import 'package:material_ui/material_ui.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized().deferFirstFrame();
  runApp(const ReadingAssistantApp(deferStartupFrame: true));
}
