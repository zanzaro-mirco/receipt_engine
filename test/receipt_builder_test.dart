import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

ReceiptBuilder builder() =>
    ReceiptBuilder(id: 'T-0001', issuedAt: DateTime(2026, 7, 27, 10, 30));

void main() {
  group('ReceiptBuilder - flusso base', () {
    test('somma le righe e calcola il resto', () {
      final Receipt r = builder()
          .addLine(
            description: 'Caffè',
            unitPrice: Money.fromEuro(1.20),
            vatRate: VatRate.reduced,
            quantity: 2,
          )
          .addLine(
            description: 'Brioche',
            unitPrice: Money.fromEuro(1.50),
            vatRate: VatRate.reduced,
          )
          .close(paid: Money.fromEuro(5));

      expect(r.total, Money.fromEuro(3.90));
      expect(r.change, Money.fromEuro(1.10));
      expect(r.itemCount, 3);
      expect(r.lines.length, 2);
    });

    test('le righe dello scontrino chiuso non sono modificabili', () {
      final Receipt r = builder()
          .addLine(
            description: 'Acqua',
            unitPrice: Money.fromEuro(1),
            vatRate: VatRate.reduced,
          )
          .close(paid: Money.fromEuro(1));

      expect(
        () => r.lines.add(
          ReceiptLine(
            description: 'x',
            unitPrice: const Money(1),
            vatRate: VatRate.standard,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('ReceiptBuilder - sconti', () {
    test('sconto percentuale di riga', () {
      final Receipt r = builder()
          .addLine(
            description: 'Maglietta',
            unitPrice: Money.fromEuro(20),
            vatRate: VatRate.standard,
            discount: Discount.percent(10),
          )
          .close(paid: Money.fromEuro(18));

      expect(r.total, Money.fromEuro(18));
    });

    test('sconto a importo fisso non può superare la base', () {
      final Receipt r = builder()
          .addLine(
            description: 'Penna',
            unitPrice: Money.fromEuro(2),
            vatRate: VatRate.standard,
            discount: Discount.amount(Money.fromEuro(5)),
          )
          .close(paid: const Money.zero());

      expect(r.total, const Money.zero());
    });

    test('sconto di documento riduce il totale', () {
      final Receipt r = builder()
          .addLine(
            description: 'Articolo',
            unitPrice: Money.fromEuro(100),
            vatRate: VatRate.standard,
          )
          .applyDocumentDiscount(Discount.percent(20))
          .close(paid: Money.fromEuro(80));

      expect(r.documentDiscount, Money.fromEuro(20));
      expect(r.total, Money.fromEuro(80));
    });

    test('sconto percentuale fuori range viene rifiutato', () {
      expect(() => Discount.percent(120), throwsArgumentError);
      expect(() => Discount.percent(-1), throwsArgumentError);
    });
  });

  group('ReceiptBuilder - riepilogo IVA', () {
    test('raggruppa per aliquota e ordina in modo crescente', () {
      final Receipt r = builder()
          .addLine(
            description: 'Pane',
            unitPrice: Money.fromEuro(2),
            vatRate: VatRate.superReduced,
          )
          .addLine(
            description: 'Vino',
            unitPrice: Money.fromEuro(12.20),
            vatRate: VatRate.standard,
          )
          .addLine(
            description: 'Pasta',
            unitPrice: Money.fromEuro(1),
            vatRate: VatRate.superReduced,
          )
          .close(paid: Money.fromEuro(20));

      expect(r.vatSummary.length, 2);
      expect(r.vatSummary.first.rate, VatRate.superReduced);
      expect(r.vatSummary.last.rate, VatRate.standard);
      expect(r.vatSummary.first.gross, Money.fromEuro(3));
      expect(r.vatSummary.last.tax, Money.fromEuro(2.20));
    });

    test('la somma dei lordi per aliquota è uguale al totale, anche con sconto',
        () {
      final Receipt r = builder()
          .addLine(
            description: 'A',
            unitPrice: Money.fromEuro(33.33),
            vatRate: VatRate.standard,
          )
          .addLine(
            description: 'B',
            unitPrice: Money.fromEuro(11.11),
            vatRate: VatRate.reduced,
          )
          .addLine(
            description: 'C',
            unitPrice: Money.fromEuro(7.77),
            vatRate: VatRate.superReduced,
          )
          .applyDocumentDiscount(Discount.percent(13))
          .close(paid: Money.fromEuro(100));

      final Money grossSum =
          Money.sum(r.vatSummary.map((VatBreakdown v) => v.gross));
      expect(grossSum, r.total);
      expect(r.totalTaxable + r.totalTax, r.total);
    });
  });

  group('ReceiptBuilder - invarianti', () {
    test('non si può chiudere uno scontrino vuoto', () {
      expect(() => builder().close(paid: const Money.zero()), throwsStateError);
    });

    test('non si può incassare meno del dovuto', () {
      final ReceiptBuilder b = builder().addLine(
        description: 'Articolo',
        unitPrice: Money.fromEuro(10),
        vatRate: VatRate.standard,
      );
      expect(
        () => b.close(paid: Money.fromEuro(5)),
        throwsA(isA<InsufficientPaymentError>()),
      );
    });

    test('non si può operare su uno scontrino già chiuso', () {
      final ReceiptBuilder b = builder().addLine(
        description: 'Articolo',
        unitPrice: Money.fromEuro(10),
        vatRate: VatRate.standard,
      );
      b.close(paid: Money.fromEuro(10));

      expect(
        () => b.addLine(
          description: 'Altro',
          unitPrice: Money.fromEuro(1),
          vatRate: VatRate.standard,
        ),
        throwsA(isA<ReceiptClosedError>()),
      );
      expect(() => b.close(paid: Money.fromEuro(10)),
          throwsA(isA<ReceiptClosedError>()));
    });

    test('quantità non positiva viene rifiutata', () {
      expect(
        () => builder().addLine(
          description: 'X',
          unitPrice: Money.fromEuro(1),
          vatRate: VatRate.standard,
          quantity: 0,
        ),
        throwsArgumentError,
      );
    });

    test('removeLastLine restituisce false su scontrino vuoto', () {
      expect(builder().removeLastLine(), isFalse);
    });
  });

  group('Pagamenti misti', () {
    // Un totale di 22 € su una riga sola: i numeri tondi servono a leggere a
    // colpo d'occhio da dove esce il resto.
    ReceiptBuilder twentyTwo() => ReceiptBuilder(id: 'P')
      ..addLine(
        description: 'Merce',
        unitPrice: const Money(2200),
        vatRate: VatRate.standard,
      );

    test('15 con la carta e 10 in contanti su 22: 3 di resto, dal contante',
        () {
      final Receipt r = twentyTwo().closeWithPayments(<Payment>[
        Payment.electronic(const Money(1500)),
        Payment.cash(const Money(1000)),
      ]);

      expect(r.paid, const Money(2500));
      expect(r.change, const Money(300));
      expect(r.payments.map((Payment p) => p.method),
          <PaymentMethod>[PaymentMethod.electronic, PaymentMethod.cash]);
    });

    test('25 con la sola carta su 22 non fa 3 di resto: è un errore', () {
      // Il caso che dà senso alla voce. La carta ha addebitato 25 e nel
      // cassetto non è entrato niente: quei 3 euro non ci sono.
      expect(
        () => twentyTwo().closeWithPayments(
            <Payment>[Payment.electronic(const Money(2500))]),
        throwsA(isA<ChangeNotAvailableError>()
            .having(
                (ChangeNotAvailableError e) => e.due, 'due', const Money(2200))
            .having((ChangeNotAvailableError e) => e.withoutChange,
                'withoutChange', const Money(2500))),
      );
    });

    test('non basta che ci siano contanti: conta quanto va oltre il totale',
        () {
      // 23 con la carta e 5 in contanti: la somma copre, i contanti ci sono,
      // ma il resto sarebbe 6 e dal cassetto ne possono uscire al massimo 5.
      expect(
        () => twentyTwo().closeWithPayments(<Payment>[
          Payment.electronic(const Money(2300)),
          Payment.cash(const Money(500)),
        ]),
        throwsA(isA<ChangeNotAvailableError>()),
      );
    });

    test('la carta esatta con i contanti in più restituisce tutti i contanti',
        () {
      final Receipt r = twentyTwo().closeWithPayments(<Payment>[
        Payment.electronic(const Money(2200)),
        Payment.cash(const Money(500)),
      ]);
      expect(r.change, const Money(500));
    });

    test('pagamenti che non coprono il totale restano un incasso insufficiente',
        () {
      expect(
        () => twentyTwo().closeWithPayments(<Payment>[
          Payment.electronic(const Money(1000)),
          Payment.cash(const Money(1000)),
        ]),
        throwsA(isA<InsufficientPaymentError>()),
      );
    });

    test('un mezzo definito da chi usa il pacchetto segue la stessa regola',
        () {
      const PaymentMethod mealVoucher =
          PaymentMethod('meal_voucher', label: 'Buono pasto');

      final Receipt ok = twentyTwo().closeWithPayments(<Payment>[
        Payment(mealVoucher, const Money(800)),
        Payment.cash(const Money(1500)),
      ]);
      expect(ok.change, const Money(100));

      expect(
        () => twentyTwo().closeWithPayments(<Payment>[
          Payment(mealVoucher, const Money(2400)),
        ]),
        throwsA(isA<ChangeNotAvailableError>()),
      );
    });

    test('close(paid:) resta un pagamento in contanti, come prima', () {
      final Receipt r = twentyTwo().close(paid: const Money(3000));
      expect(r.payments.single.method, PaymentMethod.cash);
      expect(r.payments.single.amount, const Money(3000));
      expect(r.change, const Money(800));
    });

    test('uno scontrino a totale zero si chiude senza pagamenti', () {
      final Receipt r = (twentyTwo()
            ..applyDocumentDiscount(Discount.percent(100)))
          .close(paid: const Money.zero());
      expect(r.payments, isEmpty);
      expect(r.change, const Money.zero());
    });

    test('un pagamento da zero o negativo non esiste', () {
      expect(() => Payment.cash(const Money.zero()), throwsArgumentError);
      expect(() => Payment.electronic(const Money(-100)), throwsArgumentError);
    });

    test('i pagamenti di uno scontrino chiuso non si modificano', () {
      final Receipt r = twentyTwo().close(paid: const Money(2200));
      expect(() => r.payments.add(Payment.cash(const Money(1))),
          throwsUnsupportedError);
    });

    test('uno scontrino chiuso non si richiude con altri pagamenti', () {
      final ReceiptBuilder b = twentyTwo();
      b.close(paid: const Money(2200));
      expect(
        () => b.closeWithPayments(<Payment>[Payment.cash(const Money(2200))]),
        throwsA(isA<ReceiptClosedError>()),
      );
    });
  });
}
