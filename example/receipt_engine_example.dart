import 'dart:convert';

import 'package:receipt_engine/receipt_engine.dart';

const MoneyFormatter fmt = ItalianMoneyFormatter();

void main() {
  final Receipt receipt = ReceiptBuilder(id: 'T-0001')
      .addLine(
        description: 'Caffè',
        unitPrice: Money.fromEuro(1.20),
        vatRate: VatRate.reduced,
        quantity: 2,
      )
      .addLine(
        description: 'Vino',
        unitPrice: Money.fromEuro(12.20),
        vatRate: VatRate.standard,
        discount: Discount.percent(10),
      )
      .applyDocumentDiscount(Discount.amount(Money.fromEuro(1)))
      .close(paid: Money.fromEuro(20));

  print('Scontrino ${receipt.id}');
  print('  Totale: ${fmt.format(receipt.total)}');
  print('  Resto:  ${fmt.format(receipt.change)}');
  for (final VatBreakdown v in receipt.vatSummary) {
    print('  $v');
  }

  // Il cliente riporta il vino. Lo scontrino non si tocca: si emette un reso.
  final ReturnReceipt reversal =
      ReturnBuilder(id: 'R-0001', original: receipt).addLine(1).close();

  print('');
  print('Reso ${reversal.id} su ${reversal.originalReceiptId}');
  print('  Da restituire: ${fmt.format(reversal.refund)}');
  for (final VatBreakdown v in reversal.vatSummary) {
    print('  $v');
  }

  // Il rimborso è quanto il cliente aveva pagato per quella riga, cioè al netto
  // della sua quota di sconto di documento: 10,98 di riga meno la quota di
  // sconto, non 10,98 tondi.
  print('');
  print('  Totale di riga:  ${fmt.format(receipt.lines[1].total)}');
  print('  Davvero pagato:  ${fmt.format(receipt.netLineTotals[1])}');
  print('  Saldo dopo il reso: '
      '${fmt.format(receipt.total + reversal.total)}');

  // Lo scontrino esce dal processo: verso un backend, una coda, un file.
  // `dart:convert` sta qui nell'esempio e non dentro il pacchetto — il codec
  // produce una mappa, e chi la usa sceglie come scriverla.
  const ReceiptJson codec = ReceiptJson();
  final String wire = jsonEncode(codec.encodeReceipt(receipt));
  final Receipt reread =
      codec.decodeReceipt(jsonDecode(wire) as Map<String, Object?>);

  print('');
  print('JSON: ${wire.length} caratteri');
  print('  Totale riletto: ${fmt.format(reread.total)}');
  print('  Imposta riletta: ${fmt.format(reread.totalTax)}');
  // Il documento riletto non passa dal builder: i totali sono quelli emessi,
  // non ricalcolati. Un documento fiscale si rilegge, non si rifà.
  print('  Ricalcolato? no: e i totali di riga sono ancora '
      '${reread.netLineTotals.map((Money m) => fmt.format(m)).join(', ')}');

  // Un altro cliente paga misto: 15 € con la carta e 10 in contanti su un
  // totale di 22. Il resto esce dal cassetto, e solo da lì.
  final Receipt mixed = ReceiptBuilder(id: 'T-0002')
      .addLine(
    description: 'Menù pranzo',
    unitPrice: Money.fromEuro(22),
    vatRate: VatRate.reduced,
  )
      .closeWithPayments(<Payment>[
    Payment.electronic(Money.fromEuro(15)),
    Payment.cash(Money.fromEuro(10)),
  ]);

  print('');
  print('Scontrino ${mixed.id}, pagato misto');
  for (final Payment payment in mixed.payments) {
    print('  $payment');
  }
  print('  Resto:  ${fmt.format(mixed.change)}');

  // Con la sola carta, 25 € su 22 non fanno 3 € di resto: non sono in cassa.
  try {
    ReceiptBuilder(id: 'T-0003')
        .addLine(
      description: 'Menù pranzo',
      unitPrice: Money.fromEuro(22),
      vatRate: VatRate.reduced,
    )
        .closeWithPayments(<Payment>[Payment.electronic(Money.fromEuro(25))]);
  } on ChangeNotAvailableError catch (e) {
    print('  Con la sola carta: ${e.message}');
  }
}
