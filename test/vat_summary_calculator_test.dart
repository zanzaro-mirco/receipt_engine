import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

ReceiptLine line(int cents, VatRate rate) => ReceiptLine(
      description: 'x',
      unitPrice: Money(cents),
      vatRate: rate,
    );

void main() {
  const VatSummaryCalculator calculator = VatSummaryCalculator();

  test('raggruppa per aliquota e ordina in modo crescente', () {
    final List<VatBreakdown> summary = calculator.build(
      lines: <ReceiptLine>[
        line(1220, VatRate.ordinaria),
        line(200, VatRate.superRidotta),
        line(100, VatRate.superRidotta),
      ],
      documentDiscount: const Money.zero(),
    );

    expect(summary.length, 2);
    expect(summary.first.rate, VatRate.superRidotta);
    expect(summary.first.gross, const Money(300));
    expect(summary.last.tax, const Money(220));
  });

  test('si testa senza costruire uno scontrino', () {
    // È il beneficio concreto dell'estrazione da ReceiptBuilder: prima questa
    // logica si poteva verificare solo aprendo e chiudendo un documento.
    final List<VatBreakdown> summary = calculator.build(
      lines: <ReceiptLine>[line(1000, VatRate.esente)],
      documentDiscount: const Money.zero(),
    );
    expect(summary.single.tax, const Money.zero());
  });

  test('un allocatore diverso cambia il riepilogo senza toccare il calcolo',
      () {
    const VatSummaryCalculator custom =
        VatSummaryCalculator(allocator: _AllOnLastAllocator());

    final List<VatBreakdown> summary = custom.build(
      lines: <ReceiptLine>[
        line(1000, VatRate.superRidotta),
        line(1000, VatRate.ordinaria),
      ],
      documentDiscount: const Money(200),
    );

    expect(summary.first.gross, const Money(1000)); // intatto
    expect(summary.last.gross, const Money(800)); // assorbe tutto
    expect(
        Money.sum(summary.map((VatBreakdown v) => v.gross)), const Money(1800));
  });
}

/// Strategia alternativa: lo sconto grava tutto sull'aliquota più alta.
class _AllOnLastAllocator implements DiscountAllocator {
  const _AllOnLastAllocator();

  @override
  List<Money> allocate({
    required List<Money> grossByRate,
    required Money subtotal,
    required Money discount,
  }) {
    if (grossByRate.isEmpty) return const <Money>[];
    return <Money>[
      ...grossByRate.take(grossByRate.length - 1),
      grossByRate.last - discount,
    ];
  }
}
