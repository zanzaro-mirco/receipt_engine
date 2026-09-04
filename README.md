# receipt_engine

Motore di calcolo per scontrini fiscali italiani: righe, sconti, IVA multi-aliquota,
arrotondamenti e resto. **Logica pura in Dart**, senza dipendenze da Flutter, database o I/O.

[![CI](https://github.com/zanzaro-mirco/receipt_engine/actions/workflows/ci.yml/badge.svg)](https://github.com/zanzaro-mirco/receipt_engine/actions/workflows/ci.yml)

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

## Esempio

```dart
import 'package:receipt_engine/receipt_engine.dart';

void main() {
  final Receipt receipt = ReceiptBuilder(id: 'T-0001')
      .addLine(
        description: 'Caffè',
        unitPrice: Money.fromEuro(1.20),
        vatRate: VatRate.ridotta,
        quantity: 2,
      )
      .addLine(
        description: 'Vino',
        unitPrice: Money.fromEuro(12.20),
        vatRate: VatRate.ordinaria,
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
final ReturnReceipt storno =
    ReturnBuilder(id: 'R-0001', original: receipt).addLine(1).close();

print(fmt.format(storno.refund));               // 10,16 € da restituire
print(fmt.format(receipt.lines[1].total));      // 10,98 € il totale di riga
print(fmt.format(receipt.total + storno.total)); //  2,22 € resta il caffè
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

## Stato e prossimi passi

Il pacchetto è funzionante e coperto da test. Cosa manca per considerarlo completo:

- [x] Storni e resi (documento di reso collegato allo scontrino originale)
- [ ] Pagamenti misti (contanti + elettronico sulla stessa transazione)
- [ ] Serializzazione JSON per il trasporto verso un backend
- [ ] Supporto ad aliquote di altri paesi (la struttura è già pronta)

## Licenza

MIT
