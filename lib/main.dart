import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized().deferFirstFrame();
  runApp(const ReadingAssistantApp(deferStartupFrame: true));
}
