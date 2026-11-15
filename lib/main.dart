import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app.dart';
import 'app_services.dart';
import 'features/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  final settings = SettingsController(services.kv);
  await settings.load();
  // Accessible web build (also lets browser tests find buttons by name).
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  runApp(VioraApp(services: services, settings: settings));
}
// comment
// comment 2