import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_assistant/features/image_import/presentation/widgets/image_preview.dart';

import 'test_doubles.dart';

void main() {
  testWidgets('reports a preview error only once', (tester) async {
    final provider = ControlledImageProvider();
    var errors = 0;
    Widget build() => MaterialApp(
      home: ImagePreview(image: provider, onError: () => errors++),
    );

    await tester.pumpWidget(build());
    provider.fail();
    await tester.pump();
    await tester.pump();
    expect(errors, 1);

    // A rebuild (e.g. layout change) calls errorBuilder again.
    tester.view.physicalSize = const Size(500, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(build());
    await tester.pump();
    expect(errors, 1);
  });

  testWidgets('ignores the error callback after the preview is removed', (
    tester,
  ) async {
    final provider = ControlledImageProvider();
    var errors = 0;
    var showPreview = true;
    late StateSetter setHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHost = setState;
            return showPreview
                ? ImagePreview(image: provider, onError: () => errors++)
                : const SizedBox();
          },
        ),
      ),
    );

    // Runs before the preview's own post-frame callback, removing the preview
    // in the same frame in which its error was scheduled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setHost(() => showPreview = false);
      tester.binding.drawFrame();
    });
    provider.fail();
    await tester.pump();
    await tester.pump();

    expect(find.byType(ImagePreview), findsNothing);
    expect(errors, 0);
    expect(tester.takeException(), isNull);
  });
}
