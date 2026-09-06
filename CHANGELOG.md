# Changelog

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
