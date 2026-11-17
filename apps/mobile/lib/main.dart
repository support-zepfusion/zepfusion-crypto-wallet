import 'package:material_ui/material_ui.dart';

import 'src/app_shell.dart';
import 'src/vault/wallet_controller.dart';

export 'src/app_shell.dart';

void main() {
  runApp(
    const CofinexApp(inactivityTimeout: Duration(seconds: 60), clock: Clock()),
  );
}
