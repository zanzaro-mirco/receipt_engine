import 'formatting/money_formatter.dart';
import 'models/vat_rate.dart';
import 'money.dart';

/// Scomposizione di un importo lordo in imponibile e imposta.
class VatBreakdown {
  const VatBreakdown({
    required this.rate,
    required this.gross,
    required this.taxable,
    required this.tax,
  });

  final VatRate rate;

  /// Importo IVA inclusa.
  final Money gross;

  /// Imponibile.
  final Money taxable;

  /// Imposta.
  final Money tax;

  @override
  String toString() {
    const PlainMoneyFormatter f = PlainMoneyFormatter();
    return 'IVA $rate: imponibile ${f.format(taxable)}, imposta ${f.format(tax)}';
  }
}

/// Calcolo dell'IVA per scorporo.
///
/// Lo scorporo introduce un problema di arrotondamento: la somma delle imposte
/// calcolate riga per riga può differire di qualche centesimo dall'imposta
/// calcolata sul totale. La normativa italiana richiede lo scorporo sul totale
/// per aliquota, ed è quello che fa questa classe.
class VatCalculator {
  const VatCalculator();

  /// Scorpora l'IVA da un importo lordo.
  ///
  /// L'imposta viene derivata per differenza dall'imponibile arrotondato, così
  /// che `imponibile + imposta` sia sempre esattamente uguale al lordo. È la
  /// proprietà che evita di ritrovarsi uno scontrino che non quadra per un
  /// centesimo.
  VatBreakdown splitFromGross(Money gross, VatRate rate) {
    if (rate.percentage == 0) {
      return VatBreakdown(
        rate: rate,
        gross: gross,
        taxable: gross,
        tax: const Money.zero(),
      );
    }
    final int divisor = 100 + rate.percentage;
    final Money taxable = Money((gross.cents * 100 / divisor).round());
    final Money tax = gross - taxable;
    return VatBreakdown(rate: rate, gross: gross, taxable: taxable, tax: tax);
  }

  /// Calcola l'imposta da aggiungere a un imponibile.
  VatBreakdown addToTaxable(Money taxable, VatRate rate) {
    final Money tax = taxable.percent(rate.percentage);
    return VatBreakdown(
      rate: rate,
      gross: taxable + tax,
      taxable: taxable,
      tax: tax,
    );
  }
}
