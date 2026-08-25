import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('costruisce da euro arrotondando al centesimo', () {
      expect(Money.fromEuro(1.5).cents, 150);
      expect(Money.fromEuro(0.1).cents, 10);
      expect(Money.fromEuro(1.004).cents, 100);
      expect(Money.fromEuro(0).cents, 0);
    });

    test('sul confine .5 il double non è affidabile: usare i centesimi', () {
      // 1.005 in virgola mobile binaria vale 1.00499999999999989, quindi
      // arrotonda per difetto. Non è un bug di Money: è il motivo per cui
      // `fromEuro` va usato solo ai bordi del sistema e mai nei calcoli.
      expect(Money.fromEuro(1.005).cents, 100);
      expect(const Money(101).cents, 101); // il modo corretto di esprimerlo
    });

    test('somma e sottrazione non perdono centesimi', () {
      // Il caso che rompe i double: 0.1 + 0.2 != 0.3
      final Money a = Money.fromEuro(0.1);
      final Money b = Money.fromEuro(0.2);
      expect((a + b).cents, Money.fromEuro(0.3).cents);
    });

    test('moltiplicazione arrotonda al centesimo', () {
      expect(const Money(333).multipliedBy(3).cents, 999);
      expect(const Money(10).multipliedBy(0.335).cents, 3); // 3.35 -> 3
    });

    test('percentuale', () {
      expect(const Money(1000).percent(22).cents, 220);
      expect(const Money(999).percent(10).cents, 100); // 99.9 -> 100
    });

    test('sum su lista vuota vale zero', () {
      expect(Money.sum(const <Money>[]), const Money.zero());
    });

    test('confronti e uguaglianza', () {
      expect(const Money(100) > const Money(99), isTrue);
      expect(const Money(100) == const Money(100), isTrue);
      // Duplicato intenzionale: verifica che l'uguaglianza per valore faccia
      // collassare a un solo elemento nel Set.
      // ignore: equal_elements_in_set
      expect(<Money>{const Money(5), const Money(5)}.length, 1);
    });
  });
}
