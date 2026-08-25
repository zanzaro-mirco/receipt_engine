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
  vat_calculator.dart           scorporo dell'imposta
  discount_allocator.dart       strategia di ripartizione dello sconto
  vat_summary_calculator.dart   riepilogo per aliquota
  receipt_builder.dart          ciclo di vita del documento
  formatting/money_formatter.dart   presentazione degli importi
```

## Pattern usati

| Pattern | Dove | Perché |
|---|---|---|
| **Value Object** | `Money` | L'importo ha identità per valore, non per riferimento. Rende impossibile confondere un numero con un importo |
| **Builder** | `ReceiptBuilder` | Il documento si costruisce per passi e si chiude una volta sola. La macchina a stati è minima: aperto o chiuso |
| **Strategy** | `DiscountAllocator` | Il criterio di ripartizione dello sconto è una scelta contabile, non un dettaglio di calcolo: si sostituisce senza riaprire il motore |
| **Polimorfismo al posto del branching** | `Discount` | Ogni sconto sa calcolarsi da solo |
| **Sealed class** | `Discount` | Estendibile, ma il compilatore segnala ogni `switch` incompleto |
| **Separazione dominio / presentazione** | `MoneyFormatter` | La formattazione cambia per locale e per contesto: non deve stare nel dominio |

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
