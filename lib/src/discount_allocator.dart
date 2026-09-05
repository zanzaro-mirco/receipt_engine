import 'money.dart';

/// Distribuisce lo sconto di documento fra gli importi che lo compongono.
///
/// È una strategia a sé perché il criterio di ripartizione è una scelta
/// contabile, non un dettaglio del calcolo: c'è chi lo ripartisce in
/// proporzione, chi lo imputa interamente all'articolo più caro, chi segue
/// regole di paese. Isolandolo, cambiare criterio significa passare un'altra
/// implementazione e non riaprire il motore di calcolo.
abstract interface class DiscountAllocator {
  /// Restituisce, per ciascun importo in [amounts], il valore al netto della
  /// quota di sconto di sua competenza.
  ///
  /// Invariante che ogni implementazione deve rispettare: la somma dei valori
  /// restituiti è esattamente `subtotal - discount`, senza centesimi persi per
  /// arrotondamento.
  List<Money> allocate({
    required List<Money> amounts,
    required Money subtotal,
    required Money discount,
  });
}

/// Ripartizione proporzionale al peso di ciascun importo.
///
/// L'ultimo scaglione assorbe la differenza di arrotondamento: è il modo più
/// semplice per garantire l'invariante senza inseguire i centesimi.
class ProportionalDiscountAllocator implements DiscountAllocator {
  /// Crea la strategia. Non ha stato: se ne può usare una sola istanza.
  const ProportionalDiscountAllocator();

  @override
  List<Money> allocate({
    required List<Money> amounts,
    required Money subtotal,
    required Money discount,
  }) {
    if (amounts.isEmpty) return const <Money>[];
    if (discount.isZero) return List<Money>.of(amounts);

    final Money target = subtotal - discount;
    final List<Money> result = <Money>[];
    Money distributed = const Money.zero();

    for (int i = 0; i < amounts.length; i++) {
      if (i == amounts.length - 1) {
        result.add(target - distributed);
      } else {
        final Money share = subtotal.isZero
            ? const Money.zero()
            : discount.multipliedBy(amounts[i].cents / subtotal.cents);
        final Money net = amounts[i] - share;
        result.add(net);
        distributed = distributed + net;
      }
    }
    return result;
  }
}
