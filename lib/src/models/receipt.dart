import '../formatting/money_formatter.dart';
import '../vat_calculator.dart';
import '../money.dart';
import 'receipt_line.dart';

/// Scontrino chiuso e immutabile.
///
/// Un documento fiscale non si modifica: si emette e, se serve, si storna.
/// Per questo la classe non espone alcun metodo di mutazione e le righe sono
/// restituite come lista non modificabile.
class Receipt {
  Receipt({
    required this.id,
    required this.issuedAt,
    required List<ReceiptLine> lines,
    required this.documentDiscount,
    required this.paid,
    required List<VatBreakdown> vatSummary,
  })  : _lines = List<ReceiptLine>.unmodifiable(lines),
        _vatSummary = List<VatBreakdown>.unmodifiable(vatSummary);

  final String id;
  final DateTime issuedAt;
  final List<ReceiptLine> _lines;
  final List<VatBreakdown> _vatSummary;

  /// Sconto applicato all'intero documento.
  final Money documentDiscount;

  /// Importo incassato.
  final Money paid;

  List<ReceiptLine> get lines => _lines;

  /// Riepilogo IVA per aliquota, ordinato per aliquota crescente.
  List<VatBreakdown> get vatSummary => _vatSummary;

  /// Somma delle righe, al netto degli sconti di riga.
  Money get subtotal => Money.sum(_lines.map((ReceiptLine l) => l.total));

  /// Totale del documento, IVA inclusa.
  Money get total => subtotal - documentDiscount;

  /// Totale dell'imposta.
  Money get totalTax => Money.sum(_vatSummary.map((VatBreakdown v) => v.tax));

  /// Totale imponibile.
  Money get totalTaxable =>
      Money.sum(_vatSummary.map((VatBreakdown v) => v.taxable));

  /// Resto da restituire al cliente.
  Money get change => paid - total;

  /// Numero di articoli venduti.
  num get itemCount =>
      _lines.fold<num>(0, (num acc, ReceiptLine l) => acc + l.quantity);

  @override
  String toString() => 'Receipt($id, ${_lines.length} righe, '
      'totale ${const PlainMoneyFormatter().format(total)})';
}
