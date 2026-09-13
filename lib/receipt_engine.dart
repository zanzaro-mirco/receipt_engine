/// Motore di calcolo per scontrini fiscali.
///
/// Logica pura: nessuna dipendenza da Flutter, da un database o da I/O.
/// È questo che rende il pacchetto testabile in millisecondi e riutilizzabile
/// da un'app mobile, da un backend o da un tool a riga di comando.
library;

export 'src/discount_allocator.dart';
export 'src/formatting/money_formatter.dart';
export 'src/models/discount.dart';
export 'src/models/receipt.dart';
export 'src/models/receipt_line.dart';
export 'src/models/return_receipt.dart';
export 'src/models/vat_rate.dart';
export 'src/money.dart';
export 'src/serialization/receipt_json.dart';
export 'src/receipt_builder.dart';
export 'src/return_builder.dart';
export 'src/vat_calculator.dart';
export 'src/vat_summary_calculator.dart';
