import '../formatting/money_formatter.dart';
import '../money.dart';
import '../vat_calculator.dart';
import 'vat_rate.dart';

/// Riga di un documento di reso: una riga dello scontrino originale, resa in
/// tutto o in parte.
///
/// [lineIndex] è la posizione nella lista delle righe dell'originale, non un
/// identificativo di prodotto: due righe con la stessa descrizione sono due
/// righe distinte dello scontrino e si rendono separatamente.
class ReturnLine {
  const ReturnLine({
    required this.lineIndex,
    required this.description,
    required this.vatRate,
    required this.quantity,
    required this.amount,
  });

  /// Posizione della riga resa dentro `Receipt.lines`.
  final int lineIndex;

  final String description;
  final VatRate vatRate;

  /// Unità rese. Positiva.
  final num quantity;

  /// Importo restituito. **Negativo**, come tutti gli importi di un reso.
  final Money amount;

  @override
  String toString() => 'Reso riga $lineIndex: $description x$quantity '
      '${const PlainMoneyFormatter().format(amount)}';
}

/// Documento di reso collegato a uno scontrino.
///
/// Uno scontrino chiuso non si modifica: si storna. Questo documento è il
/// modo di farlo — referenzia l'originale, ne riprende un sottoinsieme delle
/// righe e ha un proprio riepilogo IVA.
///
/// **Convenzione sui segni: qui gli importi sono negativi.** Non è una
/// stranezza, è quello che rende sommabili documenti di natura diversa: il
/// totale di giornata è la somma di tutti i documenti emessi, scontrini e resi,
/// senza casi particolari e senza che qualcuno debba ricordarsi di cambiare
/// segno. Chi deve mostrare all'operatore quanto tirare fuori dal cassetto usa
/// [refund], che è positivo.
class ReturnReceipt {
  ReturnReceipt({
    required this.id,
    required this.originalReceiptId,
    required this.issuedAt,
    required List<ReturnLine> lines,
    required List<VatBreakdown> vatSummary,
  })  : _lines = List<ReturnLine>.unmodifiable(lines),
        _vatSummary = List<VatBreakdown>.unmodifiable(vatSummary);

  final String id;

  /// Identificativo dello scontrino stornato.
  final String originalReceiptId;

  final DateTime issuedAt;
  final List<ReturnLine> _lines;
  final List<VatBreakdown> _vatSummary;

  List<ReturnLine> get lines => _lines;

  /// Riepilogo IVA a segno invertito, ordinato per aliquota crescente.
  List<VatBreakdown> get vatSummary => _vatSummary;

  /// Totale del documento, IVA inclusa. Negativo.
  Money get total => Money.sum(_lines.map((ReturnLine l) => l.amount));

  /// Imposta stornata. Negativa.
  Money get totalTax => Money.sum(_vatSummary.map((VatBreakdown v) => v.tax));

  /// Imponibile stornato. Negativo.
  Money get totalTaxable =>
      Money.sum(_vatSummary.map((VatBreakdown v) => v.taxable));

  /// Importo da restituire al cliente, positivo: è [total] cambiato di segno.
  Money get refund => -total;

  /// Numero di articoli resi. Positivo.
  num get itemCount =>
      _lines.fold<num>(0, (num acc, ReturnLine l) => acc + l.quantity);

  /// Numero di righe dell'originale toccate da questo reso.
  ///
  /// Non dice se lo scontrino è ormai reso del tutto: quello dipende anche dai
  /// resi emessi prima, e lo sa `ReturnBuilder` attraverso le quantità residue.
  int get lineCount => _lines.length;

  @override
  String toString() => 'ReturnReceipt($id su $originalReceiptId, '
      '${_lines.length} righe, '
      'totale ${const PlainMoneyFormatter().format(total)})';
}
