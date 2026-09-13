import '../money.dart';

/// Sconto applicabile a una riga o all'intero documento.
///
/// Gerarchia aperta e polimorfa: ogni tipo di sconto sa calcolarsi da solo.
/// La versione precedente usava uno `switch` su un enum, e questo violava
/// l'Open/Closed Principle — aggiungere uno sconto quantità o un "3x2"
/// obbligava a *modificare* il metodo di calcolo. Così invece si aggiunge una
/// sottoclasse e non si tocca niente di esistente, **anche da fuori dal
/// pacchetto**: chi lo usa può definire il proprio sconto senza aspettare una
/// nuova versione.
///
/// La classe è `base` e non `sealed`, per scelta. `base` lascia estendere ma
/// non implementare: un sottotipo passa sempre dal costruttore, e quindi ha
/// sempre una [description]. `sealed` avrebbe dato l'esaustività degli
/// `switch` al prezzo di chiudere la gerarchia a chi usa il pacchetto — cioè
/// di rinunciare esattamente al motivo per cui la gerarchia esiste.
///
/// Il costo è dichiarato: uno `switch` sui sottotipi di `Discount` non è mai
/// esaustivo, e il compilatore non segnala il caso mancante. Chi ne scrive
/// uno deve prevedere un caso finale — `ReceiptJson` lo fa, e un sottotipo che
/// non conosce lo rifiuta con un errore invece di farlo sparire dal documento.
abstract base class Discount {
  /// Costruttore delle sottoclassi.
  const Discount({this.description = ''});

  /// Sconto percentuale (es. `Discount.percent(10)` per il 10%).
  static Discount percent(num value, {String description = ''}) =>
      PercentageDiscount(value, description: description);

  /// Sconto a importo fisso.
  static Discount amount(Money value, {String description = ''}) =>
      AmountDiscount(value, description: description);

  /// Motivo dello sconto, da stampare sullo scontrino. Non entra nel
  /// calcolo.
  final String description;

  /// Importo dello sconto calcolato su una base imponibile.
  ///
  /// Contratto valido per ogni sottoclasse (Liskov): il risultato non è mai
  /// negativo e non supera mai la base. Chi aggiunge un tipo di sconto deve
  /// rispettarlo — un totale negativo non è un documento valido.
  Money appliedTo(Money base);
}

/// Sconto espresso in percentuale.
base class PercentageDiscount extends Discount {
  /// Crea uno sconto percentuale. Rifiuta un valore fuori da 0-100.
  PercentageDiscount(this.value, {super.description = ''}) {
    if (value < 0 || value > 100) {
      throw ArgumentError.value(
          value, 'value', 'Percentuale fuori range 0-100');
    }
  }

  /// Percentuale da applicare: 10 per il 10%.
  final num value;

  @override
  Money appliedTo(Money base) => base.percent(value);

  @override
  String toString() => 'Sconto $value%';
}

/// Sconto espresso come importo fisso.
///
/// Se l'importo supera la base viene limitato alla base: è la traduzione
/// concreta del contratto dichiarato in [Discount.appliedTo].
base class AmountDiscount extends Discount {
  /// Crea uno sconto a importo fisso. Rifiuta un importo negativo.
  AmountDiscount(this.value, {super.description = ''}) {
    if (value.isNegative) {
      throw ArgumentError.value(value, 'value', 'Sconto negativo non ammesso');
    }
  }

  /// Importo da togliere, limitato alla base al momento del calcolo.
  final Money value;

  @override
  Money appliedTo(Money base) => value > base ? base : value;

  @override
  String toString() => 'Sconto di ${value.cents} centesimi';
}
