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
  static const VatRate standard = VatRate(22, label: 'Ordinaria');

  /// Aliquota ridotta (es. ristorazione, alcuni alimentari).
  static const VatRate reduced = VatRate(10, label: 'Ridotta');

  /// Aliquota super-ridotta.
  static const VatRate superReduced = VatRate(4, label: 'Super ridotta');

  /// Operazione esente / non imponibile.
  static const VatRate exempt = VatRate(0, label: 'Esente');

  /// Percentuale intera: 22 per il 22%.
  final int percentage;

  /// Descrizione per l'operatore. Non entra nel confronto fra aliquote:
  /// due aliquote con la stessa percentuale sono la stessa aliquota, come
  /// vuole il riepilogo fiscale, anche se le chiamano in modo diverso.
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
