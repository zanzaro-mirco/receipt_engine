# Architettura e scelte di progetto

Documento breve: cosa c'è dentro, perché è organizzato così, e quali principi
sono stati applicati (o consapevolmente non applicati).

## Struttura

```
lib/src/
  money.dart                    value object: aritmetica in centesimi
  models/
    vat_rate.dart               aliquota
    discount.dart               gerarchia sealed degli sconti
    receipt_line.dart           riga
    receipt.dart                documento immutabile
    return_receipt.dart         documento di reso, a segno invertito
  vat_calculator.dart           scorporo dell'imposta
  discount_allocator.dart       strategia di ripartizione dello sconto
  vat_summary_calculator.dart   ripartizione dello sconto e riepilogo per aliquota
  receipt_builder.dart          ciclo di vita dello scontrino
  return_builder.dart           ciclo di vita del reso
  formatting/money_formatter.dart   presentazione degli importi
```

## Pattern usati

| Pattern | Dove | Perché |
|---|---|---|
| **Value Object** | `Money` | L'importo ha identità per valore, non per riferimento. Rende impossibile confondere un numero con un importo |
| **Builder** | `ReceiptBuilder`, `ReturnBuilder` | Il documento si costruisce per passi e si chiude una volta sola. La macchina a stati è minima — aperto o chiuso — ed è la stessa per entrambi |
| **Strategy** | `DiscountAllocator` | Il criterio di ripartizione dello sconto è una scelta contabile, non un dettaglio di calcolo: si sostituisce senza riaprire il motore |
| **Polimorfismo al posto del branching** | `Discount` | Ogni sconto sa calcolarsi da solo |
| **Sealed class** | `Discount` | Estendibile, ma il compilatore segnala ogni `switch` incompleto |
| **Separazione dominio / presentazione** | `MoneyFormatter` | La formattazione cambia per locale e per contesto: non deve stare nel dominio |
| **Documento come fatto immutabile** | `Receipt`, `ReturnReceipt` | Uno scontrino emesso non si corregge: se ne emette un secondo che lo storna. Il modello rende questa l'unica strada possibile |

## Storni e resi

Un documento fiscale non si modifica. Se il cliente riporta la merce non si
riapre lo scontrino: se ne emette un altro, collegato al primo, che ne storna
una parte. È il punto in cui l'immutabilità di `Receipt` smette di essere una
buona abitudine e diventa il modello del dominio.

**Gli importi di un reso sono negativi.** Non è un vezzo: è quello che rende
sommabili documenti di natura diversa. Il totale di giornata è la somma di
tutto ciò che è stato emesso, scontrini e resi, senza casi particolari e senza
che qualcuno debba ricordarsi di cambiare segno. Per l'operatore, che deve
sapere quanto tirare fuori dal cassetto, c'è `ReturnReceipt.refund`, positivo.

**Si rimborsa quello che è stato incassato, non quello che è scritto sulla
riga.** Con uno sconto di documento le due cose non coincidono: la riga vale
10,98, ma dopo la ripartizione dello sconto il cliente ne ha pagati 10,16.
Rimborsare il totale di riga significherebbe restituirgli anche lo sconto. Da
qui `Receipt.netLineTotals`: il totale effettivo di ciascuna riga, la cui somma
è esattamente il totale del documento.

**Lo sconto si ripartisce una volta sola, e sulle righe.** Prima veniva
ripartito sui totali già raggruppati per aliquota. Finché l'unico consumatore
era il riepilogo IVA la differenza non si vedeva — in entrambi i casi la somma
torna — e i test passavano. Si è vista aggiungendo i resi, dove serve sapere
quanto è stato incassato per *una riga*: due ripartizioni diverse davano due
numeri che differivano di un centesimo, e uno scontrino reso per intero non
tornava a zero. Ora `VatSummaryCalculator.compute` restituisce insieme i totali
di riga e il riepilogo per aliquota, dalla stessa ripartizione, e non possono
contraddirsi. Il parametro dell'allocatore non si chiama più `grossByRate` ma
`amounts`, perché è quello che è sempre stato.

**Il riepilogo IVA del reso è lo stesso calcolo, con il segno cambiato.**
`VatSummaryCalculator.summarize` accetta coppie *(aliquota, importo)* invece di
righe di scontrino, quindi un reso ci fa passare i propri importi negativi
senza che una riga di codice venga duplicata. Che funzioni non è ovvio: dipende
dal fatto che l'arrotondamento di `Money` è half-away-from-zero, e quindi
simmetrico rispetto allo zero. Con un "half up" lo scorporo di -3,00 non
sarebbe l'opposto di quello di +3,00, e uno scontrino stornato per intero
lascerebbe un centesimo di imposta appeso. La proprietà è verificata su ottomila
combinazioni in `vat_calculator_test.dart`, perché è portante e non deve
rompersi in silenzio.

**Un reso parziale usa l'arrotondamento cumulativo.** L'importo di una riga resa
non è *netto x quantità resa / venduta* arrotondato, ma la differenza fra due
arrotondamenti cumulativi: quanto sarebbe stato rimborsato dopo questo reso,
meno quanto lo era già stato. Con la formula diretta ogni reso parziale sbaglia
per conto proprio fino a mezzo centesimo: su una riga da 3 centesimi venduta in
4 pezzi, resa un pezzo alla volta, se ne restituiscono 4 — più di quanto
incassato. Con quella cumulativa la somma dei rimborsi di una riga resa per
intero è esattamente il suo netto, comunque la si sia spezzata.

**Non si rende più di quanto venduto.** Il conteggio comprende i resi già
emessi, che il chiamante passa a `ReturnBuilder`: senza, tre resi parziali da un
pezzo permetterebbero di restituire tre volte un articolo venduto una volta
sola. Il pacchetto non ha persistenza, quindi non può recuperarli da sé — è una
scelta, non una dimenticanza, ed è scritta fra le semplificazioni.

## SOLID, punto per punto

**Single Responsibility.** Il `ReceiptBuilder` faceva tre cose: gestire lo stato,
ripartire lo sconto di documento e calcolare l'imposta. Le ultime due sono uscite in
`VatSummaryCalculator` e `DiscountAllocator`. Il beneficio non è estetico: il calcolo
del riepilogo IVA ora si testa senza costruire uno scontrino.

**Open/Closed.** `Discount.appliedTo` era uno `switch` su un enum: aggiungere un
"3x2" significava modificare il metodo di calcolo. Ora è polimorfo. Il test
`discount_test.dart` definisce un `ThreeForTwoDiscount` **dentro il file di test** e
funziona senza toccare una riga del pacchetto: è la dimostrazione che il principio è
rispettato, non solo dichiarato.

La seconda prova è arrivata dai resi: il riepilogo IVA di un documento nuovo, con
importi negativi, non ha richiesto un solo `if` dentro `VatCalculator`. Ha richiesto
di far accettare a `summarize` una coppia *(aliquota, importo)* invece di una riga di
scontrino — cioè di togliere un'ipotesi, non di aggiungere un caso.

**Liskov.** Il contratto di `Discount.appliedTo` è esplicito nella documentazione —
il risultato non è mai negativo e non supera mai la base — ed è verificato su tutti i
sottotipi con lo stesso test parametrico.

**Interface Segregation.** Le interfacce qui sono già minime: `DiscountAllocator` e
`MoneyFormatter` hanno un metodo ciascuna.

**Dependency Inversion.** `ReceiptBuilder` riceve un `VatSummaryCalculator` che riceve
un `DiscountAllocator`: ogni livello dipende da un'astrazione e non costruisce le
proprie dipendenze.

## Property-based testing, e le due cose che ha trovato

I test a esempi dimostrano che il codice funziona sui casi a cui ha pensato chi lo ha
scritto. È un limite serio in un motore di calcolo: gli arrotondamenti si rompono sui
valori che a mano non si scelgono — 2,04 € per 1,8 kg, uno sconto dell'8% su tre righe
con aliquote diverse.

In `test/properties` ci sono sette invarianti verificate su scontrini **generati**: lo
scorporo ricompone il lordo, il riepilogo somma al totale, lo sconto di documento non fa
sparire centesimi, un reso totale è l'esatto opposto dello scontrino, spezzarlo non cambia
il rimborso, l'ordine delle righe non cambia il totale.

Il motorino è scritto a mano — un `Gen<T>` con generazione e semplificazione, un `forAll`,
una sessantina di righe — per una ragione verificabile: `glados`, l'unico pacchetto Dart
del genere, dichiara `sdk: >=2.12.0 <3.0.0` e non è compatibile con Dart 3.

**La parte che conta è la semplificazione, non la generazione.** Il primo controesempio
utile è uscito così:

```
Generato a partire da:   riga(3469c x 1.5, IVA 22%, sconto 8%)
Controesempio più semplice:   riga(1c x 0.3, IVA 22%)
```

Da «uno scontrino rotto» a «un centesimo, tre etti»: è la differenza fra una segnalazione
e una diagnosi.

Il seme della sorgente casuale è **fisso**, e non diverso ogni volta. Una suite che
fallisce su un caso che non si sa riprodurre è una suite che qualcuno disattiva. Per
cercare più a fondo si allarga da fuori, senza toccare il codice:

```bash
PROPERTY_SEED=12345 dart test test/properties
```

### Primo ritrovamento: l'ultimo etto non si poteva rendere

Le quantità sono `num`, e per la merce a peso sono `double`. Tre tranche da 0,1 sommano a
`0,30000000000000004`, non a `0,3`: il residuo prima della terza diventava
`0.09999999999999998` e il reso veniva **rifiutato**. Alla cassa significa non poter
rimborsare l'ultimo pezzo di un articolo a peso.

La correzione è una tolleranza relativa di `1e-9` sui confronti fra quantità — nove ordini
di grandezza sopra il rumore dei `double`, sei sotto il grammo. La via pulita sarebbe stata
rappresentare le quantità come interi scalati, che è ciò che `Money` fa con gli importi:
non si può, perché la quantità arriva da fuori come `num` qualunque e un pacchetto
pubblicato non cambia il tipo di un parametro pubblico per un caso limite.

### Secondo ritrovamento: un limite, non un difetto

Questo non lo avevo previsto. Una riga da 1,72 € al 22% porta 31 centesimi di imposta. Resa
in due tranche da mezzo, ogni documento scorpora 86 centesimi e ne dichiara 16: **16 + 16 fa
32**. L'imposta stornata supera di un centesimo quella incassata.

Non è un errore di calcolo. Ogni documento di reso è un documento fiscale a sé e scorpora
sui propri importi, come prescrive la norma: due arrotondamenti indipendenti non fanno
l'arrotondamento della somma. Lo scarto è misurato e cresce come metà del numero di
documenti — un centesimo su tre tranche, dieci su venti — mentre **il denaro rimborsato
resta esatto in ogni caso**.

Correggerlo si potrebbe, facendo dipendere l'imposta di un documento da quella dei
precedenti. Non si deve: un documento fiscale deve poter essere ricalcolato da solo, e un
reso la cui imposta non è lo scorporo dei suoi importi è un reso che non supera un
controllo.

Quindi la proprietà non pretende zero: pretende che lo scarto **resti legato al numero di
documenti**. Se un giorno lo superasse, vorrebbe dire che gli errori hanno smesso di essere
indipendenti e hanno cominciato a comporsi — e quello sarebbe un difetto vero.

## Dove ho consapevolmente semplificato

- **`VatCalculator` è una classe concreta, non un'interfaccia.** Lo scorporo è
  aritmetica normata: non esistono implementazioni alternative sensate. Se servisse
  supportare regimi diversi, diventerebbe un'interfaccia.
- **Nessun sistema di eventi né persistenza.** È una libreria di calcolo: aggiungerli
  la trasformerebbe in qualcos'altro.
- **`Money` usa `int`, non `BigInt`.** Con `int` a 64 bit il limite è oltre i
  92 miliardi di euro: per uno scontrino è abbondante.
- **I resi precedenti li passa il chiamante.** `ReturnBuilder` non può cercarseli: il
  pacchetto non ha persistenza e non deve averla. Il prezzo è che chi lo usa deve
  ricordarsi di passarli, altrimenti il controllo "non si rende più di quanto venduto"
  guarda solo il documento corrente. Il costruttore rifiuta almeno i resi di un altro
  scontrino, che è l'errore più facile da fare.
- **Nessuna numerazione fiscale dei documenti.** Gli identificativi sono stringhe che
  arrivano da fuori: la numerazione progressiva è materia di normativa e di
  dispositivo, non di aritmetica.
- **Non esiste il reso di un reso, né un termine oltre il quale non si rende.** Sono
  regole commerciali, non fiscali: cambiano da catena a catena e starebbero sopra
  questo livello.
- **Le regole fiscali di altri paesi non ci sono, e non è un ritardo.** Dalla `0.4.0`
  l'aliquota è un `num`, così il 5,5% francese si esprime e si scorpora: l'aritmetica è
  aperta a qualunque percentuale. Il dominio no. Sapere quale bene sta a quale aliquota o
  quando vale il reverse charge è conoscenza normativa che invecchia, e tenerla dentro un
  pacchetto di calcolo significherebbe rilasciare una versione a ogni circolare.
- **Il reso non porta con sé un metodo di rimborso.** Contante, storno sulla carta o
  buono sono una decisione di cassa; qui c'è solo l'importo.
- **Le quantità restano `num`, con una tolleranza sui confronti.** Gli importi sono interi
  perché il denaro non ammette approssimazioni; le quantità no, perché arrivano da fuori
  come le manda una bilancia. Il prezzo è dichiarato: due quantità che differiscono di meno
  di un miliardesimo sono la stessa quantità.
- **L'imposta stornata da più documenti di reso può scostarsi di qualche centesimo da
  quella incassata.** È aritmetica di arrotondamenti indipendenti, non un difetto, e la
  sezione qui sopra spiega perché correggerla sarebbe peggio. Il denaro rimborsato invece
  torna sempre esatto.
