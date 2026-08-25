import '../money.dart';

/// Formattazione degli importi.
///
/// Sta fuori da [Money] di proposito: un value object di dominio non deve
/// sapere come si scrive un numero in italiano. Separandolo si può avere una
/// formattazione diversa per locale, per scontrino e per report senza toccare
/// il dominio — ed è una responsabilità in meno per la classe che regge tutta
/// l'aritmetica del pacchetto.
abstract interface class MoneyFormatter {
  String format(Money value);
}

/// Formato italiano: virgola come separatore decimale, simbolo in coda.
class ItalianMoneyFormatter implements MoneyFormatter {
  const ItalianMoneyFormatter({this.suffix = ' €'});

  final String suffix;

  @override
  String format(Money value) {
    final int abs = value.cents.abs();
    final String sign = value.cents < 0 ? '-' : '';
    final String units = (abs ~/ 100).toString();
    final String decimals = (abs % 100).toString().padLeft(2, '0');
    return '$sign$units,$decimals$suffix';
  }
}

/// Formato neutro per log e messaggi di errore.
class PlainMoneyFormatter implements MoneyFormatter {
  const PlainMoneyFormatter();

  @override
  String format(Money value) {
    final int abs = value.cents.abs();
    final String sign = value.cents < 0 ? '-' : '';
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }
}
