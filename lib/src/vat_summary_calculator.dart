import 'discount_allocator.dart';
import 'models/receipt_line.dart';
import 'models/vat_rate.dart';
import 'money.dart';
import 'vat_calculator.dart';

/// Costruisce il riepilogo IVA di un documento.
///
/// Prima questa logica stava dentro `ReceiptBuilder`, che si ritrovava a fare
/// tre cose: gestire lo stato aperto/chiuso, ripartire lo sconto di documento
/// e calcolare l'imposta. Separandola, il builder torna a occuparsi solo del
/// ciclo di vita del documento e questo calcolo diventa testabile da solo,
/// senza costruire uno scontrino.
class VatSummaryCalculator {
  const VatSummaryCalculator({
    VatCalculator calculator = const VatCalculator(),
    DiscountAllocator allocator = const ProportionalDiscountAllocator(),
  })  : _calculator = calculator,
        _allocator = allocator;

  final VatCalculator _calculator;
  final DiscountAllocator _allocator;

  /// Riepilogo per aliquota, ordinato in modo crescente.
  ///
  /// L'imposta si calcola sul totale per aliquota, non riga per riga: è il
  /// requisito normativo ed evita che gli arrotondamenti di riga si accumulino.
  List<VatBreakdown> build({
    required List<ReceiptLine> lines,
    required Money documentDiscount,
  }) {
    final Map<VatRate, Money> grossByRate = <VatRate, Money>{};
    for (final ReceiptLine line in lines) {
      grossByRate[line.vatRate] =
          (grossByRate[line.vatRate] ?? const Money.zero()) + line.total;
    }

    final List<VatRate> rates = grossByRate.keys.toList()
      ..sort((VatRate a, VatRate b) => a.compareTo(b));

    final List<Money> gross =
        rates.map((VatRate r) => grossByRate[r]!).toList();
    final Money subtotal = Money.sum(gross);

    final List<Money> net = _allocator.allocate(
      grossByRate: gross,
      subtotal: subtotal,
      discount: documentDiscount,
    );

    return <VatBreakdown>[
      for (int i = 0; i < rates.length; i++)
        _calculator.splitFromGross(net[i], rates[i]),
    ];
  }
}
