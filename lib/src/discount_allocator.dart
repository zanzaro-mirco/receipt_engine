import 'money.dart';

/// Distribuisce lo sconto di documento fra i totali delle singole aliquote.
///
/// È una strategia a sé perché il criterio di ripartizione è una scelta
/// contabile, non un dettaglio del calcolo: c'è chi lo ripartisce in
/// proporzione, chi lo imputa interamente all'aliquota più alta, chi segue
/// regole di paese. Isolandolo, cambiare criterio significa passare un'altra
/// implementazione e non riaprire il motore di calcolo.
abstract interface class DiscountAllocator {
  /// Restituisce, per ciascun importo in [grossByRate], il valore al netto
  /// della quota di sconto di sua competenza.
  ///
  /// Invariante che ogni implementazione deve rispettare: la somma dei valori
  /// restituiti è esattamente `subtotal - discount`, senza centesimi persi per
  /// arrotondamento.
  List<Money> allocate({
    required List<Money> grossByRate,
    required Money subtotal,
    required Money discount,
  });
}

/// Ripartizione proporzionale al peso di ciascuna aliquota.
///
/// L'ultimo scaglione assorbe la differenza di arrotondamento: è il modo più
/// semplice per garantire l'invariante senza inseguire i centesimi.
class ProportionalDiscountAllocator implements DiscountAllocator {
  const ProportionalDiscountAllocator();

  @override
  List<Money> allocate({
    required List<Money> grossByRate,
    required Money subtotal,
    required Money discount,
  }) {
    if (grossByRate.isEmpty) return const <Money>[];
    if (discount.isZero) return List<Money>.of(grossByRate);

    final Money target = subtotal - discount;
    final List<Money> result = <Money>[];
    Money distributed = const Money.zero();

    for (int i = 0; i < grossByRate.length; i++) {
      if (i == grossByRate.length - 1) {
        result.add(target - distributed);
      } else {
        final Money share = subtotal.isZero
            ? const Money.zero()
            : discount.multipliedBy(grossByRate[i].cents / subtotal.cents);
        final Money net = grossByRate[i] - share;
        result.add(net);
        distributed = distributed + net;
      }
    }
    return result;
  }
}
