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
- **Il reso non porta con sé un metodo di rimborso.** Contante, storno sulla carta o
  buono sono una decisione di cassa; qui c'è solo l'importo.
