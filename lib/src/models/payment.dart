import '../formatting/money_formatter.dart';
import '../money.dart';

/// Mezzo di pagamento.
///
/// Aperto come `VatRate` e per la stessa ragione: contanti e
/// carta ci sono in ogni cassa, ma il buono spesa di un cliente o il
/// pagamento con app di un altro non devono richiedere una nuova versione del
/// pacchetto.
///
/// L'unica cosa che il motore di calcolo ha bisogno di sapere su un mezzo di
/// pagamento è se **dà resto**. Il resto esce dal cassetto: si può restituire
/// solo quello che è stato versato in un mezzo da cui si può restituire.
class PaymentMethod {
  /// Crea un mezzo di pagamento.
  ///
  /// [code] lo identifica: due mezzi con lo stesso codice sono lo stesso
  /// mezzo, come due aliquote con la stessa percentuale sono la stessa
  /// aliquota.
  const PaymentMethod(this.code, {this.label = '', this.givesChange = false});

  /// Contanti: l'unico mezzo predefinito che dà resto.
  static const PaymentMethod cash =
      PaymentMethod('cash', label: 'Contanti', givesChange: true);

  /// Pagamento elettronico: carta, bancomat, telefono. Addebita l'importo
  /// esatto e non dà resto.
  static const PaymentMethod electronic =
      PaymentMethod('electronic', label: 'Elettronico');

  /// Identificativo stabile, quello che finisce nel JSON.
  final String code;

  /// Descrizione per l'operatore e per lo scontrino. Non entra nel confronto.
  final String label;

  /// Vero se da questo mezzo si può restituire un resto.
  final bool givesChange;

  @override
  bool operator ==(Object other) =>
      other is PaymentMethod && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => label.isEmpty ? code : label;
}

/// Un importo versato con un mezzo di pagamento.
class Payment {
  /// Crea un pagamento. Rifiuta un importo non positivo: un pagamento da zero
  /// non è un pagamento, e uno negativo è un rimborso, che ha il suo documento.
  Payment(this.method, this.amount) {
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError.value(amount, 'amount', 'Deve essere positivo');
    }
  }

  /// Pagamento in contanti.
  factory Payment.cash(Money amount) => Payment(PaymentMethod.cash, amount);

  /// Pagamento elettronico.
  factory Payment.electronic(Money amount) =>
      Payment(PaymentMethod.electronic, amount);

  /// Mezzo con cui è stato versato.
  final PaymentMethod method;

  /// Importo versato. Positivo.
  final Money amount;

  @override
  String toString() => '$method ${const PlainMoneyFormatter().format(amount)}';
}
