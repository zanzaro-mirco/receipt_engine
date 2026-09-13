import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

void main() {
  const VatCalculator calculator = VatCalculator();

  group('VatCalculator.splitFromGross', () {
    test('scorpora il 22% da un importo lordo', () {
      final VatBreakdown r =
          calculator.splitFromGross(const Money(1220), VatRate.standard);
      expect(r.taxable, const Money(1000));
      expect(r.tax, const Money(220));
    });

    test('imponibile + imposta è sempre uguale al lordo', () {
      // Proprietà che protegge dallo scontrino che non quadra per un centesimo.
      for (int cents = 1; cents <= 2000; cents++) {
        final Money gross = Money(cents);
        for (final VatRate rate in <VatRate>[
          VatRate.standard,
          VatRate.reduced,
          VatRate.superReduced,
        ]) {
          final VatBreakdown r = calculator.splitFromGross(gross, rate);
          expect(r.taxable + r.tax, gross,
              reason: 'lordo $cents cent con aliquota $rate');
        }
      }
    });

    test("lo scorporo di un importo negativo è l'opposto di quello positivo",
        () {
      // Proprietà su cui si regge il riepilogo IVA dei resi: il documento di
      // reso passa importi negativi dentro questo stesso calcolo invece di
      // duplicarlo. Vale perché l'arrotondamento di Money è half-away-from-zero
      // e quindi simmetrico: con un "half up" lo scorporo di -3,00 non sarebbe
      // l'opposto di quello di +3,00 e uno scontrino stornato per intero
      // lascerebbe un centesimo di imposta appeso.
      for (int cents = 1; cents <= 2000; cents++) {
        for (final VatRate rate in <VatRate>[
          VatRate.standard,
          VatRate.reduced,
          VatRate.superReduced,
          VatRate.exempt,
        ]) {
          final VatBreakdown positive =
              calculator.splitFromGross(Money(cents), rate);
          final VatBreakdown negative =
              calculator.splitFromGross(Money(-cents), rate);

          expect(negative.taxable, -positive.taxable,
              reason: 'imponibile, $cents cent con aliquota $rate');
          expect(negative.tax, -positive.tax,
              reason: 'imposta, $cents cent con aliquota $rate');
        }
      }
    });

    test('aliquota zero non genera imposta', () {
      final VatBreakdown r =
          calculator.splitFromGross(const Money(500), VatRate.exempt);
      expect(r.tax, const Money.zero());
      expect(r.taxable, const Money(500));
    });

    test('addToTaxable aggiunge l imposta all imponibile', () {
      final VatBreakdown r =
          calculator.addToTaxable(const Money(1000), VatRate.standard);
      expect(r.tax, const Money(220));
      expect(r.gross, const Money(1220));
    });
  });

  group('Aliquote frazionarie', () {
    const VatCalculator calculator = VatCalculator();

    // Il pacchetto non conosce le regole fiscali francesi, e non pretende di
    // conoscerle: quello che deve reggere è lo scorporo su un divisore non
    // intero, che prima della 0.4.0 non era nemmeno esprimibile.
    const VatRate tauxReduit = VatRate(5.5, label: 'Taux réduit');
    const VatRate tauxParticulier = VatRate(2.1, label: 'Taux particulier');

    test('scorpora al 5,5% ricomponendo esattamente il lordo', () {
      final VatBreakdown r =
          calculator.splitFromGross(const Money(1055), tauxReduit);
      expect(r.taxable, const Money(1000));
      expect(r.tax, const Money(55));
      expect(r.taxable + r.tax, r.gross);
    });

    test(
        'imponibile più imposta fa il lordo su ogni centesimo fino a dieci euro',
        () {
      for (int cents = 1; cents <= 1000; cents++) {
        for (final VatRate rate in <VatRate>[tauxReduit, tauxParticulier]) {
          final VatBreakdown r = calculator.splitFromGross(Money(cents), rate);
          expect(r.taxable + r.tax, r.gross,
              reason: 'lo scorporo non ricompone $cents cent al $rate');
        }
      }
    });

    test('addToTaxable calcola l imposta su una percentuale non intera', () {
      final VatBreakdown r =
          calculator.addToTaxable(const Money(1000), tauxReduit);
      expect(r.tax, const Money(55));
      expect(r.gross, const Money(1055));
    });

    test('un intero scritto come double è la stessa aliquota', () {
      // Conta perché il riepilogo raggruppa per aliquota: se `22` e `22.0`
      // fossero due chiavi diverse, lo stesso scontrino produrrebbe due righe
      // a seconda di come chi chiama ha scritto il letterale.
      expect(const VatRate(22.0), VatRate.standard);
      expect(const VatRate(22.0).hashCode, VatRate.standard.hashCode);
    });

    test('si stampa in italiano, e senza decimali quando non servono', () {
      expect(tauxReduit.toString(), '5,5%');
      expect(VatRate.standard.toString(), '22%');
      expect(const VatRate(22.0).toString(), '22%');
    });

    test('ordina fra intere e frazionarie', () {
      final List<VatRate> rates = <VatRate>[
        VatRate.standard,
        tauxReduit,
        VatRate.reduced,
        tauxParticulier,
      ]..sort();
      expect(rates.map((VatRate r) => r.percentage), <num>[2.1, 5.5, 10, 22]);
    });
  });
}
