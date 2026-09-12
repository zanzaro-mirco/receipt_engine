import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

final DateTime timestamp = DateTime(2026, 9, 4, 11, 15);

/// Scontrino di riferimento: tre righe, due aliquote, uno sconto di riga e uno
/// di documento.
///
/// Lo sconto di documento non è decorazione: è la condizione in cui un reso
/// fatto male si vede. Senza, il totale di riga e l'incassato coincidono e
/// qualunque implementazione sembra corretta.
Receipt receipt() => ReceiptBuilder(id: 'T-0001', issuedAt: timestamp)
    .addLine(
      description: 'Maglietta',
      unitPrice: Money.fromEuro(20),
      vatRate: VatRate.standard,
    )
    .addLine(
      description: 'Pane',
      unitPrice: Money.fromEuro(2),
      vatRate: VatRate.superReduced,
      quantity: 3,
    )
    .addLine(
      description: 'Vino',
      unitPrice: Money.fromEuro(12.20),
      vatRate: VatRate.standard,
      discount: Discount.percent(10),
    )
    .applyDocumentDiscount(Discount.percent(10))
    .close(paid: Money.fromEuro(50));

ReturnBuilder returnFor(
  Receipt original, {
  List<ReturnReceipt> previous = const <ReturnReceipt>[],
}) =>
    ReturnBuilder(
      id: 'R-0001',
      original: original,
      issuedAt: timestamp,
      previousReturns: previous,
    );

void main() {
  group('Il criterio: storno parziale', () {
    test('storna due righe su tre e la somma quadra a zero sulle righe rese',
        () {
      final Receipt r = receipt();
      final ReturnReceipt reversal = returnFor(r).addLine(0).addLine(2).close();

      // Quello che il cliente aveva pagato per le due righe rese: il totale di
      // riga dopo la ripartizione dello sconto di documento, non prima.
      final Money takenOnReturnedLines =
          Money.sum(<Money>[r.netLineTotals[0], r.netLineTotals[2]]);

      expect(takenOnReturnedLines + reversal.total, const Money.zero(),
          reason: 'scontrino e reso non si annullano sulle righe rese');

      expect(reversal.originalReceiptId, 'T-0001');
      expect(reversal.lines.map((ReturnLine l) => l.lineIndex), <int>[0, 2]);
      expect(reversal.lines.map((ReturnLine l) => l.description),
          <String>['Maglietta', 'Vino']);
      expect(reversal.total.isNegative, isTrue, reason: 'un reso è negativo');
      expect(reversal.refund, -reversal.total);
    });

    test('la riga non resa resta interamente a carico del cliente', () {
      final Receipt r = receipt();
      final ReturnReceipt reversal = returnFor(r).addLine(0).addLine(2).close();

      expect(r.total + reversal.total, r.netLineTotals[1],
          reason: 'dopo il reso deve restare esattamente il pane');
    });

    test('il reso non restituisce lo sconto di documento', () {
      // La riga vale 20,00 sullo scontrino, ma con il 10% di sconto di
      // documento il cliente ne ha pagati meno. Rimborsare il totale di riga
      // significherebbe restituirgli anche lo sconto.
      final Receipt r = receipt();
      final ReturnReceipt reversal = returnFor(r).addLine(0).close();

      expect(reversal.refund, lessThan(r.lines[0].total));
      expect(reversal.refund, r.netLineTotals[0]);
    });
  });

  group('Reso totale', () {
    test('ogni importo dello scontrino torna a zero, riepilogo IVA compreso',
        () {
      final Receipt r = receipt();
      final ReturnReceipt reversal = returnFor(r).addEverything().close();

      expect(r.total + reversal.total, const Money.zero());
      expect(r.totalTaxable + reversal.totalTaxable, const Money.zero());
      expect(r.totalTax + reversal.totalTax, const Money.zero());

      // Aliquota per aliquota, non solo sul totale: è qui che due ripartizioni
      // diverse dello sconto lascerebbero un centesimo appeso.
      expect(reversal.vatSummary.length, r.vatSummary.length);
      for (int i = 0; i < r.vatSummary.length; i++) {
        expect(reversal.vatSummary[i].rate, r.vatSummary[i].rate);
        expect(r.vatSummary[i].gross + reversal.vatSummary[i].gross,
            const Money.zero());
        expect(r.vatSummary[i].taxable + reversal.vatSummary[i].taxable,
            const Money.zero());
        expect(r.vatSummary[i].tax + reversal.vatSummary[i].tax,
            const Money.zero());
      }
    });

    test('rende tutte le quantità, non solo tutte le righe', () {
      final Receipt r = receipt();
      final ReturnReceipt reversal = returnFor(r).addEverything().close();

      expect(reversal.itemCount, r.itemCount);
      expect(reversal.lineCount, 3);
    });

    test('dopo un reso totale non resta niente da rendere', () {
      final Receipt r = receipt();
      final ReturnReceipt first = returnFor(r).addEverything().close();
      final ReturnBuilder second =
          returnFor(r, previous: <ReturnReceipt>[first]);

      expect(second.isFullyReturned, isTrue);
      expect(second.remainingQuantity(1), 0);
      expect(() => second.addLine(1), throwsArgumentError);
    });
  });

  group('Non si rende più di quanto venduto', () {
    test('una quantità superiore al venduto viene rifiutata', () {
      expect(
        () => returnFor(receipt()).addLine(1, quantity: 4),
        throwsA(isA<ExcessiveReturnError>()),
      );
    });

    test('i resi già emessi contano nel conteggio', () {
      // Senza questo, tre resi parziali da un pezzo permetterebbero di
      // restituire tre volte un articolo venduto una volta sola.
      final Receipt r = receipt();
      final ReturnReceipt first = returnFor(r).addLine(1, quantity: 2).close();
      final ReturnBuilder second =
          returnFor(r, previous: <ReturnReceipt>[first]);

      expect(second.remainingQuantity(1), 1);
      expect(
        () => second.addLine(1, quantity: 2),
        throwsA(isA<ExcessiveReturnError>()),
      );
      expect(second.addLine(1, quantity: 1).remainingQuantity(1), 0);
    });

    test('due aggiunte sulla stessa riga si sommano e insieme sforano', () {
      final ReturnBuilder b = returnFor(receipt())..addLine(1, quantity: 2);
      expect(b.remainingQuantity(1), 1);
      expect(
        () => b.addLine(1, quantity: 2),
        throwsA(isA<ExcessiveReturnError>()),
      );
    });

    test("l'errore dice quale riga e quanto restava", () {
      try {
        returnFor(receipt()).addLine(1, quantity: 5);
        fail('doveva sollevare');
      } on ExcessiveReturnError catch (e) {
        expect(e.lineIndex, 1);
        expect(e.requested, 5);
        expect(e.remaining, 3);
      }
    });

    test('un reso di un altro scontrino viene rifiutato', () {
      final Receipt r = receipt();
      final ReturnReceipt elsewhere = ReturnBuilder(
        id: 'R-9',
        original: ReceiptBuilder(id: 'T-9999', issuedAt: timestamp)
            .addLine(
              description: 'Altro',
              unitPrice: Money.fromEuro(1),
              vatRate: VatRate.standard,
            )
            .close(paid: Money.fromEuro(1)),
        issuedAt: timestamp,
      ).addLine(0).close();

      expect(
        () => returnFor(r, previous: <ReturnReceipt>[elsewhere]),
        throwsArgumentError,
      );
    });

    test('un indice di riga inesistente viene rifiutato', () {
      expect(() => returnFor(receipt()).addLine(3), throwsRangeError);
      expect(() => returnFor(receipt()).addLine(-1), throwsRangeError);
    });
  });

  group('Resi parziali e arrotondamento', () {
    test('rendere un pezzo alla volta restituisce quanto un reso unico', () {
      // L'invariante che regge tutto: comunque si spezzi il reso di una riga,
      // la somma dei rimborsi è esattamente quanto quella riga aveva incassato.
      // Con un arrotondamento non cumulativo qui si perderebbero centesimi.
      for (int price = 1; price <= 200; price++) {
        for (int quantity = 1; quantity <= 7; quantity++) {
          final Receipt r = ReceiptBuilder(id: 'T-0002', issuedAt: timestamp)
              .addLine(
                description: 'A',
                unitPrice: Money(price),
                vatRate: VatRate.standard,
                quantity: quantity,
              )
              .addLine(
                description: 'B',
                unitPrice: const Money(997),
                vatRate: VatRate.reduced,
              )
              .applyDocumentDiscount(Discount.percent(13))
              .close(paid: Money.fromEuro(100));

          final List<ReturnReceipt> issued = <ReturnReceipt>[];
          for (int k = 0; k < quantity; k++) {
            issued.add(
              ReturnBuilder(
                id: 'R-$k',
                original: r,
                issuedAt: timestamp,
                previousReturns: issued,
              ).addLine(0, quantity: 1).close(),
            );
          }

          final String scenario = 'prezzo $price, quantità $quantity';
          expect(
            Money.sum(issued.map((ReturnReceipt e) => e.lines.single.amount)),
            -r.netLineTotals[0],
            reason: scenario,
          );
          expect(
            issued.every((ReturnReceipt e) => e.lines.single.amount.cents <= 0),
            isTrue,
            reason: 'nessun reso può restituire un importo positivo: $scenario',
          );
        }
      }
    });

    test('una quantità frazionaria si rende come le altre', () {
      // Merce a peso: 1,5 kg venduti, 0,5 resi.
      final Receipt r = ReceiptBuilder(id: 'T-0003', issuedAt: timestamp)
          .addLine(
            description: 'Prosciutto',
            unitPrice: Money.fromEuro(30),
            vatRate: VatRate.reduced,
            quantity: 1.5,
          )
          .close(paid: Money.fromEuro(45));

      final ReturnReceipt reversal =
          returnFor(r).addLine(0, quantity: 0.5).close();

      expect(reversal.refund, Money.fromEuro(15));
      expect(reversal.lines.single.quantity, 0.5);
    });
  });

  group('Ciclo di vita del documento', () {
    test('non si può chiudere un reso senza righe', () {
      expect(() => returnFor(receipt()).close(), throwsStateError);
    });

    test('non si può operare su un reso già chiuso', () {
      final ReturnBuilder b = returnFor(receipt())..addLine(0);
      b.close();

      expect(() => b.addLine(1), throwsA(isA<ReceiptClosedError>()));
      expect(() => b.close(), throwsA(isA<ReceiptClosedError>()));
      expect(b.isClosed, isTrue);
    });

    test('le righe del reso chiuso non sono modificabili', () {
      final ReturnReceipt reversal = returnFor(receipt()).addLine(0).close();
      expect(
        () => reversal.lines.add(reversal.lines.first),
        throwsUnsupportedError,
      );
    });

    test('il riepilogo IVA del reso è ordinato per aliquota crescente', () {
      final ReturnReceipt reversal =
          returnFor(receipt()).addEverything().close();
      expect(
        reversal.vatSummary.map((VatBreakdown v) => v.rate.percentage),
        <int>[4, 22],
      );
      expect(reversal.vatSummary.every((VatBreakdown v) => v.gross.isNegative),
          isTrue);
    });
  });

  // I casi qui sotto vengono dai test di proprietà in `test/properties`, e
  // stanno qui perché un caso limite trovato una volta va tenuto fermo con un
  // nome: la ricerca casuale esplora, la regressione custodisce.
  group('Merce a peso, resa a pezzi', () {
    test(
        'tre tranche da un etto su tre etti venduti: la terza non va rifiutata',
        () {
      final Receipt sold = (ReceiptBuilder(id: 'S')
            ..addLine(
              description: 'Prosciutto',
              unitPrice: const Money(2000),
              vatRate: VatRate.standard,
              quantity: 0.3,
            ))
          .close(paid: const Money(600));

      // 0,1 + 0,1 + 0,1 fa 0,30000000000000004 in virgola mobile binaria.
      // Senza tolleranza il residuo prima della terza tranche è
      // 0.09999999999999998, e alla cassa non si può rimborsare l'ultimo etto.
      final List<ReturnReceipt> emitted = <ReturnReceipt>[];
      for (int i = 0; i < 3; i++) {
        emitted.add(
          (ReturnBuilder(id: 'R$i', original: sold, previousReturns: emitted)
                ..addLine(0, quantity: 0.1))
              .close(),
        );
      }

      expect(Money.sum(emitted.map((ReturnReceipt r) => r.total)), -sold.total,
          reason: 'Le tre tranche devono restituire esattamente il venduto');

      final ReturnBuilder after = ReturnBuilder(
        id: 'R3',
        original: sold,
        previousReturns: emitted,
      );
      expect(after.remainingQuantity(0), 0,
          reason: 'Un residuo entro la tolleranza si legge zero, non 5e-17');
      expect(after.isFullyReturned, isTrue);
    });

    test('rendere più del venduto resta un errore', () {
      final Receipt sold = (ReceiptBuilder(id: 'S')
            ..addLine(
              description: 'Prosciutto',
              unitPrice: const Money(2000),
              vatRate: VatRate.standard,
              quantity: 0.3,
            ))
          .close(paid: const Money(600));

      // La tolleranza copre il rumore dei double, non una quantità in più: un
      // decimo di troppo sta otto ordini di grandezza sopra.
      expect(
        () => ReturnBuilder(id: 'R', original: sold).addLine(0, quantity: 0.4),
        throwsA(isA<ExcessiveReturnError>()),
      );
    });
  });

  group('Imposta stornata su più documenti', () {
    test('due tranche stornano un centesimo di imposta in più del venduto', () {
      final Receipt sold = (ReceiptBuilder(id: 'S')
            ..addLine(
              description: 'Merce',
              unitPrice: const Money(858),
              vatRate: VatRate.standard,
              quantity: 0.2,
            ))
          .close(paid: const Money(200));

      expect(sold.total, const Money(172));
      expect(sold.totalTax, const Money(31));

      final ReturnReceipt first = (ReturnBuilder(id: 'R1', original: sold)
            ..addLine(0, quantity: 0.1))
          .close();
      final ReturnReceipt second = (ReturnBuilder(
        id: 'R2',
        original: sold,
        previousReturns: <ReturnReceipt>[first],
      )..addLine(0, quantity: 0.1))
          .close();

      // Il denaro torna esatto.
      expect(first.total + second.total, -sold.total);

      // L'imposta no: 86 centesimi scorporati due volte danno 16 + 16, mentre
      // 172 scorporati una volta danno 31. Non è un errore di calcolo ma
      // l'aritmetica di due arrotondamenti indipendenti — ogni documento di
      // reso è un documento fiscale a sé e scorpora sui propri importi. Questo
      // test esiste per fissare il comportamento, non per approvarlo: se un
      // giorno cambia, deve cambiare per una decisione e non per caso.
      expect(first.totalTax, const Money(-16));
      expect(second.totalTax, const Money(-16));
      expect(first.totalTax + second.totalTax, const Money(-32));
      expect(first.totalTax + second.totalTax, isNot(-sold.totalTax));
    });
  });
}
