/// Importo monetario rappresentato in centesimi.
///
/// I `double` non si usano per il denaro: `0.1 + 0.2` non fa `0.3` in virgola
/// mobile binaria, e su uno scontrino questo diventa un errore contabile.
/// Tutta l'aritmetica avviene su interi; la conversione in decimale è solo
/// una questione di presentazione.
class Money implements Comparable<Money> {
  /// Crea un importo a partire dai centesimi.
  const Money(this.cents);

  /// Importo nullo.
  const Money.zero() : cents = 0;

  /// Crea un importo da un valore in euro.
  ///
  /// Da usare **solo ai bordi del sistema** (input utente, parsing di un
  /// listino): all'interno del dominio si lavora sempre in centesimi.
  ///
  /// Attenzione al confine: `Money.fromEuro(1.005)` restituisce 100 centesimi,
  /// non 101, perché `1.005` in virgola mobile binaria vale in realtà
  /// `1.00499999999999989`. Non è un difetto di questa classe, è la ragione
  /// per cui il denaro non si rappresenta con i `double`.
  factory Money.fromEuro(num euro) => Money((euro * 100).round());

  /// Valore in centesimi. Può essere negativo (storni, sconti).
  final int cents;

  bool get isZero => cents == 0;
  bool get isNegative => cents < 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);

  /// Moltiplica per un fattore arrotondando al centesimo.
  ///
  /// L'arrotondamento è half-away-from-zero, coerente con `num.round()` di
  /// Dart e con la prassi commerciale italiana.
  Money multipliedBy(num factor) => Money((cents * factor).round());

  /// Applica una percentuale (es. 10 per il 10%).
  Money percent(num percentage) => multipliedBy(percentage / 100);

  /// Somma di una lista di importi.
  static Money sum(Iterable<Money> values) =>
      values.fold(const Money.zero(), (a, b) => a + b);

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  /// Rappresentazione tecnica, per log e messaggi di errore.
  ///
  /// La formattazione destinata all'utente sta in `MoneyFormatter`: un value
  /// object di dominio non deve sapere come si scrive un numero in italiano.
  @override
  String toString() => 'Money($cents cent)';
}
