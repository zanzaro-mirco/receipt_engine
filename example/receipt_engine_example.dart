import 'package:receipt_engine/receipt_engine.dart';

const MoneyFormatter fmt = ItalianMoneyFormatter();

void main() {
  final Receipt receipt = ReceiptBuilder(id: 'T-0001')
      .addLine(
        description: 'Caffè',
        unitPrice: Money.fromEuro(1.20),
        vatRate: VatRate.ridotta,
        quantity: 2,
      )
      .addLine(
        description: 'Vino',
        unitPrice: Money.fromEuro(12.20),
        vatRate: VatRate.ordinaria,
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
  final ReturnReceipt storno =
      ReturnBuilder(id: 'R-0001', original: receipt).addLine(1).close();

  print('');
  print('Reso ${storno.id} su ${storno.originalReceiptId}');
  print('  Da restituire: ${fmt.format(storno.refund)}');
  for (final VatBreakdown v in storno.vatSummary) {
    print('  $v');
  }

  // Il rimborso è quanto il cliente aveva pagato per quella riga, cioè al netto
  // della sua quota di sconto di documento: 10,98 di riga meno la quota di
  // sconto, non 10,98 tondi.
  print('');
  print('  Totale di riga:  ${fmt.format(receipt.lines[1].total)}');
  print('  Davvero pagato:  ${fmt.format(receipt.netLineTotals[1])}');
  print('  Saldo dopo il reso: '
      '${fmt.format(receipt.total + storno.total)}');
}
