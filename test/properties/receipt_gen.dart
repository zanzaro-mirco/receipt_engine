import 'dart:math';

import 'package:receipt_engine/receipt_engine.dart';

import 'property.dart';

/// Descrizione di una riga, prima che diventi una [ReceiptLine].
///
/// Serve un livello intermedio perché la semplificazione lavora su dati, non
/// su oggetti costruiti: `ReceiptLine` valida nel costruttore, e un candidato
/// semplificato non valido interromperebbe la ricerca invece di scartarsi.
class LineSpec {
  /// Crea la descrizione di una riga.
  const LineSpec({
    required this.unitPriceCents,
    required this.ratePercentage,
    required this.quantityTenths,
    required this.discountPercent,
  });

  /// Prezzo unitario in centesimi, IVA inclusa.
  final int unitPriceCents;

  /// Percentuale dell'aliquota: 22 per il 22%.
  final int ratePercentage;

  /// Quantità in decimi di unità.
  ///
  /// Intera, e non un `double`, perché è così che la quantità viene inserita
  /// davvero: la bilancia manda 3 ettogrammi, non 0,30000000000000004 kg. È
  /// anche l'unico modo di generare tranche che sommano *in decimale* alla
  /// quantità venduta, che è il caso in cui i resi parziali si rompono.
  final int quantityTenths;

  /// Sconto di riga in percentuale. Zero significa nessuno sconto.
  final int discountPercent;

  /// Quantità come la vede il dominio.
  num get quantity =>
      quantityTenths % 10 == 0 ? quantityTenths ~/ 10 : quantityTenths / 10;

  /// Aliquota come la vede il dominio.
  VatRate get rate => VatRate(ratePercentage);

  /// Sconto come lo vede il dominio.
  Discount? get discount =>
      discountPercent == 0 ? null : Discount.percent(discountPercent);

  @override
  String toString() => 'riga(${unitPriceCents}c x $quantity, '
      'IVA $ratePercentage%'
      '${discountPercent == 0 ? '' : ', sconto $discountPercent%'})';
}

/// Descrizione di uno scontrino intero.
class ReceiptSpec {
  /// Crea la descrizione di uno scontrino.
  const ReceiptSpec(
      {required this.lines, required this.documentDiscountPercent});

  /// Le righe, nell'ordine in cui verranno inserite.
  final List<LineSpec> lines;

  /// Sconto di documento in percentuale. Zero significa nessuno sconto.
  final int documentDiscountPercent;

  /// Costruisce lo scontrino vero.
  Receipt build({String id = 'S'}) {
    final ReceiptBuilder builder = ReceiptBuilder(
      id: id,
      issuedAt: DateTime.utc(2026, 9, 12),
    );
    for (int i = 0; i < lines.length; i++) {
      final LineSpec line = lines[i];
      builder.addLine(
        description: 'Articolo $i',
        unitPrice: Money(line.unitPriceCents),
        vatRate: line.rate,
        quantity: line.quantity,
        discount: line.discount,
      );
    }
    if (documentDiscountPercent > 0) {
      builder.applyDocumentDiscount(Discount.percent(documentDiscountPercent));
    }
    // Il pagamento non c'entra con nessuna delle proprietà: si paga esatto.
    return builder.close(paid: builder.currentTotal);
  }

  @override
  String toString() => <String>[
        'scontrino:',
        for (final LineSpec line in lines) '  $line',
        if (documentDiscountPercent > 0)
          '  sconto di documento $documentDiscountPercent%',
      ].join('\n');
}

/// Le aliquote fra cui pescare: quelle italiane vere, zero compreso.
const List<int> _ratePercentages = <int>[0, 4, 5, 10, 22];

/// Generatore di righe.
///
/// I prezzi restano piccoli apposta: un controesempio da 3,17 € si legge, uno
/// da 91.482,63 € no, e gli arrotondamenti che interessano non dipendono
/// dall'ordine di grandezza.
final Gen<LineSpec> lineGen = Gen<LineSpec>(
  (Random r) => LineSpec(
    unitPriceCents: 1 + r.nextInt(5000),
    ratePercentage: _ratePercentages[r.nextInt(_ratePercentages.length)],
    // Da un decimo a cinque unità. I valori non multipli di dieci sono la
    // merce a peso, ed è lì che le quantità smettono di essere esatte.
    quantityTenths: 1 + r.nextInt(50),
    // Lo sconto di riga c'è in un caso su tre: uno scontrino in cui ogni riga
    // è scontata non somiglia a niente.
    discountPercent: r.nextInt(3) == 0 ? 1 + r.nextInt(60) : 0,
  ),
  shrink: _shrinkLine,
);

Iterable<LineSpec> _shrinkLine(LineSpec line) sync* {
  if (line.discountPercent != 0) {
    yield LineSpec(
      unitPriceCents: line.unitPriceCents,
      ratePercentage: line.ratePercentage,
      quantityTenths: line.quantityTenths,
      discountPercent: 0,
    );
  }
  if (line.ratePercentage != 22) {
    yield LineSpec(
      unitPriceCents: line.unitPriceCents,
      ratePercentage: 22,
      quantityTenths: line.quantityTenths,
      discountPercent: line.discountPercent,
    );
  }
  // La quantità scende verso il basso ma non verso l'unità intera: se il
  // difetto sta nelle frazioni, portarla a 1 lo farebbe sparire e la ricerca
  // risalirebbe. Prima si prova a dimezzarla, poi a scendere di un decimo.
  if (line.quantityTenths > 1) {
    for (final int tenths in <int>[
      line.quantityTenths ~/ 2,
      line.quantityTenths - 1
    ]) {
      if (tenths >= 1 && tenths != line.quantityTenths) {
        yield LineSpec(
          unitPriceCents: line.unitPriceCents,
          ratePercentage: line.ratePercentage,
          quantityTenths: tenths,
          discountPercent: line.discountPercent,
        );
      }
    }
  }
  for (final int cents in <int>[
    line.unitPriceCents ~/ 2,
    line.unitPriceCents - 1
  ]) {
    if (cents >= 1 && cents != line.unitPriceCents) {
      yield LineSpec(
        unitPriceCents: cents,
        ratePercentage: line.ratePercentage,
        quantityTenths: line.quantityTenths,
        discountPercent: line.discountPercent,
      );
    }
  }
}

/// Generatore di scontrini, da una a sei righe.
final Gen<ReceiptSpec> receiptGen = Gen<ReceiptSpec>(
  (Random r) => ReceiptSpec(
    lines: <LineSpec>[
      for (int i = 0; i < 1 + r.nextInt(6); i++) lineGen.generate(r),
    ],
    documentDiscountPercent: discountPercentOf(r),
  ),
  shrink: _shrinkReceipt,
);

/// Sconto di documento: assente in tre casi su quattro.
int discountPercentOf(Random r) => r.nextInt(4) == 0 ? 1 + r.nextInt(40) : 0;

Iterable<ReceiptSpec> _shrinkReceipt(ReceiptSpec spec) sync* {
  // Prima si toglie roba: meno righe è la semplificazione che fa capire di più.
  if (spec.documentDiscountPercent != 0) {
    yield ReceiptSpec(lines: spec.lines, documentDiscountPercent: 0);
  }
  if (spec.lines.length > 1) {
    for (int i = 0; i < spec.lines.length; i++) {
      yield ReceiptSpec(
        lines: <LineSpec>[...spec.lines]..removeAt(i),
        documentDiscountPercent: spec.documentDiscountPercent,
      );
    }
  }
  // Poi si semplifica quello che resta, una riga per volta.
  for (int i = 0; i < spec.lines.length; i++) {
    for (final LineSpec simpler in _shrinkLine(spec.lines[i])) {
      final List<LineSpec> lines = <LineSpec>[...spec.lines];
      lines[i] = simpler;
      yield ReceiptSpec(
        lines: lines,
        documentDiscountPercent: spec.documentDiscountPercent,
      );
    }
  }
}

/// Spezza [quantityTenths] in tranche che sommano **in decimale** allo stesso
/// valore.
///
/// Deterministica, e non casuale, per una ragione imparata rompendoci il naso:
/// una proprietà deve essere una **funzione pura del valore generato**. Con una
/// sorgente casuale condivisa, ogni rivalutazione della stessa `spec` produce
/// tranche diverse — e la semplificazione, che riprova il candidato decine di
/// volte, insegue un bersaglio che si sposta. Il controesempio che ne esce è
/// riproducibile solo per finta: lo si rilegge e i conti non tornano.
///
/// I decimi sono interi, quindi la partizione è esatta per costruzione: è la
/// somma dei `double` corrispondenti che può non tornare, ed è precisamente il
/// caso che si vuole mettere alla prova.
List<int> partitionTenths(int quantityTenths) {
  if (quantityTenths <= 1) return <int>[quantityTenths];
  final int pieces = quantityTenths < 3 ? quantityTenths : 3;
  final int base = quantityTenths ~/ pieces;
  final int leftover = quantityTenths - base * pieces;
  return <int>[
    for (int i = 0; i < pieces; i++) base + (i < leftover ? 1 : 0),
  ];
}
