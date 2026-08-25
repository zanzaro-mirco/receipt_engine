import '../formatting/money_formatter.dart';
import '../money.dart';
import 'discount.dart';
import 'vat_rate.dart';

/// Riga di uno scontrino.
///
/// Il prezzo unitario è IVA inclusa, come da prassi del retail italiano:
/// il cliente vede il prezzo esposto, lo scorporo è un fatto contabile.
class ReceiptLine {
  ReceiptLine({
    required this.description,
    required this.unitPrice,
    required this.vatRate,
    this.quantity = 1,
    this.discount,
  }) {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Deve essere positiva');
    }
    if (unitPrice.isNegative) {
      throw ArgumentError.value(
          unitPrice, 'unitPrice', 'Non può essere negativo');
    }
  }

  final String description;
  final Money unitPrice;
  final VatRate vatRate;
  final num quantity;
  final Discount? discount;

  /// Totale di riga prima dello sconto.
  Money get grossBeforeDiscount => unitPrice.multipliedBy(quantity);

  /// Importo dello sconto di riga.
  Money get discountAmount =>
      discount?.appliedTo(grossBeforeDiscount) ?? const Money.zero();

  /// Totale di riga IVA inclusa, al netto dello sconto.
  Money get total => grossBeforeDiscount - discountAmount;

  @override
  String toString() =>
      '$description x$quantity ${const PlainMoneyFormatter().format(total)} '
      '($vatRate)';
}
