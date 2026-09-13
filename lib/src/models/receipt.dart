import '../formatting/money_formatter.dart';
import '../vat_calculator.dart';
import '../money.dart';
import 'payment.dart';
import 'receipt_line.dart';

/// Scontrino chiuso e immutabile.
///
/// Un documento fiscale non si modifica: si emette e, se serve, si storna.
/// Per questo la classe non espone alcun metodo di mutazione e le righe sono
/// restituite come lista non modificabile.
class Receipt {
  /// Costruito da `ReceiptBuilder.close`, che è l'unico posto in cui i
  /// totali di riga e il riepilogo IVA vengono dalla stessa ripartizione
  /// dello sconto. Costruirlo a mano con numeri incoerenti è possibile ed
  /// è responsabilità di chi lo fa.
  Receipt({
    required this.id,
    required this.issuedAt,
    required List<ReceiptLine> lines,
    required this.documentDiscount,
    required this.paid,
    required List<Money> netLineTotals,
    required List<VatBreakdown> vatSummary,
    List<Payment>? payments,
  })  : assert(netLineTotals.length == lines.length,
            'Un totale netto per ogni riga'),
        _payments = List<Payment>.unmodifiable(
          payments ??
              (paid.isZero ? <Payment>[] : <Payment>[Payment.cash(paid)]),
        ),
        _lines = List<ReceiptLine>.unmodifiable(lines),
        _netLineTotals = List<Money>.unmodifiable(netLineTotals),
        _vatSummary = List<VatBreakdown>.unmodifiable(vatSummary);

  /// Identificativo del documento. Lo assegna chi emette: il pacchetto non
  /// gestisce la numerazione progressiva, che è materia di normativa e di
  /// registratore di cassa.
  final String id;

  /// Istante di emissione.
  final DateTime issuedAt;
  final List<ReceiptLine> _lines;
  final List<Payment> _payments;
  final List<Money> _netLineTotals;
  final List<VatBreakdown> _vatSummary;

  /// Sconto applicato all'intero documento.
  final Money documentDiscount;

  /// Importo incassato: la somma di [payments].
  final Money paid;

  /// Pagamenti con cui è stato saldato, in ordine di inserimento.
  ///
  /// Uno scontrino costruito senza indicarli, com'era prima della 0.6.0, ne
  /// ha uno solo in contanti pari a [paid]: è il significato che [change] ha
  /// sempre avuto, perché un resto si dà solo sul contante.
  List<Payment> get payments => _payments;

  /// Righe del documento, in ordine di inserimento. Non modificabile.
  List<ReceiptLine> get lines => _lines;

  /// Totale effettivo di ciascuna riga, nello stesso ordine di [lines]: il
  /// totale di riga dopo che lo sconto di documento è stato ripartito.
  ///
  /// È quanto il cliente ha davvero pagato per quella riga, e quindi la base di
  /// qualunque rimborso. Rimborsare `lines[i].total` restituirebbe anche la
  /// quota di sconto di documento che su quella riga non è mai stata incassata.
  ///
  /// La somma è esattamente [total]: è l'invariante garantita dal
  /// `DiscountAllocator`, e senza di quella un reso totale non tornerebbe a
  /// zero per un centesimo.
  List<Money> get netLineTotals => _netLineTotals;

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
  ///
  /// Esce sempre da pagamenti che danno resto: `ReceiptBuilder` rifiuta di
  /// chiudere uno scontrino in cui la parte versata con mezzi che non danno
  /// resto supera il totale. Per questo la formula resta `paid - total` anche
  /// con i pagamenti misti.
  Money get change => paid - total;

  /// Numero di articoli venduti.
  num get itemCount =>
      _lines.fold<num>(0, (num acc, ReceiptLine l) => acc + l.quantity);

  @override
  String toString() => 'Receipt($id, ${_lines.length} righe, '
      'totale ${const PlainMoneyFormatter().format(total)})';
}
