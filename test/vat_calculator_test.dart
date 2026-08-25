import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

void main() {
  const VatCalculator calculator = VatCalculator();

  group('VatCalculator.splitFromGross', () {
    test('scorpora il 22% da un importo lordo', () {
      final VatBreakdown r =
          calculator.splitFromGross(const Money(1220), VatRate.ordinaria);
      expect(r.taxable, const Money(1000));
      expect(r.tax, const Money(220));
    });

    test('imponibile + imposta è sempre uguale al lordo', () {
      // Proprietà che protegge dallo scontrino che non quadra per un centesimo.
      for (int cents = 1; cents <= 2000; cents++) {
        final Money gross = Money(cents);
        for (final VatRate rate in <VatRate>[
          VatRate.ordinaria,
          VatRate.ridotta,
          VatRate.superRidotta,
        ]) {
          final VatBreakdown r = calculator.splitFromGross(gross, rate);
          expect(r.taxable + r.tax, gross,
              reason: 'lordo $cents cent con aliquota $rate');
        }
      }
    });

    test('aliquota zero non genera imposta', () {
      final VatBreakdown r =
          calculator.splitFromGross(const Money(500), VatRate.esente);
      expect(r.tax, const Money.zero());
      expect(r.taxable, const Money(500));
    });

    test('addToTaxable aggiunge l imposta all imponibile', () {
      final VatBreakdown r =
          calculator.addToTaxable(const Money(1000), VatRate.ordinaria);
      expect(r.tax, const Money(220));
      expect(r.gross, const Money(1220));
    });
  });
}
