import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

void main() {
  const DiscountAllocator allocator = ProportionalDiscountAllocator();

  List<Money> run(List<int> gross, int discount) {
    final List<Money> values = gross.map(Money.new).toList();
    return allocator.allocate(
      grossByRate: values,
      subtotal: Money.sum(values),
      discount: Money(discount),
    );
  }

  group('ProportionalDiscountAllocator', () {
    test('senza sconto restituisce i valori invariati', () {
      expect(
          run(<int>[100, 200], 0), <Money>[const Money(100), const Money(200)]);
    });

    test('lista vuota', () {
      expect(run(<int>[], 500), isEmpty);
    });

    test('ripartisce in proporzione al peso di ciascuna aliquota', () {
      final List<Money> r = run(<int>[1000, 3000], 400);
      // 25% e 75% del subtotale -> 100 e 300 di sconto
      expect(r.first, const Money(900));
      expect(r.last, const Money(2700));
    });

    test('la somma è sempre esattamente subtotale meno sconto', () {
      // L'invariante che protegge dallo scontrino che non quadra: qui si prova
      // su combinazioni che producono arrotondamenti scomodi.
      for (final List<int> gross in <List<int>>[
        <int>[777, 1111, 3333],
        <int>[1, 1, 1],
        <int>[9999, 1],
        <int>[333, 333, 333, 1],
      ]) {
        final Money subtotal = Money.sum(gross.map(Money.new));
        for (int discount = 0; discount <= subtotal.cents; discount += 17) {
          final List<Money> r = allocator.allocate(
            grossByRate: gross.map(Money.new).toList(),
            subtotal: subtotal,
            discount: Money(discount),
          );
          expect(Money.sum(r), subtotal - Money(discount),
              reason: 'gross $gross, sconto $discount');
        }
      }
    });

    test('con una sola aliquota assorbe tutto lo sconto', () {
      expect(run(<int>[1000], 137), <Money>[const Money(863)]);
    });
  });
}
