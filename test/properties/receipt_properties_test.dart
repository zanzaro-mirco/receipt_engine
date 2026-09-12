import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

import 'property.dart';
import 'receipt_gen.dart';

/// Proprietà del motore di calcolo, verificate su scontrini generati.
///
/// Un test a esempi dimostra che il codice funziona sui casi a cui chi lo ha
/// scritto ha pensato. Questi dicono qualcosa di diverso: che un'invariante
/// vale su centinaia di scontrini che nessuno ha scelto — e sono le quantità
/// frazionarie e gli sconti che non dividono tondi a rompere le cose, cioè
/// esattamente i valori che a mano non si scrivono.
void main() {
  group('Proprietà · lo scontrino quadra', () {
    test('imponibile più imposta fa esattamente il lordo, su ogni aliquota',
        () {
      forAll(receiptGen, (ReceiptSpec spec) {
        final Receipt receipt = spec.build();
        for (final VatBreakdown row in receipt.vatSummary) {
          expect(
            row.taxable + row.tax,
            row.gross,
            reason: 'Aliquota ${row.rate}: lo scorporo non ricompone il lordo',
          );
        }
      });
    });

    test('il riepilogo IVA somma al totale del documento', () {
      forAll(receiptGen, (ReceiptSpec spec) {
        final Receipt receipt = spec.build();
        expect(
          Money.sum(receipt.vatSummary.map((VatBreakdown v) => v.gross)),
          receipt.total,
          reason: 'Il riepilogo per aliquota non somma al totale',
        );
      });
    });

    test('lo sconto di documento non fa sparire centesimi dalle righe', () {
      forAll(receiptGen, (ReceiptSpec spec) {
        final Receipt receipt = spec.build();
        expect(
          Money.sum(receipt.netLineTotals),
          receipt.total,
          reason: 'I totali di riga al netto non sommano al totale',
        );
      });
    });
  });

  group('Proprietà · il reso storna', () {
    test('rendere tutto è l\'esatto opposto dello scontrino', () {
      forAll(receiptGen, (ReceiptSpec spec) {
        final Receipt receipt = spec.build();
        final ReturnReceipt full = (ReturnBuilder(id: 'R', original: receipt)
              ..addEverything())
            .close();

        expect(full.refund, receipt.total,
            reason: 'Il reso totale non restituisce il totale incassato');

        // E non solo il totale: anche riga per riga del riepilogo, perché è
        // quello che finisce nel registro dei corrispettivi.
        expect(full.vatSummary.length, receipt.vatSummary.length);
        for (int i = 0; i < full.vatSummary.length; i++) {
          expect(full.vatSummary[i].rate, receipt.vatSummary[i].rate);
          expect(-full.vatSummary[i].tax, receipt.vatSummary[i].tax,
              reason:
                  'L\'imposta stornata non è l\'opposto di quella incassata');
          expect(-full.vatSummary[i].taxable, receipt.vatSummary[i].taxable);
        }
      });
    });

    test('spezzare un reso in più tranche non cambia quanto si restituisce',
        () {
      forAll(receiptGen, (ReceiptSpec spec) {
        final Receipt receipt = spec.build();

        // Ogni riga viene resa a pezzi, un documento per tranche, come succede
        // quando il cliente torna tre volte.
        final List<ReturnReceipt> emitted = <ReturnReceipt>[];
        for (int line = 0; line < spec.lines.length; line++) {
          final List<int> parts =
              partitionTenths(spec.lines[line].quantityTenths);
          for (int p = 0; p < parts.length; p++) {
            emitted.add(
              (ReturnBuilder(
                id: 'R$line-$p',
                original: receipt,
                previousReturns: emitted,
              )..addLine(line, quantity: parts[p] / 10))
                  .close(),
            );
          }
        }

        expect(
          Money.sum(emitted.map((ReturnReceipt r) => r.total)),
          -receipt.total,
          reason: 'La somma dei resi parziali non fa il totale dello scontrino',
        );
      });
    });

    test('storna la stessa imposta, a meno di un arrotondamento per documento',
        () {
      forAll(receiptGen, (ReceiptSpec spec) {
        final Receipt receipt = spec.build();

        final List<ReturnReceipt> emitted = <ReturnReceipt>[];
        for (int line = 0; line < spec.lines.length; line++) {
          final List<int> parts =
              partitionTenths(spec.lines[line].quantityTenths);
          for (int p = 0; p < parts.length; p++) {
            emitted.add(
              (ReturnBuilder(
                id: 'R$line-$p',
                original: receipt,
                previousReturns: emitted,
              )..addLine(line, quantity: parts[p] / 10))
                  .close(),
            );
          }
        }

        // Il denaro torna esatto, ed è l'impegno vero: lo verifica la
        // proprietà qui sopra.
        //
        // L'imposta no, e non per un difetto. Ogni documento di reso scorpora
        // l'IVA sui propri importi, come prescrive la norma: due scorpori da
        // 86 centesimi non fanno lo scorporo di 172. Lo scarto però non è
        // libero di crescere — ogni documento sbaglia al massimo mezzo
        // centesimo per aliquota — e resta legato al numero di documenti. Se
        // un giorno lo superasse vorrebbe dire che gli errori si stanno
        // componendo invece di restare indipendenti, e quello sarebbe un
        // difetto vero.
        final int documents = emitted.length;
        final Money reversed =
            Money.sum(emitted.map((ReturnReceipt r) => r.totalTax));
        final int drift = (reversed.cents + receipt.totalTax.cents).abs();

        expect(
          drift,
          lessThanOrEqualTo(documents),
          reason: 'Lo scarto fra imposta stornata e incassata supera il numero '
              'di documenti: non è arrotondamento, è accumulo',
        );
      });
    });
  });

  group('Proprietà · l\'ordine delle righe', () {
    test('non cambia il totale del documento', () {
      forAll(receiptGen, (ReceiptSpec spec) {
        final Receipt asIs = spec.build();
        final Receipt reversed = ReceiptSpec(
          lines: spec.lines.reversed.toList(),
          documentDiscountPercent: spec.documentDiscountPercent,
        ).build();

        expect(reversed.total, asIs.total,
            reason: 'Invertire le righe ha cambiato il totale');
      });
    });
  });
}
