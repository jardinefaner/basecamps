import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a 1x1 child inside a MediaQuery overriding the logical width
/// and returns the resulting [Breakpoint] as seen by [Breakpoints.of].
Future<Breakpoint> _breakpointAt(
  WidgetTester tester,
  double width,
) async {
  late Breakpoint observed;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            observed = Breakpoints.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return observed;
}

void main() {
  group('Breakpoints.of', () {
    testWidgets('599dp → compact (just below medium boundary)',
        (tester) async {
      expect(await _breakpointAt(tester, 599), Breakpoint.compact);
    });

    testWidgets('600dp → medium (medium boundary)', (tester) async {
      expect(await _breakpointAt(tester, 600), Breakpoint.medium);
    });

    testWidgets('839dp → medium (just below expanded boundary)',
        (tester) async {
      expect(await _breakpointAt(tester, 839), Breakpoint.medium);
    });

    testWidgets('840dp → expanded (expanded boundary)', (tester) async {
      expect(await _breakpointAt(tester, 840), Breakpoint.expanded);
    });

    testWidgets('1199dp → expanded (just below large boundary)',
        (tester) async {
      expect(await _breakpointAt(tester, 1199), Breakpoint.expanded);
    });

    testWidgets('1200dp → large (large boundary)', (tester) async {
      expect(await _breakpointAt(tester, 1200), Breakpoint.large);
    });
  });
}
