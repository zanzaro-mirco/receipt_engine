import 'dart:io';
import 'dart:math';

/// Un generatore di valori casuali, con il modo di semplificarli.
///
/// È il minimo indispensabile per fare property-based testing, scritto a mano
/// per una ragione verificabile: `glados`, l'unico pacchetto Dart del genere,
/// dichiara `sdk: >=2.12.0 <3.0.0` e non è compatibile con Dart 3.
///
/// La parte che conta non è [generate] ma [shrink]. Un generatore che trova un
/// caso rotto fra migliaia di valori casuali consegna un controesempio
/// illeggibile — dodici righe, importi a sei cifre — e da lì non si capisce
/// *cosa* è rotto. Semplificare il controesempio finché resta rotto è ciò che
/// trasforma una segnalazione in una diagnosi.
class Gen<T> {
  /// Crea un generatore.
  ///
  /// Senza [shrink] il controesempio viene riportato com'è stato generato.
  const Gen(this.generate, {this.shrink = _noShrink});

  /// Produce un valore a partire da una sorgente di casualità.
  final T Function(Random random) generate;

  /// Restituisce valori più semplici di quello dato, dal più semplice in poi.
  ///
  /// Non deve mai restituire il valore stesso: la ricerca non terminerebbe.
  final Iterable<T> Function(T value) shrink;

  static Iterable<Never> _noShrink(Object? value) => const <Never>[];

  /// Deriva un generatore applicando [transform] ai valori prodotti.
  ///
  /// La semplificazione si perde: `map` non sa tornare indietro dal valore
  /// trasformato a quello originale. Per i tipi su cui la diagnosi conta si
  /// scrive un [Gen] con il suo [shrink].
  Gen<R> map<R>(R Function(T value) transform) =>
      Gen<R>((Random r) => transform(generate(r)));
}

/// Numero di casi provati per ogni proprietà, se non diversamente indicato.
const int defaultExamples = 300;

/// Seme della sorgente casuale.
///
/// Fisso, e non «ogni volta diverso», perché una suite che fallisce su un caso
/// che non si sa riprodurre è una suite che qualcuno disattiva. Con un seme
/// fisso la stessa esecuzione esplora sempre gli stessi casi: se passa oggi
/// passa domani, e un fallimento è ripetibile con un comando.
///
/// Per cercare più a fondo si allarga la ricerca da fuori, senza toccare il
/// codice:
///
/// ```bash
/// PROPERTY_SEED=12345 dart test test/properties
/// ```
int get propertySeed {
  final String? fromEnvironment = Platform.environment['PROPERTY_SEED'];
  return fromEnvironment == null ? 20260912 : int.parse(fromEnvironment);
}

/// Verifica che [property] valga per ogni valore prodotto da [gen].
///
/// Al primo valore che la viola, cerca il controesempio più semplice che la
/// viola ancora e lo riporta insieme al seme, così che il caso si possa
/// rieseguire.
void forAll<T>(
  Gen<T> gen,
  void Function(T value) property, {
  int examples = defaultExamples,
  int? seed,
}) {
  final int usedSeed = seed ?? propertySeed;
  final Random random = Random(usedSeed);

  for (int i = 0; i < examples; i++) {
    final T value = gen.generate(random);
    final Object? failure = _failureOf(property, value);
    if (failure == null) continue;

    final T simplest = _shrink(gen, value, property);
    final Object? simplestFailure = _failureOf(property, simplest);

    throw _PropertyFailure(
      seed: usedSeed,
      examplesTried: i + 1,
      original: value,
      simplest: simplest,
      cause: simplestFailure ?? failure,
    );
  }
}

/// L'errore sollevato da [property], oppure `null` se è passata.
Object? _failureOf<T>(void Function(T) property, T value) {
  try {
    property(value);
    return null;
  } on _PropertyFailure {
    rethrow;
  } catch (error) {
    return error;
  }
}

/// Scende verso il valore più semplice che continua a violare la proprietà.
///
/// Avidamente: appena un candidato fallisce si riparte da lui. Non garantisce
/// il minimo assoluto, e non serve — serve un caso che una persona possa
/// leggere.
T _shrink<T>(Gen<T> gen, T failing, void Function(T) property) {
  T best = failing;
  int budget = 500;

  bool improved = true;
  while (improved && budget > 0) {
    improved = false;
    for (final T candidate in gen.shrink(best)) {
      if (--budget <= 0) break;
      if (_failureOf(property, candidate) != null) {
        best = candidate;
        improved = true;
        break;
      }
    }
  }
  return best;
}

class _PropertyFailure implements Exception {
  _PropertyFailure({
    required this.seed,
    required this.examplesTried,
    required this.original,
    required this.simplest,
    required this.cause,
  });

  final int seed;
  final int examplesTried;
  final Object? original;
  final Object? simplest;
  final Object? cause;

  @override
  String toString() => <String>[
        'Proprietà violata dopo $examplesTried casi (seme $seed).',
        '',
        'Controesempio più semplice:',
        '  $simplest',
        '',
        'Errore:',
        '  $cause',
        '',
        'Generato a partire da:',
        '  $original',
        '',
        'Per rieseguire esattamente questa ricerca:',
        '  PROPERTY_SEED=$seed dart test test/properties',
      ].join('\n');
}
