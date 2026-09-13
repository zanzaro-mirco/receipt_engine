# receipt_engine

Motore di calcolo per scontrini fiscali italiani: righe, sconti, IVA multi-aliquota,
storni e resi, arrotondamenti e resto. **Logica pura in Dart**, senza dipendenze da
Flutter, database o I/O.

[![pub package](https://img.shields.io/pub/v/receipt_engine.svg)](https://pub.dev/packages/receipt_engine)
[![pub points](https://img.shields.io/pub/points/receipt_engine)](https://pub.dev/packages/receipt_engine/score)
[![CI](https://github.com/zanzaro-mirco/receipt_engine/actions/workflows/ci.yml/badge.svg)](https://github.com/zanzaro-mirco/receipt_engine/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Perché esiste

Nasce da un problema reale incontrato lavorando su software per registratori di cassa:
il calcolo di uno scontrino sembra banale finché non ci si scontra con gli arrotondamenti.
Se l'imposta si calcola riga per riga, la somma può differire di qualche centesimo
dall'imposta calcolata sul totale — e uno scontrino che non quadra per un centesimo
è un problema contabile, non un dettaglio estetico.

Questo pacchetto isola quella logica in un modulo testabile in millisecondi,
riutilizzabile da un'app mobile, da un backend o da un tool a riga di comando.

## Scelte di progetto

| Scelta | Motivo |
|---|---|
| Importi in centesimi (`Money`), mai `double` | `0.1 + 0.2 != 0.3` in virgola mobile binaria. Sul denaro non è accettabile |
| IVA scorporata sul totale per aliquota, non per riga | È il requisito normativo, ed evita che gli arrotondamenti di riga si accumulino |
| Imposta derivata per differenza dall'imponibile | Garantisce l'invariante `imponibile + imposta == lordo`, sempre |
| `Receipt` immutabile, `ReceiptBuilder` mutabile | Un documento fiscale non si modifica: si emette e semmai si storna |
| Il reso è un secondo documento, con importi negativi | Rende sommabili scontrini e resi: il totale di giornata è la somma di tutto, senza casi particolari |
| Si rimborsa l'incassato di riga, non il totale di riga | Con uno sconto di documento le due cose differiscono, e rimborsare la seconda restituirebbe anche lo sconto |
| Resi parziali con arrotondamento cumulativo | Tre resi da un pezzo devono restituire esattamente quanto un reso da tre |
| `VatRate` come classe e non come `enum` | Le aliquote cambiano per legge e per paese: un enum imporrebbe un rilascio a ogni variazione |
| Sconti polimorfi invece di uno `switch` | Aggiungere un "3x2" non richiede di modificare il calcolo esistente |
| Ripartizione dello sconto come strategia sostituibile | È una scelta contabile, non un dettaglio di calcolo |
| Formattazione fuori dal value object | Cambia con la lingua e col contesto: non deve stare nel dominio |
| Zero dipendenze a runtime | Il dominio non deve sapere che esistono Flutter o un database |

## Installazione

```bash
dart pub add receipt_engine
```

```dart
import 'package:receipt_engine/receipt_engine.dart';
```

L'API completa è su
[pub.dev/documentation/receipt_engine](https://pub.dev/documentation/receipt_engine/latest/).

## Esempio

```dart
import 'package:receipt_engine/receipt_engine.dart';

void main() {
  final Receipt receipt = ReceiptBuilder(id: 'T-0001')
      .addLine(
        description: 'Caffè',
        unitPrice: Money.fromEuro(1.20),
        vatRate: VatRate.reduced,
        quantity: 2,
      )
      .addLine(
        description: 'Vino',
        unitPrice: Money.fromEuro(12.20),
        vatRate: VatRate.standard,
        discount: Discount.percent(10),
      )
      .applyDocumentDiscount(Discount.amount(Money.fromEuro(1)))
      .close(paid: Money.fromEuro(20));

  const MoneyFormatter fmt = ItalianMoneyFormatter();
  print(fmt.format(receipt.total));   // 12,38 €
  print(fmt.format(receipt.change));  // 7,62 €

  for (final VatBreakdown v in receipt.vatSummary) {
    print(v); // IVA 10%: imponibile ..., imposta ...
  }
}
```

Il cliente riporta il vino. Lo scontrino non si tocca: si emette un reso.

```dart
final ReturnReceipt reversal =
    ReturnBuilder(id: 'R-0001', original: receipt).addLine(1).close();

print(fmt.format(reversal.refund));                // 10,16 € da restituire
print(fmt.format(receipt.lines[1].total));         // 10,98 € il totale di riga
print(fmt.format(receipt.total + reversal.total)); //  2,22 € resta il caffè
```

Il rimborso è 10,16 e non 10,98 perché su quella riga il cliente aveva già
goduto della sua quota di sconto di documento. Il riepilogo IVA del reso è
quello dello scontrino con il segno cambiato, e la somma dei due torna a zero
sulle righe rese — imposta compresa.

L'esempio completo, eseguibile, è in
[`example/receipt_engine_example.dart`](example/receipt_engine_example.dart).

## Struttura

```
lib/
  receipt_engine.dart              API pubblica
  src/
    money.dart                     valore monetario in centesimi
    vat_calculator.dart            scorporo dell'imposta
    discount_allocator.dart        strategia di ripartizione dello sconto
    vat_summary_calculator.dart    ripartizione dello sconto e riepilogo per aliquota
    receipt_builder.dart           ciclo di vita dello scontrino
    return_builder.dart            ciclo di vita del reso
    formatting/money_formatter.dart
    models/
      vat_rate.dart  discount.dart  receipt_line.dart
      receipt.dart   return_receipt.dart
example/                           programma eseguibile: emissione e storno
test/                              invarianti, contratto dei sottotipi, allocazione
```

Le scelte architetturali e i principi applicati sono in [ARCHITECTURE.md](ARCHITECTURE.md).

## Test

```bash
dart pub get
dart test
dart test --coverage=coverage
```

La pipeline misura anche il punteggio di pub.dev a ogni push, con
[`pana`](https://pub.dev/packages/pana), e fallisce se scende sotto 130 su 160:
un criterio scritto dove può fallire vale più dello stesso criterio scritto in un
documento. `pana` non gira su Windows — il suo sandbox rifiuta i percorsi con i due
punti dei dischi — quindi la CI non è una comodità, è l'unico posto dove quel numero
esiste.

I test non verificano solo i casi felici. Due esempi di invarianti verificate:

- `imponibile + imposta == lordo` per **ogni** importo da 1 a 2000 centesimi e per ogni aliquota;
- la somma dei lordi per aliquota è sempre uguale al totale del documento, anche in presenza
  di uno sconto di documento che va distribuito fra aliquote diverse;
- il contratto di `Discount` — mai negativo, mai superiore alla base — vale per **ogni**
  sottotipo, incluso uno definito dentro il file di test per dimostrare che la gerarchia
  è davvero aperta all'estensione;
- lo scorporo di un importo negativo è esattamente l'opposto di quello positivo, su
  ottomila combinazioni di importo e aliquota: è la proprietà su cui si regge il
  riepilogo IVA dei resi;
- comunque si spezzi il reso di una riga — un pezzo alla volta, in qualunque ordine —
  la somma dei rimborsi è esattamente quanto quella riga aveva incassato, verificato su
  millequattrocento combinazioni di prezzo e quantità.

In più, in `test/properties`, sette invarianti verificate su scontrini **generati** invece
che scelti: è lì che si rompono gli arrotondamenti, perché nessuno scrive a mano «2,04 € per
1,8 kg con l'8% di sconto». Hanno già trovato un difetto vero — l'ultima tranche di un reso
su merce a peso veniva rifiutata — e si sono ridotti da soli al caso minimo che lo mostra.

Il seme è fisso, così un fallimento è sempre riproducibile. Per cercare più a fondo:

```bash
PROPERTY_SEED=12345 dart test test/properties
```

## Stato e prossimi passi

Pubblicato su [pub.dev](https://pub.dev/packages/receipt_engine) con **160/160** al
[punteggio](https://pub.dev/packages/receipt_engine/score).

Quello che manca, in ordine di quanto lo chiederebbe chi lo sta già usando:

- ⬜ Serializzazione JSON, per il trasporto verso un backend
- ⬜ Pagamenti misti (contanti ed elettronico sulla stessa transazione)

E una cosa che **non** arriverà, che è diverso dal mancare. Fino alla `0.3.1` questa riga
prometteva il «supporto ad aliquote di altri paesi»: la promessa è ritirata. Dalla `0.4.0`
un'aliquota è un `num`, quindi il 5,5% francese o il 13,5% irlandese si **calcolano** senza
problemi — ma sapere quale bene sta a quale aliquota, quando vale il reverse charge e come
si numera un documento in un altro ordinamento è lavoro di dominio, non di aritmetica.
`receipt_engine` resta un motore a IVA italiana con i conti aperti a qualunque percentuale,
e chi ha bisogno delle regole di un altro paese sa già, leggendo questa riga, che qui non
le trova.

<!-- I marcatori sono simboli e non caselle Markdown `- [ ]`: dartdoc legge
     `[x]` come un riferimento a un elemento del codice e la pagina del
     pacchetto su pub.dev si riempirebbe di riferimenti irrisolti. -->

## Licenza

MIT
