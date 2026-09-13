# Changelog

## 0.5.0

- **Serializzazione JSON**, con `ReceiptJson`: `encodeReceipt`, `decodeReceipt`,
  `encodeReturnReceipt`, `decodeReturnReceipt`. Nessuna modifica incompatibile e nessuna
  dipendenza nuova — il codec è scritto a mano, e restituisce una `Map` invece di una
  stringa perché `dart:convert` non entri nel pacchetto.
- **La rilettura non ricalcola.** I totali di riga al netto dello sconto e il riepilogo IVA
  vengono riletti dal documento, non rifatti passando per `ReceiptBuilder`: un documento
  fiscale emesso si rilegge, non si riemette. `ARCHITECTURE.md` spiega cosa andrebbe storto
  altrimenti.
- **Ogni documento porta uno `schemaVersion`.** Rileggere un documento scritto da una
  versione più recente del pacchetto solleva una `FormatException` invece di produrre uno
  scontrino monco. Uno schema più vecchio si legge: il controllo è asimmetrico apposta.
- **Errori distinti per causa distinta:** `FormatException` quando il problema è di
  trasporto (campo mancante, importo che non è un intero di centesimi, tipo di documento
  sbagliato), `ArgumentError` quando la forma è giusta ma il contenuto no — una quantità
  negativa la rifiuta `ReceiptLine`, che è il posto che conosce la regola.
- **Due test e non uno.** Un round-trip su scontrini generati (l'ottava proprietà) e un
  test che scrive per esteso la mappa attesa. Il secondo esiste perché il primo non può
  accorgersi di un nome di campo cambiato in scrittura *e* in lettura: verificato
  rinominando davvero un campo, la proprietà resta verde e il test del formato fallisce.
- L'esempio eseguibile ora mostra anche il giro fuori dal processo e ritorno.

## 0.4.0

- **Modifica non compatibile: `VatRate.percentage` è un `num` e non più un `int`.** La
  documentazione della classe si vantava di non essere un `enum` «perché le aliquote
  cambiano per legge e per paese», e intanto il tipo escludeva metà delle aliquote
  europee: la Francia ha il 5,5% e il 2,1%, l'Irlanda il 13,5%. Ora
  `const VatRate(5.5, label: 'Taux réduit')` si scrive e si calcola.
  **Cosa si rompe:** solo l'assegnazione della percentuale a un `int`
  (`final int p = rate.percentage;` diventa `final num p = rate.percentage;`). Costruire
  un'aliquota da un letterale intero, confrontarla, ordinarla e scorporarla funziona
  esattamente come prima.
- **`VatRate.toString()` scrive all'italiana e senza decimali inutili:** `22%`, `5,5%`, e
  `VatRate(22.0)` resta `22%` invece di diventare `22.0%`.
- **`VatRate(22)` e `VatRate(22.0)` sono la stessa aliquota.** Lo erano già per come Dart
  confronta i numeri; ora c'è un test che lo tiene fermo, perché è ciò che impedisce al
  riepilogo IVA di spaccarsi in due righe a seconda di come è stato scritto un letterale.
- **Le sette proprietà girano anche sulle aliquote frazionarie:** il generatore pesca pure
  2,1%, 5,5% e 13,5%, cioè divisori non interi nello scorporo.
- **README onesto sui punti aperti.** La sezione «Stato e prossimi passi» annunciava il
  supporto alle aliquote di altri paesi e sosteneva che «la struttura è già pronta». La
  prima era una promessa che non intendo mantenere, la seconda era falsa — il tipo `int`
  la smentiva. Ora la sezione dice quali sono i due punti aperti veri e perché il dominio
  resta italiano.

## 0.3.1

- **Correzione: l'ultima tranche di un reso su merce a peso veniva rifiutata.** Le
  quantità sono `num`, e tre resi da 0,1 su una riga da 0,3 sommano a
  `0,30000000000000004`: il residuo diventava `0.09999999999999998` e
  `ExcessiveReturnError` scattava su un reso legittimo. I confronti fra quantità ora
  ammettono una tolleranza relativa di `1e-9`, e `remainingQuantity` restituisce **zero**
  invece del pulviscolo lasciato dalle sottrazioni fra `double`.
- **Sette test di proprietà su scontrini generati**, in `test/properties`, con
  generazione e semplificazione dei controesempi scritte a mano: `glados` non è
  compatibile con Dart 3. Sono loro ad aver trovato il difetto qui sopra, e a essersi
  ridotti da soli a «un centesimo, tre etti».
- **Dichiarato un limite che prima non era scritto:** l'imposta stornata da più documenti
  di reso può scostarsi di qualche centesimo da quella incassata, perché ogni documento
  scorpora sui propri importi. Il denaro rimborsato resta invece sempre esatto.
  `ARCHITECTURE.md` spiega perché non va corretto.

## 0.3.0

- **Modifiche non compatibili: le aliquote predefinite cambiano nome.**
  `VatRate.ordinaria`, `ridotta`, `superRidotta` ed `esente` diventano
  `standard`, `reduced`, `superReduced` ed `exempt`. Sono gli stessi termini
  usati dalle direttive europee sull'IVA, e allineano l'API pubblica al resto
  del pacchetto, che era già in inglese. Le etichette leggibili — `Ordinaria`,
  `Ridotta`, `Super ridotta`, `Esente` — non cambiano: restano il testo che
  finisce sullo scontrino.
- Il resto del rinominio riguarda i test e l'esempio, e non tocca l'API.

## 0.2.0

Prima versione pubblicata su pub.dev.

- **Storni e resi.** `ReturnReceipt` e `ReturnBuilder`: documento di reso
  collegato allo scontrino originale, totale o parziale, con riepilogo IVA a
  segno invertito e controllo che non si renda più di quanto venduto — resi
  precedenti compresi.
- `Receipt.netLineTotals`: il totale effettivo di ciascuna riga, dopo la
  ripartizione dello sconto di documento. È la base di ogni rimborso.
- Lo sconto di documento si ripartisce una volta sola, sulle righe, e il
  riepilogo per aliquota ne discende: prima erano due ripartizioni distinte che
  potevano differire di un centesimo.
- `VatSummaryCalculator.summarize` accetta coppie *(aliquota, importo)* e
  funziona su importi negativi, così il reso riusa il calcolo invece di
  duplicarlo.
- **Modifiche non compatibili:** `DiscountAllocator.allocate` prende `amounts`
  al posto di `grossByRate`; `Receipt` richiede `netLineTotals`.
- Preparazione alla pubblicazione: documentazione dartdoc su tutta l'API
  pubblica, `topics` e `issue_tracker` nel pubspec, `lints` e `test` aggiornati
  all'ultima versione. La pipeline misura il punteggio di pub.dev a ogni push e
  fallisce sotto 130 su 160.

## 0.1.0

- Primo rilascio: `Money`, `VatRate`, `VatCalculator`, `ReceiptBuilder`.
- Riepilogo IVA per aliquota, sconti di riga e di documento, calcolo del resto.
