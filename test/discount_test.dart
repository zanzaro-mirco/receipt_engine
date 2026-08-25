import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

/// Sconto aggiunto solo dal test: dimostra che la gerarchia è aperta
/// all'estensione senza modificare una riga del pacchetto.
final class ThreeForTwoDiscount extends Discount {
  ThreeForTwoDiscount(this.unitPrice, this.quantity);

  final Money unitPrice;
  final int quantity;

  @override
  Money appliedTo(Money base) {
    final Money free = unitPrice.multipliedBy(quantity ~/ 3);
    return free > base ? base : free;
  }
}

void main() {
  group('Discount', () {
    test('percentuale', () {
      expect(
          Discount.percent(10).appliedTo(const Money(1000)), const Money(100));
    });

    test('importo fisso', () {
      expect(Discount.amount(const Money(250)).appliedTo(const Money(1000)),
          const Money(250));
    });

    test('rifiuta valori non validi', () {
      expect(() => Discount.percent(101), throwsArgumentError);
      expect(() => Discount.percent(-1), throwsArgumentError);
      expect(() => Discount.amount(const Money(-1)), throwsArgumentError);
    });
  });

  group('contratto rispettato da ogni sottotipo (Liskov)', () {
    final List<Discount> tutti = <Discount>[
      Discount.percent(30),
      Discount.amount(const Money(10000)),
      ThreeForTwoDiscount(const Money(500), 7),
    ];

    test('lo sconto non è mai negativo e non supera mai la base', () {
      for (final Discount d in tutti) {
        for (int base = 0; base <= 3000; base += 137) {
          final Money result = d.appliedTo(Money(base));
          expect(result.isNegative, isFalse, reason: '$d su $base');
          expect(result <= Money(base), isTrue, reason: '$d su $base');
        }
      }
    });
  });

  test('un nuovo tipo di sconto non richiede modifiche al pacchetto', () {
    // 7 articoli da 5,00 -> 2 gratis
    final Discount d = ThreeForTwoDiscount(const Money(500), 7);
    expect(d.appliedTo(const Money(3500)), const Money(1000));
  });
}
