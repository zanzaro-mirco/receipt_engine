/// Aliquota IVA.
///
/// Modellata come classe e non come enum perché le aliquote cambiano per legge
/// e per paese: un enum costringerebbe a rilasciare una nuova versione del
/// pacchetto a ogni variazione normativa.
///
/// La percentuale è un [num] e non un `int` per la stessa ragione. Metà delle
/// aliquote europee non sono intere — la Francia ha il 5,5% e il 2,1%,
/// l'Irlanda il 13,5% — e un intero avrebbe smentito la frase qui sopra:
///
/// ```dart
/// const VatRate tauxReduit = VatRate(5.5, label: 'Taux réduit');
/// ```
///
/// Il pacchetto resta calibrato sull'IVA italiana: quello che garantisce è che
/// lo scorporo e il riepilogo funzionino su qualunque percentuale, non che
/// conosca le regole di un altro paese.
class VatRate implements Comparable<VatRate> {
  /// Crea un'aliquota dalla percentuale (22 per il 22%, 5.5 per il 5,5%).
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

  /// Percentuale: 22 per il 22%, 5.5 per il 5,5%.
  final num percentage;

  /// Descrizione per l'operatore. Non entra nel confronto fra aliquote:
  /// due aliquote con la stessa percentuale sono la stessa aliquota, come
  /// vuole il riepilogo fiscale, anche se le chiamano in modo diverso.
  final String label;

  @override
  int compareTo(VatRate other) => percentage.compareTo(other.percentage);

  /// Due aliquote con la stessa percentuale sono la stessa aliquota, anche se
  /// una la scrive `22` e l'altra `22.0`: in Dart i due valori sono uguali e
  /// hanno lo stesso codice hash, e il riepilogo per aliquota non deve
  /// spaccarsi in due righe per come è stato scritto un letterale.
  @override
  bool operator ==(Object other) =>
      other is VatRate && other.percentage == percentage;

  @override
  int get hashCode => percentage.hashCode;

  /// Percentuale in formato italiano: `22%`, `5,5%`.
  ///
  /// Le aliquote intere restano senza decimali anche quando arrivano da un
  /// `double`, altrimenti `VatRate(22.0)` si stamperebbe `22.0%`.
  @override
  String toString() {
    final String digits = percentage == percentage.truncate()
        ? percentage.truncate().toString()
        : percentage.toString();
    return '${digits.replaceAll('.', ',')}%';
  }
}
