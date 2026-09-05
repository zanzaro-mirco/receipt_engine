import 'formatting/money_formatter.dart';
import 'models/discount.dart';
import 'models/receipt.dart';
import 'models/receipt_line.dart';
import 'models/vat_rate.dart';
import 'money.dart';
import 'vat_summary_calculator.dart';

/// Errore sollevato quando si opera su un documento già chiuso.
///
/// Vale per lo scontrino e per il documento di reso: la macchina a stati è la
/// stessa — aperto o chiuso — e non merita due errori distinti.
class ReceiptClosedError extends StateError {
  /// Crea l'errore.
  ReceiptClosedError() : super('Il documento è già stato chiuso');
}

/// Errore sollevato quando l'incasso non copre il totale.
class InsufficientPaymentError extends StateError {
  /// Crea l'errore a partire dal dovuto e dall'incassato.
  InsufficientPaymentError(this.due, this.paid)
      : super('Incasso ${const PlainMoneyFormatter().format(paid)} inferiore '
            'al dovuto ${const PlainMoneyFormatter().format(due)}');

  /// Totale del documento.
  final Money due;

  /// Importo offerto, inferiore al dovuto.
  final Money paid;
}

/// Costruisce uno scontrino passo dopo passo e lo chiude in un [Receipt]
/// immutabile.
///
/// Unica responsabilità: il ciclo di vita del documento. Il calcolo dell'IVA e
/// la ripartizione dello sconto sono delegati a [VatSummaryCalculator], che
/// arriva dall'esterno e può essere sostituito — è la stessa ragione per cui
/// il builder non sa nulla di come si formatta un importo.
class ReceiptBuilder {
  /// Apre un nuovo scontrino.
  ///
  /// Senza [issuedAt] usa l'istante corrente. [summaryCalculator] si
  /// sostituisce per cambiare il criterio di ripartizione dello sconto o
  /// il regime di calcolo dell'imposta.
  ReceiptBuilder({
    required this.id,
    DateTime? issuedAt,
    VatSummaryCalculator summaryCalculator = const VatSummaryCalculator(),
  })  : issuedAt = issuedAt ?? DateTime.now(),
        _summaryCalculator = summaryCalculator;

  /// Identificativo che finirà sul documento.
  final String id;

  /// Istante di emissione, fissato all'apertura e non alla chiusura.
  final DateTime issuedAt;

  final VatSummaryCalculator _summaryCalculator;

  final List<ReceiptLine> _lines = <ReceiptLine>[];
  Discount? _documentDiscount;
  bool _closed = false;

  /// Vero dopo [close]: da quel momento ogni operazione è rifiutata.
  bool get isClosed => _closed;

  /// Vero finché non è stata aggiunta nessuna riga.
  bool get isEmpty => _lines.isEmpty;

  /// Numero di righe inserite finora.
  int get lineCount => _lines.length;

  /// Somma delle righe, al netto degli sconti di riga.
  Money get subtotal => Money.sum(_lines.map((ReceiptLine l) => l.total));

  /// Totale corrente, IVA inclusa e al netto di tutti gli sconti.
  Money get currentTotal => subtotal - _documentDiscountAmount;

  Money get _documentDiscountAmount =>
      _documentDiscount?.appliedTo(subtotal) ?? const Money.zero();

  /// Aggiunge una riga.
  ReceiptBuilder addLine({
    required String description,
    required Money unitPrice,
    required VatRate vatRate,
    num quantity = 1,
    Discount? discount,
  }) {
    _ensureOpen();
    _lines.add(
      ReceiptLine(
        description: description,
        unitPrice: unitPrice,
        vatRate: vatRate,
        quantity: quantity,
        discount: discount,
      ),
    );
    return this;
  }

  /// Rimuove l'ultima riga inserita. Restituisce `false` se non c'è nulla da
  /// rimuovere.
  bool removeLastLine() {
    _ensureOpen();
    if (_lines.isEmpty) return false;
    _lines.removeLast();
    return true;
  }

  /// Applica uno sconto all'intero documento, sostituendo l'eventuale
  /// precedente.
  ReceiptBuilder applyDocumentDiscount(Discount discount) {
    _ensureOpen();
    _documentDiscount = discount;
    return this;
  }

  /// Chiude lo scontrino con l'importo incassato.
  Receipt close({required Money paid}) {
    _ensureOpen();
    if (_lines.isEmpty) {
      throw StateError('Non si può chiudere uno scontrino senza righe');
    }

    final Money discount = _documentDiscountAmount;
    final Money total = subtotal - discount;
    if (paid < total) {
      throw InsufficientPaymentError(total, paid);
    }

    // Un solo calcolo: i totali di riga al netto dello sconto e il riepilogo
    // per aliquota che ne discende escono dalla stessa ripartizione.
    final DocumentTotals totals = _summaryCalculator.compute(
      lines: _lines,
      documentDiscount: discount,
    );

    _closed = true;
    return Receipt(
      id: id,
      issuedAt: issuedAt,
      lines: _lines,
      documentDiscount: discount,
      paid: paid,
      netLineTotals: totals.netLineTotals,
      vatSummary: totals.vatSummary,
    );
  }

  void _ensureOpen() {
    if (_closed) throw ReceiptClosedError();
  }
}
