import '../models/discount.dart';
import '../models/payment.dart';
import '../models/receipt.dart';
import '../models/receipt_line.dart';
import '../models/return_receipt.dart';
import '../models/vat_rate.dart';
import '../money.dart';
import '../vat_calculator.dart';

/// Traduzione fra i documenti del dominio e mappe JSON.
///
/// Sta fuori dai modelli per la stessa ragione per cui ci sta
/// `MoneyFormatter`: uno scontrino non deve sapere come viaggia, esattamente
/// come non deve sapere come si scrive un numero in italiano. Chi non
/// serializza non paga niente per questa classe, e chi la usa può sostituirla
/// senza toccare il dominio.
///
/// Il risultato è una `Map`, non una stringa: `dart:convert` non compare da
/// nessuna parte nel pacchetto, così la mappa si può annidare dentro un
/// documento più grande, passarla a un encoder diverso o scriverla in un
/// database che parla già di mappe.
///
/// ```dart
/// const ReceiptJson codec = ReceiptJson();
/// final String wire = jsonEncode(codec.encodeReceipt(receipt));
/// final Receipt again =
///     codec.decodeReceipt(jsonDecode(wire) as Map<String, Object?>);
/// ```
///
/// **La decodifica non ricalcola niente.** I totali di riga al netto dello
/// sconto e il riepilogo IVA vengono riletti dal documento, non rifatti
/// passando per `ReceiptBuilder`: un documento fiscale emesso non si
/// ricalcola, si rilegge. Se lo si ricostruisse dal builder, una correzione
/// futura agli arrotondamenti cambierebbe retroattivamente scontrini già
/// emessi — e il documento riletto non sarebbe più quello consegnato al
/// cliente.
class ReceiptJson {
  /// Crea il codec. Non ha stato: ne basta un'istanza sola.
  const ReceiptJson();

  /// Versione dello schema scritta in ogni documento.
  ///
  /// È ciò che distingue un formato da uno scarico di campi: senza, la prima
  /// modifica incompatibile arriva addosso a chi ha già dei documenti salvati
  /// e non ha modo di sapere quale forma abbiano.
  ///
  /// - **1** (`0.5.0`): l'incasso è un importo solo, `paid`.
  /// - **2** (`0.6.0`): si aggiungono i `payments`, uno per mezzo di
  ///   pagamento. `paid` resta, ed è la loro somma.
  ///
  /// Un documento con schema 1 si legge ancora: i suoi pagamenti diventano
  /// un solo pagamento in contanti pari a `paid`, che è quello che `paid` ha
  /// sempre significato — un resto si dà solo sul contante.
  static const int schemaVersion = 2;

  /// Rappresentazione JSON di uno scontrino.
  Map<String, Object?> encodeReceipt(Receipt receipt) => <String, Object?>{
        'schemaVersion': schemaVersion,
        'type': 'receipt',
        'id': receipt.id,
        'issuedAt': receipt.issuedAt.toUtc().toIso8601String(),
        'documentDiscount': receipt.documentDiscount.cents,
        'paid': receipt.paid.cents,
        'payments': <Object?>[
          for (final Payment payment in receipt.payments)
            _encodePayment(payment),
        ],
        'lines': <Object?>[
          for (final ReceiptLine line in receipt.lines) _encodeLine(line),
        ],
        'netLineTotals': <Object?>[
          for (final Money amount in receipt.netLineTotals) amount.cents,
        ],
        'vatSummary': <Object?>[
          for (final VatBreakdown row in receipt.vatSummary)
            _encodeBreakdown(row),
        ],
      };

  /// Scontrino riletto da [json].
  ///
  /// Solleva una [FormatException] se il documento non ha la forma attesa, e
  /// un [ArgumentError] se ha la forma giusta ma contiene valori che il
  /// dominio rifiuta — una quantità negativa, per esempio. La distinzione è
  /// voluta: il primo è un problema di trasporto, il secondo di contenuto.
  Receipt decodeReceipt(Map<String, Object?> json) {
    final int version = _checkEnvelope(json, 'receipt');
    final Money paid = _money(json, 'paid');
    final List<Payment>? payments = version < 2
        ? null
        : <Payment>[
            for (final Object? payment in _list(json, 'payments'))
              _decodePayment(_asMap(payment, 'payments')),
          ];
    if (payments != null &&
        Money.sum(payments.map((Payment p) => p.amount)) != paid) {
      // Due dati salvati che si contraddicono: non si sceglie quale dei due
      // credere, perché qualunque scelta inventerebbe un incasso.
      throw FormatException(
        'I pagamenti non sommano all\'incasso dichiarato ${paid.cents}',
      );
    }
    return Receipt(
      id: _string(json, 'id'),
      issuedAt: _dateTime(json, 'issuedAt'),
      lines: <ReceiptLine>[
        for (final Object? line in _list(json, 'lines'))
          _decodeLine(_asMap(line, 'lines')),
      ],
      documentDiscount: _money(json, 'documentDiscount'),
      paid: paid,
      payments: payments,
      netLineTotals: <Money>[
        for (final Object? amount in _list(json, 'netLineTotals'))
          Money(_integer(amount, 'netLineTotals')),
      ],
      vatSummary: <VatBreakdown>[
        for (final Object? row in _list(json, 'vatSummary'))
          _decodeBreakdown(_asMap(row, 'vatSummary')),
      ],
    );
  }

  /// Rappresentazione JSON di un documento di reso.
  Map<String, Object?> encodeReturnReceipt(ReturnReceipt receipt) =>
      <String, Object?>{
        'schemaVersion': schemaVersion,
        'type': 'return',
        'id': receipt.id,
        'originalReceiptId': receipt.originalReceiptId,
        'issuedAt': receipt.issuedAt.toUtc().toIso8601String(),
        'lines': <Object?>[
          for (final ReturnLine line in receipt.lines) _encodeReturnLine(line),
        ],
        'vatSummary': <Object?>[
          for (final VatBreakdown row in receipt.vatSummary)
            _encodeBreakdown(row),
        ],
      };

  /// Documento di reso riletto da [json].
  ReturnReceipt decodeReturnReceipt(Map<String, Object?> json) {
    // Il reso non ha pagamenti — non porta un metodo di rimborso — e la sua
    // forma è la stessa negli schemi 1 e 2.
    _checkEnvelope(json, 'return');
    return ReturnReceipt(
      id: _string(json, 'id'),
      originalReceiptId: _string(json, 'originalReceiptId'),
      issuedAt: _dateTime(json, 'issuedAt'),
      lines: <ReturnLine>[
        for (final Object? line in _list(json, 'lines'))
          _decodeReturnLine(_asMap(line, 'lines')),
      ],
      vatSummary: <VatBreakdown>[
        for (final Object? row in _list(json, 'vatSummary'))
          _decodeBreakdown(_asMap(row, 'vatSummary')),
      ],
    );
  }

  // --------------------------------------------------------------- scrittura

  Map<String, Object?> _encodeLine(ReceiptLine line) => <String, Object?>{
        'description': line.description,
        'unitPrice': line.unitPrice.cents,
        'vatRate': _encodeRate(line.vatRate),
        'quantity': line.quantity,
        if (line.discount != null) 'discount': _encodeDiscount(line.discount!),
      };

  Map<String, Object?> _encodeReturnLine(ReturnLine line) => <String, Object?>{
        'lineIndex': line.lineIndex,
        'description': line.description,
        'vatRate': _encodeRate(line.vatRate),
        'quantity': line.quantity,
        'amount': line.amount.cents,
      };

  Map<String, Object?> _encodePayment(Payment payment) => <String, Object?>{
        'method': <String, Object?>{
          'code': payment.method.code,
          'label': payment.method.label,
          'givesChange': payment.method.givesChange,
        },
        'amount': payment.amount.cents,
      };

  Map<String, Object?> _encodeRate(VatRate rate) => <String, Object?>{
        'percentage': rate.percentage,
        'label': rate.label,
      };

  Map<String, Object?> _encodeBreakdown(VatBreakdown row) => <String, Object?>{
        'rate': _encodeRate(row.rate),
        'gross': row.gross.cents,
        'taxable': row.taxable.cents,
        'tax': row.tax.cents,
      };

  /// Lo sconto porta con sé il proprio tipo.
  ///
  /// `Discount` è una gerarchia polimorfa: senza un discriminante esplicito,
  /// uno sconto del 10% e uno di dieci centesimi sarebbero indistinguibili
  /// sul filo.
  ///
  /// Il caso finale non è difensivo per abitudine. `Discount` è
  /// `abstract base class` e non `sealed`, quindi un sottotipo definito
  /// altrove è possibile, e il compilatore non può accorgersi che questo
  /// `switch` non lo copre. Meglio un errore esplicito che uno sconto che
  /// sparisce silenziosamente dal documento.
  Map<String, Object?> _encodeDiscount(Discount discount) => switch (discount) {
        PercentageDiscount(:final num value) => <String, Object?>{
            'kind': 'percent',
            'value': value,
            'description': discount.description,
          },
        AmountDiscount(:final Money value) => <String, Object?>{
            'kind': 'amount',
            'value': value.cents,
            'description': discount.description,
          },
        _ => throw UnsupportedError(
            'Sconto di tipo ${discount.runtimeType} non serializzabile: '
            'aggiungi il suo caso a ReceiptJson',
          ),
      };

  // ----------------------------------------------------------------- lettura

  ReceiptLine _decodeLine(Map<String, Object?> json) => ReceiptLine(
        description: _string(json, 'description'),
        unitPrice: _money(json, 'unitPrice'),
        vatRate: _decodeRate(_asMap(json['vatRate'], 'vatRate')),
        quantity: _number(json, 'quantity'),
        discount: json['discount'] == null
            ? null
            : _decodeDiscount(_asMap(json['discount'], 'discount')),
      );

  ReturnLine _decodeReturnLine(Map<String, Object?> json) => ReturnLine(
        lineIndex: _integer(json['lineIndex'], 'lineIndex'),
        description: _string(json, 'description'),
        vatRate: _decodeRate(_asMap(json['vatRate'], 'vatRate')),
        quantity: _number(json, 'quantity'),
        amount: _money(json, 'amount'),
      );

  /// Il mezzo si ricostruisce dal documento, `givesChange` compreso, e non
  /// si confronta con i mezzi predefiniti: un buono pasto registrato da chi
  /// usa il pacchetto deve tornare indietro com'era, anche se questa versione
  /// non lo conosce.
  Payment _decodePayment(Map<String, Object?> json) {
    final Map<String, Object?> method = _asMap(json['method'], 'method');
    final Object? givesChange = method['givesChange'];
    if (givesChange is! bool) {
      throw FormatException(
          'Il campo "givesChange" non è un booleano: $givesChange');
    }
    return Payment(
      PaymentMethod(
        _string(method, 'code'),
        label: _string(method, 'label'),
        givesChange: givesChange,
      ),
      _money(json, 'amount'),
    );
  }

  VatRate _decodeRate(Map<String, Object?> json) => VatRate(
        _number(json, 'percentage'),
        label: _string(json, 'label'),
      );

  VatBreakdown _decodeBreakdown(Map<String, Object?> json) => VatBreakdown(
        rate: _decodeRate(_asMap(json['rate'], 'rate')),
        gross: _money(json, 'gross'),
        taxable: _money(json, 'taxable'),
        tax: _money(json, 'tax'),
      );

  Discount _decodeDiscount(Map<String, Object?> json) {
    final String kind = _string(json, 'kind');
    final String description = _string(json, 'description');
    return switch (kind) {
      'percent' =>
        Discount.percent(_number(json, 'value'), description: description),
      'amount' =>
        Discount.amount(_money(json, 'value'), description: description),
      _ => throw FormatException('Tipo di sconto sconosciuto: "$kind"'),
    };
  }

  // ---------------------------------------------------------------- aiutanti

  int _checkEnvelope(Map<String, Object?> json, String expectedType) {
    final int version = _integer(json['schemaVersion'], 'schemaVersion');
    if (version > schemaVersion) {
      throw FormatException(
        'Documento scritto con lo schema $version, e questa versione del '
        'pacchetto arriva allo schema $schemaVersion',
      );
    }
    final String type = _string(json, 'type');
    if (type != expectedType) {
      throw FormatException(
        'Atteso un documento di tipo "$expectedType", trovato "$type"',
      );
    }
    return version;
  }

  String _string(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is String) return value;
    throw FormatException('Il campo "$field" non è una stringa: $value');
  }

  num _number(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is num) return value;
    throw FormatException('Il campo "$field" non è un numero: $value');
  }

  /// Importo intero in centesimi, come nel dominio.
  Money _money(Map<String, Object?> json, String field) =>
      Money(_integer(json[field], field));

  /// Intero, accettando anche un `double` che sia davvero intero.
  ///
  /// `jsonDecode` restituisce un `double` per `204.0` e un `int` per `204`, e
  /// i due numeri sono lo stesso importo. Arrotondare in silenzio un `204.7`
  /// invece farebbe entrare nel dominio un importo che nessuno ha emesso, e
  /// per un documento fiscale è meglio un errore che una cifra inventata.
  int _integer(Object? value, String field) {
    if (value is int) return value;
    if (value is double && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw FormatException('Il campo "$field" non è un intero: $value');
  }

  DateTime _dateTime(Map<String, Object?> json, String field) {
    final String raw = _string(json, field);
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Il campo "$field" non è una data ISO 8601: $raw');
    }
    return parsed;
  }

  List<Object?> _list(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is List) return value;
    throw FormatException('Il campo "$field" non è una lista: $value');
  }

  Map<String, Object?> _asMap(Object? value, String field) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    throw FormatException('Il campo "$field" non è un oggetto: $value');
  }
}
