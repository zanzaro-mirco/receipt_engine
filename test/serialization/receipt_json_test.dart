import 'dart:convert';

import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

/// Scontrino di riferimento: due aliquote, uno sconto di riga percentuale e
/// uno sconto di documento a importo. Serve che ci sia dentro tutto quello che
/// il formato deve saper scrivere.
Receipt buildReceipt() => (ReceiptBuilder(
      id: 'T-0001',
      issuedAt: DateTime.utc(2026, 9, 13, 10, 30),
    )
          ..addLine(
            description: 'Caffè',
            unitPrice: const Money(110),
            vatRate: VatRate.reduced,
            quantity: 2,
          )
          ..addLine(
            description: 'Prosciutto',
            unitPrice: const Money(2040),
            vatRate: VatRate.standard,
            quantity: 0.3,
            discount: Discount.percent(10, description: 'Promo'),
          )
          ..applyDocumentDiscount(
              Discount.amount(const Money(50), description: 'Buono')))
        .close(paid: const Money(1000));

/// Uno sconto definito fuori dal pacchetto, come può fare chiunque lo usi.
final class BuyTwoPayOneDiscount extends Discount {
  BuyTwoPayOneDiscount() : super(description: 'Prendi 2 paghi 1');

  @override
  Money appliedTo(Money base) => base.multipliedBy(0.5);
}

void main() {
  const ReceiptJson codec = ReceiptJson();

  group('Il formato, scritto per esteso', () {
    // Questo test esiste per bloccare i **nomi dei campi**, che è ciò che il
    // round-trip da solo non può fare: un formato sbagliato in modo
    // simmetrico torna indietro identico e non se ne accorge nessuno. Qui
    // invece rinominare `netLineTotals` fa fallire la suite, come deve:
    // dall'altra parte del filo c'è qualcuno che ha già scritto il suo parser.
    test('uno scontrino si scrive esattamente così', () {
      expect(codec.encodeReceipt(buildReceipt()), <String, Object?>{
        'schemaVersion': 2,
        'type': 'receipt',
        'id': 'T-0001',
        'issuedAt': '2026-09-13T10:30:00.000Z',
        'documentDiscount': 50,
        'paid': 1000,
        'payments': <Object?>[
          <String, Object?>{
            'method': <String, Object?>{
              'code': 'cash',
              'label': 'Contanti',
              'givesChange': true,
            },
            'amount': 1000,
          },
        ],
        'lines': <Object?>[
          <String, Object?>{
            'description': 'Caffè',
            'unitPrice': 110,
            'vatRate': <String, Object?>{'percentage': 10, 'label': 'Ridotta'},
            'quantity': 2,
          },
          <String, Object?>{
            'description': 'Prosciutto',
            'unitPrice': 2040,
            'vatRate': <String, Object?>{
              'percentage': 22,
              'label': 'Ordinaria'
            },
            'quantity': 0.3,
            'discount': <String, Object?>{
              'kind': 'percent',
              'value': 10,
              'description': 'Promo',
            },
          },
        ],
        'netLineTotals': <Object?>[206, 515],
        'vatSummary': <Object?>[
          <String, Object?>{
            'rate': <String, Object?>{'percentage': 10, 'label': 'Ridotta'},
            'gross': 206,
            'taxable': 187,
            'tax': 19,
          },
          <String, Object?>{
            'rate': <String, Object?>{'percentage': 22, 'label': 'Ordinaria'},
            'gross': 515,
            'taxable': 422,
            'tax': 93,
          },
        ],
      });
    });

    test('un reso si scrive esattamente così', () {
      final ReturnReceipt reso = (ReturnBuilder(
        id: 'R-0001',
        original: buildReceipt(),
        issuedAt: DateTime.utc(2026, 9, 14, 9),
      )..addLine(0, quantity: 1))
          .close();

      expect(codec.encodeReturnReceipt(reso), <String, Object?>{
        'schemaVersion': 2,
        'type': 'return',
        'id': 'R-0001',
        'originalReceiptId': 'T-0001',
        'issuedAt': '2026-09-14T09:00:00.000Z',
        'lines': <Object?>[
          <String, Object?>{
            'lineIndex': 0,
            'description': 'Caffè',
            'vatRate': <String, Object?>{'percentage': 10, 'label': 'Ridotta'},
            'quantity': 1,
            'amount': -103,
          },
        ],
        'vatSummary': <Object?>[
          <String, Object?>{
            'rate': <String, Object?>{'percentage': 10, 'label': 'Ridotta'},
            'gross': -103,
            'taxable': -94,
            'tax': -9,
          },
        ],
      });
    });

    test('passa da una stringa JSON vera e torna indietro', () {
      // Gli altri test lavorano sulla mappa; questo verifica che il giro
      // completo attraverso `jsonEncode`/`jsonDecode` non perda niente — ed è
      // lì che i tipi numerici cambiano sotto i piedi.
      final Receipt original = buildReceipt();
      final String wire = jsonEncode(codec.encodeReceipt(original));
      final Receipt again =
          codec.decodeReceipt(jsonDecode(wire) as Map<String, Object?>);

      expect(again.total, original.total);
      expect(again.totalTax, original.totalTax);
      expect(again.id, original.id);
      expect(again.issuedAt, original.issuedAt);
      expect(again.lines.first.description, 'Caffè');
      expect(again.lines[1].discount, isA<PercentageDiscount>());
      expect(again.lines[1].discount!.description, 'Promo');
    });
  });

  group('Quello che la decodifica rifiuta', () {
    Map<String, Object?> receiptMap() => codec.encodeReceipt(buildReceipt());

    test('uno schema più recente di quello che questa versione conosce', () {
      final Map<String, Object?> json = receiptMap()
        ..['schemaVersion'] = ReceiptJson.schemaVersion + 1;
      expect(() => codec.decodeReceipt(json), throwsFormatException);
    });

    test('un documento scritto dalla 0.5.0 si legge ancora', () {
      // Non una mappa rimaneggiata ma il testo esatto che la 0.5.0 produceva
      // per lo scontrino di riferimento: è quello che chi l'ha usata ha già
      // salvato. Senza `payments`, e con lo schema 1.
      const String writtenBy050 = '''
{"schemaVersion":1,"type":"receipt","id":"T-0001",
 "issuedAt":"2026-09-13T10:30:00.000Z","documentDiscount":50,"paid":1000,
 "lines":[
  {"description":"Caffè","unitPrice":110,
   "vatRate":{"percentage":10,"label":"Ridotta"},"quantity":2},
  {"description":"Prosciutto","unitPrice":2040,
   "vatRate":{"percentage":22,"label":"Ordinaria"},"quantity":0.3,
   "discount":{"kind":"percent","value":10,"description":"Promo"}}],
 "netLineTotals":[206,515],
 "vatSummary":[
  {"rate":{"percentage":10,"label":"Ridotta"},"gross":206,"taxable":187,"tax":19},
  {"rate":{"percentage":22,"label":"Ordinaria"},"gross":515,"taxable":422,"tax":93}]}
''';
      final Receipt again =
          codec.decodeReceipt(jsonDecode(writtenBy050) as Map<String, Object?>);

      expect(again.total, buildReceipt().total);
      // `paid` ha sempre significato contanti: un resto si dà solo lì.
      expect(again.payments.single.method, PaymentMethod.cash);
      expect(again.payments.single.amount, const Money(1000));
      expect(again.change, const Money(279));
    });

    test('un reso letto come se fosse uno scontrino', () {
      final ReturnReceipt reso =
          (ReturnBuilder(id: 'R', original: buildReceipt())..addEverything())
              .close();
      expect(
        () => codec.decodeReceipt(codec.encodeReturnReceipt(reso)),
        throwsFormatException,
      );
    });

    test('un importo che non è un numero intero di centesimi', () {
      final Map<String, Object?> json = receiptMap()..['paid'] = 1000.7;
      expect(() => codec.decodeReceipt(json), throwsFormatException);
    });

    test('un importo intero scritto come double invece si accetta', () {
      // `jsonDecode` restituisce `1000.0` per un `1000.0` scritto sul filo, e
      // quello è lo stesso importo: rifiutarlo sarebbe pedanteria.
      final Map<String, Object?> json = receiptMap()..['paid'] = 1000.0;
      expect(codec.decodeReceipt(json).paid, const Money(1000));
    });

    test('un campo che manca', () {
      final Map<String, Object?> json = receiptMap()..remove('netLineTotals');
      expect(() => codec.decodeReceipt(json), throwsFormatException);
    });

    test('uno sconto di un tipo che non esiste', () {
      final Map<String, Object?> json = receiptMap();
      final List<Object?> lines = json['lines']! as List<Object?>;
      (lines[1]! as Map<String, Object?>)['discount'] = <String, Object?>{
        'kind': 'tre-per-due',
        'value': 1,
        'description': '',
      };
      expect(() => codec.decodeReceipt(json), throwsFormatException);
    });

    test('una quantità che il dominio non accetta', () {
      // Forma giusta, contenuto sbagliato: qui l'errore non è di trasporto e
      // arriva dal costruttore di `ReceiptLine`, che è il posto che conosce
      // la regola.
      final Map<String, Object?> json = receiptMap();
      final List<Object?> lines = json['lines']! as List<Object?>;
      (lines.first! as Map<String, Object?>)['quantity'] = -1;
      expect(() => codec.decodeReceipt(json), throwsArgumentError);
    });
  });

  group('Aliquote frazionarie sul filo', () {
    test('il 5,5% francese sopravvive al viaggio', () {
      const VatRate tauxReduit = VatRate(5.5, label: 'Taux réduit');
      final Receipt original = (ReceiptBuilder(
        id: 'F-1',
        issuedAt: DateTime.utc(2026, 9, 13),
      )..addLine(
              description: 'Pain',
              unitPrice: const Money(1055),
              vatRate: tauxReduit))
          .close(paid: const Money(1055));

      final String wire = jsonEncode(codec.encodeReceipt(original));
      final Receipt again =
          codec.decodeReceipt(jsonDecode(wire) as Map<String, Object?>);

      expect(again.vatSummary.single.rate, tauxReduit);
      expect(again.vatSummary.single.rate.label, 'Taux réduit');
      expect(again.totalTax, const Money(55));
    });

    test('un intero riletto come double resta la stessa aliquota', () {
      // È il caso che prima della 0.4.0 non si poteva nemmeno esprimere:
      // `jsonDecode` può restituire `22.0`, e il riepilogo non deve spaccarsi
      // in due righe per questo.
      final Map<String, Object?> json = codec.encodeReceipt(buildReceipt());
      final List<Object?> summary = json['vatSummary']! as List<Object?>;
      for (final Object? row in summary) {
        ((row! as Map<String, Object?>)['rate']!
            as Map<String, Object?>)['percentage'] = 10.0;
      }
      final List<Object?> lines = json['lines']! as List<Object?>;
      for (final Object? line in lines) {
        ((line! as Map<String, Object?>)['vatRate']!
            as Map<String, Object?>)['percentage'] = 10.0;
      }

      final Receipt again = codec.decodeReceipt(json);
      expect(again.lines.first.vatRate, VatRate.reduced);
      expect(again.vatSummary.first.rate, VatRate.reduced);
    });
  });

  group('Pagamenti sul filo', () {
    Receipt mixed() => (ReceiptBuilder(
          id: 'M-1',
          issuedAt: DateTime.utc(2026, 9, 13),
        )..addLine(
                description: 'Merce',
                unitPrice: const Money(2200),
                vatRate: VatRate.standard,
              ))
            .closeWithPayments(<Payment>[
          Payment.electronic(const Money(1500)),
          Payment(const PaymentMethod('meal_voucher', label: 'Buono pasto'),
              const Money(400)),
          Payment.cash(const Money(600)),
        ]);

    test('un pagamento misto torna indietro con i suoi mezzi e il suo resto',
        () {
      final Receipt original = mixed();
      final Receipt again = codec.decodeReceipt(
        jsonDecode(jsonEncode(codec.encodeReceipt(original)))
            as Map<String, Object?>,
      );

      expect(again.payments.map((Payment p) => p.method.code),
          <String>['electronic', 'meal_voucher', 'cash']);
      expect(again.payments.map((Payment p) => p.amount.cents),
          <int>[1500, 400, 600]);
      expect(again.change, const Money(300));
    });

    test('un mezzo che questa versione non conosce torna indietro com\'era',
        () {
      // Il buono pasto non è fra i mezzi predefiniti: se la decodifica lo
      // confrontasse con quelli, perderebbe `givesChange` o l'etichetta.
      final Receipt again = codec.decodeReceipt(codec.encodeReceipt(mixed()));
      final PaymentMethod voucher = again.payments[1].method;

      expect(voucher.label, 'Buono pasto');
      expect(voucher.givesChange, isFalse);
    });

    test('pagamenti che non sommano all\'incasso dichiarato', () {
      final Map<String, Object?> json = codec.encodeReceipt(mixed())
        ..['paid'] = 9999;
      expect(() => codec.decodeReceipt(json), throwsFormatException);
    });

    test('schema 2 senza pagamenti', () {
      final Map<String, Object?> json = codec.encodeReceipt(mixed())
        ..remove('payments');
      expect(() => codec.decodeReceipt(json), throwsFormatException);
    });
  });

  group('Sconti definiti da chi usa il pacchetto', () {
    test('funzionano nello scontrino, ma non si scrivono in JSON', () {
      // `Discount` è aperto per scelta: il builder accetta lo sconto e lo
      // calcola senza sapere cosa sia. Il formato invece non lo conosce, e
      // uno sconto che non si sa scrivere non si omette.
      final Receipt receipt = (ReceiptBuilder(
        id: 'X-1',
        issuedAt: DateTime.utc(2026, 9, 13),
      )..addLine(
              description: 'Merce',
              unitPrice: const Money(1000),
              vatRate: VatRate.standard,
              quantity: 2,
              discount: BuyTwoPayOneDiscount()))
          .close(paid: const Money(1000));

      expect(receipt.total, const Money(1000));
      expect(() => codec.encodeReceipt(receipt), throwsUnsupportedError);
    });
  });
}
