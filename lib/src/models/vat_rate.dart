/// Aliquota IVA.
///
/// Modellata come classe e non come enum perché le aliquote cambiano per legge
/// e per paese: un enum costringerebbe a rilasciare una nuova versione del
/// pacchetto a ogni variazione normativa.
class VatRate implements Comparable<VatRate> {
  /// Crea un'aliquota dalla percentuale intera (22 per il 22%).
  const VatRate(this.percentage, {this.label = ''})
      : assert(percentage >= 0, 'Aliquota negativa non ammessa');

  /// Aliquota ordinaria italiana.
  static const VatRate ordinaria = VatRate(22, label: 'Ordinaria');

  /// Aliquota ridotta (es. ristorazione, alcuni alimentari).
  static const VatRate ridotta = VatRate(10, label: 'Ridotta');

  /// Aliquota super-ridotta.
  static const VatRate superRidotta = VatRate(4, label: 'Super ridotta');

  /// Operazione esente / non imponibile.
  static const VatRate esente = VatRate(0, label: 'Esente');

  final int percentage;
  final String label;

  @override
  int compareTo(VatRate other) => percentage.compareTo(other.percentage);

  @override
  bool operator ==(Object other) =>
      other is VatRate && other.percentage == percentage;

  @override
  int get hashCode => percentage.hashCode;

  @override
  String toString() => '$percentage%';
}
