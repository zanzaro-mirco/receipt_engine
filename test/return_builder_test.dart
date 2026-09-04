import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

final DateTime quando = DateTime(2026, 9, 4, 11, 15);

/// Scontrino di riferimento: tre righe, due aliquote, uno sconto di riga e uno
/// di documento.
///
/// Lo sconto di documento non è decorazione: è la condizione in cui un reso
/// fatto male si vede. Senza, il totale di riga e l'incassato coincidono e
/// qualunque implementazione sembra corretta.
Receipt scontrino() => ReceiptBuilder(id: 'T-0001', issuedAt: quando)
    .addLine(
      description: 'Maglietta',
      unitPrice: Money.fromEuro(20),
      vatRate: VatRate.ordinaria,
    )
    .addLine(
      description: 'Pane',
      unitPrice: Money.fromEuro(2),
      vatRate: VatRate.superRidotta,
      quantity: 3,
    )
    .addLine(
      description: 'Vino',
      unitPrice: Money.fromEuro(12.20),
      vatRate: VatRate.ordinaria,
      discount: Discount.percent(10),
    )
    .applyDocumentDiscount(Discount.percent(10))
    .close(paid: Money.fromEuro(50));

ReturnBuilder reso(
  Receipt originale, {
  List<ReturnReceipt> precedenti = const <ReturnReceipt>[],
}) =>
    ReturnBuilder(
      id: 'R-0001',
      original: originale,
      issuedAt: quando,
      previousReturns: precedenti,
    );

void main() {
  group('Il criterio: storno parziale', () {
    test('storna due righe su tre e la somma quadra a zero sulle righe rese',
        () {
      final Receipt r = scontrino();
      final ReturnReceipt storno = reso(r).addLine(0).addLine(2).close();

      // Quello che il cliente aveva pagato per le due righe rese: il totale di
      // riga dopo la ripartizione dello sconto di documento, non prima.
      final Money incassatoSulleRigheRese =
          Money.sum(<Money>[r.netLineTotals[0], r.netLineTotals[2]]);

      expect(incassatoSulleRigheRese + storno.total, const Money.zero(),
          reason: 'scontrino e reso non si annullano sulle righe rese');

      expect(storno.originalReceiptId, 'T-0001');
      expect(storno.lines.map((ReturnLine l) => l.lineIndex), <int>[0, 2]);
      expect(storno.lines.map((ReturnLine l) => l.description),
          <String>['Maglietta', 'Vino']);
      expect(storno.total.isNegative, isTrue, reason: 'un reso è negativo');
      expect(storno.refund, -storno.total);
    });

    test('la riga non resa resta interamente a carico del cliente', () {
      final Receipt r = scontrino();
      final ReturnReceipt storno = reso(r).addLine(0).addLine(2).close();

      expect(r.total + storno.total, r.netLineTotals[1],
          reason: 'dopo il reso deve restare esattamente il pane');
    });

    test('il reso non restituisce lo sconto di documento', () {
      // La riga vale 20,00 sullo scontrino, ma con il 10% di sconto di
      // documento il cliente ne ha pagati meno. Rimborsare il totale di riga
      // significherebbe restituirgli anche lo sconto.
      final Receipt r = scontrino();
      final ReturnReceipt storno = reso(r).addLine(0).close();

      expect(storno.refund, lessThan(r.lines[0].total));
      expect(storno.refund, r.netLineTotals[0]);
    });
  });

  group('Reso totale', () {
    test('ogni importo dello scontrino torna a zero, riepilogo IVA compreso',
        () {
      final Receipt r = scontrino();
      final ReturnReceipt storno = reso(r).addEverything().close();

      expect(r.total + storno.total, const Money.zero());
      expect(r.totalTaxable + storno.totalTaxable, const Money.zero());
      expect(r.totalTax + storno.totalTax, const Money.zero());

      // Aliquota per aliquota, non solo sul totale: è qui che due ripartizioni
      // diverse dello sconto lascerebbero un centesimo appeso.
      expect(storno.vatSummary.length, r.vatSummary.length);
      for (int i = 0; i < r.vatSummary.length; i++) {
        expect(storno.vatSummary[i].rate, r.vatSummary[i].rate);
        expect(r.vatSummary[i].gross + storno.vatSummary[i].gross,
            const Money.zero());
        expect(r.vatSummary[i].taxable + storno.vatSummary[i].taxable,
            const Money.zero());
        expect(
            r.vatSummary[i].tax + storno.vatSummary[i].tax, const Money.zero());
      }
    });

    test('rende tutte le quantità, non solo tutte le righe', () {
      final Receipt r = scontrino();
      final ReturnReceipt storno = reso(r).addEverything().close();

      expect(storno.itemCount, r.itemCount);
      expect(storno.lineCount, 3);
    });

    test('dopo un reso totale non resta niente da rendere', () {
      final Receipt r = scontrino();
      final ReturnReceipt primo = reso(r).addEverything().close();
      final ReturnBuilder secondo = reso(r, precedenti: <ReturnReceipt>[primo]);

      expect(secondo.isFullyReturned, isTrue);
      expect(secondo.remainingQuantity(1), 0);
      expect(() => secondo.addLine(1), throwsArgumentError);
    });
  });

  group('Non si rende più di quanto venduto', () {
    test('una quantità superiore al venduto viene rifiutata', () {
      expect(
        () => reso(scontrino()).addLine(1, quantity: 4),
        throwsA(isA<ExcessiveReturnError>()),
      );
    });

    test('i resi già emessi contano nel conteggio', () {
      // Senza questo, tre resi parziali da un pezzo permetterebbero di
      // restituire tre volte un articolo venduto una volta sola.
      final Receipt r = scontrino();
      final ReturnReceipt primo = reso(r).addLine(1, quantity: 2).close();
      final ReturnBuilder secondo = reso(r, precedenti: <ReturnReceipt>[primo]);

      expect(secondo.remainingQuantity(1), 1);
      expect(
        () => secondo.addLine(1, quantity: 2),
        throwsA(isA<ExcessiveReturnError>()),
      );
      expect(secondo.addLine(1, quantity: 1).remainingQuantity(1), 0);
    });

    test('due aggiunte sulla stessa riga si sommano e insieme sforano', () {
      final ReturnBuilder b = reso(scontrino())..addLine(1, quantity: 2);
      expect(b.remainingQuantity(1), 1);
      expect(
        () => b.addLine(1, quantity: 2),
        throwsA(isA<ExcessiveReturnError>()),
      );
    });

    test("l'errore dice quale riga e quanto restava", () {
      try {
        reso(scontrino()).addLine(1, quantity: 5);
        fail('doveva sollevare');
      } on ExcessiveReturnError catch (e) {
        expect(e.lineIndex, 1);
        expect(e.requested, 5);
        expect(e.remaining, 3);
      }
    });

    test('un reso di un altro scontrino viene rifiutato', () {
      final Receipt r = scontrino();
      final ReturnReceipt altrove = ReturnBuilder(
        id: 'R-9',
        original: ReceiptBuilder(id: 'T-9999', issuedAt: quando)
            .addLine(
              description: 'Altro',
              unitPrice: Money.fromEuro(1),
              vatRate: VatRate.ordinaria,
            )
            .close(paid: Money.fromEuro(1)),
        issuedAt: quando,
      ).addLine(0).close();

      expect(
        () => reso(r, precedenti: <ReturnReceipt>[altrove]),
        throwsArgumentError,
      );
    });

    test('un indice di riga inesistente viene rifiutato', () {
      expect(() => reso(scontrino()).addLine(3), throwsRangeError);
      expect(() => reso(scontrino()).addLine(-1), throwsRangeError);
    });
  });

  group('Resi parziali e arrotondamento', () {
    test('rendere un pezzo alla volta restituisce quanto un reso unico', () {
      // L'invariante che regge tutto: comunque si spezzi il reso di una riga,
      // la somma dei rimborsi è esattamente quanto quella riga aveva incassato.
      // Con un arrotondamento non cumulativo qui si perderebbero centesimi.
      for (int prezzo = 1; prezzo <= 200; prezzo++) {
        for (int quantita = 1; quantita <= 7; quantita++) {
          final Receipt r = ReceiptBuilder(id: 'T-0002', issuedAt: quando)
              .addLine(
                description: 'A',
                unitPrice: Money(prezzo),
                vatRate: VatRate.ordinaria,
                quantity: quantita,
              )
              .addLine(
                description: 'B',
                unitPrice: const Money(997),
                vatRate: VatRate.ridotta,
              )
              .applyDocumentDiscount(Discount.percent(13))
              .close(paid: Money.fromEuro(100));

          final List<ReturnReceipt> emessi = <ReturnReceipt>[];
          for (int k = 0; k < quantita; k++) {
            emessi.add(
              ReturnBuilder(
                id: 'R-$k',
                original: r,
                issuedAt: quando,
                previousReturns: emessi,
              ).addLine(0, quantity: 1).close(),
            );
          }

          final String caso = 'prezzo $prezzo, quantità $quantita';
          expect(
            Money.sum(emessi.map((ReturnReceipt e) => e.lines.single.amount)),
            -r.netLineTotals[0],
            reason: caso,
          );
          expect(
            emessi.every((ReturnReceipt e) => e.lines.single.amount.cents <= 0),
            isTrue,
            reason: 'nessun reso può restituire un importo positivo: $caso',
          );
        }
      }
    });

    test('una quantità frazionaria si rende come le altre', () {
      // Merce a peso: 1,5 kg venduti, 0,5 resi.
      final Receipt r = ReceiptBuilder(id: 'T-0003', issuedAt: quando)
          .addLine(
            description: 'Prosciutto',
            unitPrice: Money.fromEuro(30),
            vatRate: VatRate.ridotta,
            quantity: 1.5,
          )
          .close(paid: Money.fromEuro(45));

      final ReturnReceipt storno = reso(r).addLine(0, quantity: 0.5).close();

      expect(storno.refund, Money.fromEuro(15));
      expect(storno.lines.single.quantity, 0.5);
    });
  });

  group('Ciclo di vita del documento', () {
    test('non si può chiudere un reso senza righe', () {
      expect(() => reso(scontrino()).close(), throwsStateError);
    });

    test('non si può operare su un reso già chiuso', () {
      final ReturnBuilder b = reso(scontrino())..addLine(0);
      b.close();

      expect(() => b.addLine(1), throwsA(isA<ReceiptClosedError>()));
      expect(() => b.close(), throwsA(isA<ReceiptClosedError>()));
      expect(b.isClosed, isTrue);
    });

    test('le righe del reso chiuso non sono modificabili', () {
      final ReturnReceipt storno = reso(scontrino()).addLine(0).close();
      expect(
        () => storno.lines.add(storno.lines.first),
        throwsUnsupportedError,
      );
    });

    test('il riepilogo IVA del reso è ordinato per aliquota crescente', () {
      final ReturnReceipt storno = reso(scontrino()).addEverything().close();
      expect(
        storno.vatSummary.map((VatBreakdown v) => v.rate.percentage),
        <int>[4, 22],
      );
      expect(storno.vatSummary.every((VatBreakdown v) => v.gross.isNegative),
          isTrue);
    });
  });
}
