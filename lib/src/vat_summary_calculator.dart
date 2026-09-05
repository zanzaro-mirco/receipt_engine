import 'discount_allocator.dart';
import 'models/receipt_line.dart';
import 'models/vat_rate.dart';
import 'money.dart';
import 'vat_calculator.dart';

/// Un importo con l'aliquota a cui appartiene.
///
/// È la sola cosa che serve per costruire un riepilogo IVA: non una riga di
/// scontrino, non una riga di reso, solo una coppia. Grazie a questo il
/// riepilogo di un documento di reso passa per lo stesso codice di quello di
/// uno scontrino.
typedef RatedAmount = ({VatRate rate, Money amount});

/// Esito del calcolo di un documento.
///
/// I due valori escono dalla **stessa** ripartizione dello sconto, ed è il
/// punto: se il totale di una riga e il riepilogo per aliquota venissero da due
/// ripartizioni diverse, potrebbero divergere di un centesimo e un reso totale
/// non tornerebbe a zero.
typedef DocumentTotals = ({
  List<Money> netLineTotals,
  List<VatBreakdown> vatSummary,
});

/// Costruisce il riepilogo IVA di un documento.
///
/// Prima questa logica stava dentro `ReceiptBuilder`, che si ritrovava a fare
/// tre cose: gestire lo stato aperto/chiuso, ripartire lo sconto di documento
/// e calcolare l'imposta. Separandola, il builder torna a occuparsi solo del
/// ciclo di vita del documento e questo calcolo diventa testabile da solo,
/// senza costruire uno scontrino.
class VatSummaryCalculator {
  /// Crea il calcolatore.
  ///
  /// [calculator] decide come si scorpora l'imposta, [allocator] come si
  /// ripartisce lo sconto di documento: due scelte indipendenti, ed è il
  /// motivo per cui arrivano da fuori invece di essere costruite qui.
  const VatSummaryCalculator({
    VatCalculator calculator = const VatCalculator(),
    DiscountAllocator allocator = const ProportionalDiscountAllocator(),
  })  : _calculator = calculator,
        _allocator = allocator;

  final VatCalculator _calculator;
  final DiscountAllocator _allocator;

  /// Ripartisce lo sconto di documento sulle righe e ne ricava il riepilogo
  /// per aliquota.
  ///
  /// Lo sconto si ripartisce **una volta sola, e sulle righe**. Prima veniva
  /// ripartito sui totali già raggruppati per aliquota: finché l'unico
  /// consumatore era il riepilogo IVA la differenza non si vedeva, perché in
  /// entrambi i casi la somma torna. Si è vista con i resi, dove serve sapere
  /// quanto è stato incassato per *una riga*: due ripartizioni diverse davano
  /// due numeri che differivano di un centesimo, e uno scontrino reso per
  /// intero non tornava a zero.
  DocumentTotals compute({
    required List<ReceiptLine> lines,
    required Money documentDiscount,
  }) {
    final List<Money> gross = lines.map((ReceiptLine l) => l.total).toList();
    final List<Money> net = _allocator.allocate(
      amounts: gross,
      subtotal: Money.sum(gross),
      discount: documentDiscount,
    );

    return (
      netLineTotals: net,
      vatSummary: summarize(<RatedAmount>[
        for (int i = 0; i < lines.length; i++)
          (rate: lines[i].vatRate, amount: net[i]),
      ]),
    );
  }

  /// Riepilogo per aliquota, ordinato in modo crescente, a partire da importi
  /// già al netto di ogni sconto.
  ///
  /// L'imposta si calcola sul totale per aliquota, non riga per riga: è il
  /// requisito normativo ed evita che gli arrotondamenti di riga si accumulino.
  ///
  /// Accetta importi **negativi** senza alcun trattamento speciale, ed è così
  /// che un documento di reso riusa questo calcolo invece di duplicarlo. Che
  /// funzioni non è ovvio: dipende dal fatto che l'arrotondamento di [Money] è
  /// half-away-from-zero e quindi simmetrico rispetto allo zero. Con un
  /// "half up" lo scorporo di `-3,00` non sarebbe l'opposto di quello di
  /// `+3,00` e un reso totale lascerebbe un centesimo di imposta appeso.
  List<VatBreakdown> summarize(Iterable<RatedAmount> amounts) {
    final Map<VatRate, Money> byRate = <VatRate, Money>{};
    for (final RatedAmount a in amounts) {
      byRate[a.rate] = (byRate[a.rate] ?? const Money.zero()) + a.amount;
    }

    final List<VatRate> rates = byRate.keys.toList()..sort();
    return <VatBreakdown>[
      for (final VatRate rate in rates)
        _calculator.splitFromGross(byRate[rate]!, rate),
    ];
  }

  /// Scorciatoia per chi vuole solo il riepilogo: equivale a
  /// `compute(...).vatSummary`.
  List<VatBreakdown> build({
    required List<ReceiptLine> lines,
    required Money documentDiscount,
  }) =>
      compute(lines: lines, documentDiscount: documentDiscount).vatSummary;
}
