import 'models/receipt.dart';
import 'models/receipt_line.dart';
import 'models/return_receipt.dart';
import 'money.dart';
import 'receipt_builder.dart';
import 'vat_summary_calculator.dart';

/// Errore sollevato quando si tenta di rendere più di quanto venduto.
///
/// Il conto tiene dentro anche i resi già emessi sullo stesso scontrino: senza
/// di quelli, tre resi parziali da una unità ciascuno permetterebbero di
/// restituire tre volte un articolo venduto una volta sola.
class ExcessiveReturnError extends StateError {
  /// Crea l'errore con la riga in questione, il richiesto e il residuo.
  ExcessiveReturnError({
    required this.lineIndex,
    required this.requested,
    required this.remaining,
  }) : super('Riga $lineIndex: richieste $requested unità di reso, '
            'ma ne restano $remaining');

  /// Posizione della riga nell'originale.
  final int lineIndex;

  /// Quantità che si è tentato di rendere.
  final num requested;

  /// Quantità che era ancora rendibile.
  final num remaining;
}

/// Costruisce un documento di reso a partire da uno scontrino chiuso.
///
/// Parallelo di [ReceiptBuilder], con la stessa macchina a stati minima —
/// aperto o chiuso — e una differenza sostanziale: qui non si sceglie cosa
/// mettere nel documento, si sceglie *cosa restituire di un documento che
/// esiste già*. Le descrizioni, le aliquote e gli importi non vengono passati
/// da fuori, vengono dall'originale. È il motivo per cui un reso non può
/// contraddire lo scontrino che storna.
class ReturnBuilder {
  /// Apre un reso su [original].
  ///
  /// [previousReturns] sono i resi già emessi sullo stesso scontrino, che
  /// il chiamante deve fornire: senza, il controllo sulle quantità guarda
  /// solo questo documento e si può rendere più volte la stessa merce. Il
  /// costruttore rifiuta i resi che appartengono a un altro scontrino.
  ReturnBuilder({
    required this.id,
    required this.original,
    DateTime? issuedAt,
    List<ReturnReceipt> previousReturns = const <ReturnReceipt>[],
    VatSummaryCalculator summaryCalculator = const VatSummaryCalculator(),
  })  : issuedAt = issuedAt ?? DateTime.now(),
        _summaryCalculator = summaryCalculator,
        _alreadyReturned = _sumPrevious(original, previousReturns);

  /// Identificativo del documento di reso.
  final String id;

  /// Lo scontrino stornato.
  final Receipt original;

  /// Istante di emissione del reso.
  final DateTime issuedAt;

  final VatSummaryCalculator _summaryCalculator;

  /// Quantità già resa per ciascuna riga dai documenti precedenti.
  final List<num> _alreadyReturned;

  /// Quantità che *questo* documento sta rendendo, per indice di riga.
  final Map<int, num> _requested = <int, num>{};

  bool _closed = false;

  /// Vero dopo [close]: da quel momento ogni operazione è rifiutata.
  bool get isClosed => _closed;

  /// Vero finché non è stata aggiunta nessuna riga al reso.
  bool get isEmpty => _requested.isEmpty;

  /// Quantità ancora rendibile per la riga [lineIndex]: quanto è stato venduto,
  /// meno i resi già emessi, meno quello che sta per entrare in questo reso.
  num remainingQuantity(int lineIndex) =>
      original.lines[lineIndex].quantity -
      _alreadyReturned[lineIndex] -
      (_requested[lineIndex] ?? 0);

  /// Vero quando non resta più niente da rendere su nessuna riga.
  bool get isFullyReturned {
    for (int i = 0; i < original.lines.length; i++) {
      if (remainingQuantity(i) > 0) return false;
    }
    return true;
  }

  /// Aggiunge al reso una riga dell'originale.
  ///
  /// Senza [quantity] rende tutto quello che resta rendibile su quella riga.
  /// Chiamarla due volte sullo stesso indice somma le quantità: chi sta alla
  /// cassa passa due volte lo stesso articolo, non deve accorgersene.
  ReturnBuilder addLine(int lineIndex, {num? quantity}) {
    _ensureOpen();
    RangeError.checkValidIndex(lineIndex, original.lines, 'lineIndex');

    final num remaining = remainingQuantity(lineIndex);
    final num qty = quantity ?? remaining;
    if (qty <= 0) {
      throw ArgumentError.value(qty, 'quantity', 'Deve essere positiva');
    }
    if (qty > remaining) {
      throw ExcessiveReturnError(
        lineIndex: lineIndex,
        requested: qty,
        remaining: remaining,
      );
    }

    _requested.update(lineIndex, (num q) => q + qty, ifAbsent: () => qty);
    return this;
  }

  /// Rende tutto quello che resta rendibile: il reso totale.
  ReturnBuilder addEverything() {
    _ensureOpen();
    for (int i = 0; i < original.lines.length; i++) {
      if (remainingQuantity(i) > 0) addLine(i);
    }
    return this;
  }

  /// Chiude il reso.
  ReturnReceipt close() {
    _ensureOpen();
    if (_requested.isEmpty) {
      throw StateError('Non si può chiudere un reso senza righe');
    }

    // Ordinate come sull'originale: un documento di reso si legge accanto allo
    // scontrino che storna.
    final List<int> indexes = _requested.keys.toList()..sort();
    final List<ReturnLine> lines = <ReturnLine>[
      for (final int index in indexes) _lineFor(index),
    ];

    _closed = true;
    return ReturnReceipt(
      id: id,
      originalReceiptId: original.id,
      issuedAt: issuedAt,
      lines: lines,
      vatSummary: _summaryCalculator.summarize(<RatedAmount>[
        for (final ReturnLine l in lines) (rate: l.vatRate, amount: l.amount),
      ]),
    );
  }

  /// Costruisce la riga di reso per l'indice [index].
  ///
  /// La base non è il totale di riga ma `netLineTotals`, cioè il totale dopo la
  /// ripartizione dello sconto di documento: è quello che il cliente ha pagato
  /// davvero per quella riga. Rimborsare il totale di riga significherebbe
  /// restituire anche lo sconto.
  ///
  /// L'importo è la **differenza fra due arrotondamenti cumulativi**: quanto
  /// sarebbe stato rimborsato dopo questo reso, meno quanto lo era già stato.
  /// Non è un vezzo. Con la formula diretta — netto per quantità resa diviso
  /// venduta, arrotondato — ogni reso parziale sbaglia fino a mezzo centesimo
  /// per conto proprio, e tre resi da un pezzo non restituiscono quanto un reso
  /// da tre. Così invece la somma dei rimborsi di una riga resa per intero è
  /// esattamente il suo netto, comunque la si sia spezzata.
  ReturnLine _lineFor(int index) {
    final ReceiptLine sold = original.lines[index];
    final Money net = original.netLineTotals[index];
    final num requested = _requested[index]!;
    final num before = _alreadyReturned[index];

    final Money refund = _cumulative(net, before + requested, sold.quantity) -
        _cumulative(net, before, sold.quantity);

    return ReturnLine(
      lineIndex: index,
      description: sold.description,
      vatRate: sold.vatRate,
      quantity: requested,
      amount: -refund,
    );
  }

  static Money _cumulative(Money net, num returned, num sold) =>
      net.multipliedBy(returned / sold);

  static List<num> _sumPrevious(
    Receipt original,
    List<ReturnReceipt> previous,
  ) {
    final List<num> counts = List<num>.filled(original.lines.length, 0);
    for (final ReturnReceipt document in previous) {
      if (document.originalReceiptId != original.id) {
        throw ArgumentError.value(
          document.originalReceiptId,
          'previousReturns',
          'Reso di un altro scontrino: atteso ${original.id}',
        );
      }
      for (final ReturnLine line in document.lines) {
        RangeError.checkValidIndex(
            line.lineIndex, original.lines, 'previousReturns');
        counts[line.lineIndex] += line.quantity;
      }
    }
    return counts;
  }

  void _ensureOpen() {
    if (_closed) throw ReceiptClosedError();
  }
}
