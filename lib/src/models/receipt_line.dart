import '../formatting/money_formatter.dart';
import '../money.dart';
import 'discount.dart';
import 'vat_rate.dart';

/// Riga di uno scontrino.
///
/// Il prezzo unitario è IVA inclusa, come da prassi del retail italiano:
/// il cliente vede il prezzo esposto, lo scorporo è un fatto contabile.
class ReceiptLine {
  /// Crea una riga.
  ///
  /// Rifiuta una [quantity] non positiva e un [unitPrice] negativo: una
  /// riga che toglie valore allo scontrino è uno sconto o un reso, e per
  /// entrambi esiste già il suo modo di esprimersi.
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

  /// Descrizione stampata sullo scontrino.
  final String description;

  /// Prezzo unitario, **IVA inclusa**.
  final Money unitPrice;

  /// Aliquota della riga. Determina il gruppo nel riepilogo IVA.
  final VatRate vatRate;

  /// Quantità venduta. È un [num] e non un [int] perché la merce a peso
  /// si vende a frazioni: 1,5 kg è una quantità legittima.
  final num quantity;

  /// Sconto della singola riga, indipendente da quello di documento.
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
