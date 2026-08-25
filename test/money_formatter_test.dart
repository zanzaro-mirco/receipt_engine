import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ItalianMoneyFormatter', () {
    const MoneyFormatter f = ItalianMoneyFormatter();

    test('usa la virgola e due decimali', () {
      expect(f.format(const Money(1234)), '12,34 €');
      expect(f.format(const Money(5)), '0,05 €');
      expect(f.format(const Money.zero()), '0,00 €');
    });

    test('gestisce gli importi negativi', () {
      expect(f.format(const Money(-250)), '-2,50 €');
    });

    test('il suffisso è configurabile', () {
      expect(const ItalianMoneyFormatter(suffix: '').format(const Money(1234)),
          '12,34');
    });
  });

  group('PlainMoneyFormatter', () {
    const MoneyFormatter f = PlainMoneyFormatter();

    test('usa il punto, per log e messaggi tecnici', () {
      expect(f.format(const Money(1234)), '12.34');
      expect(f.format(const Money(-5)), '-0.05');
    });
  });

  test('sostituire il formattatore non tocca il dominio', () {
    // La verifica concreta dell inversione delle dipendenze: la stessa somma
    // si presenta in due modi senza che Money sappia nulla di formattazione.
    final Money total = const Money(1000) + const Money(234);
    expect(const ItalianMoneyFormatter().format(total), '12,34 €');
    expect(const PlainMoneyFormatter().format(total), '12.34');
  });
}
