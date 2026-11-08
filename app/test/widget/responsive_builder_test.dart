import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/widget/responsive_builder.dart';

void main() {
  testWidgets('uses the available width to select a responsive layout', (tester) async {
    Future<void> pumpAtWidth(double width) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 200,
              child: ResponsiveBuilder(
                builder: (sizing) => Text(sizing.isMobile ? 'compact' : 'desktop'),
              ),
            ),
          ),
        ),
      ),
    );

    await pumpAtWidth(699);
    expect(find.text('compact'), findsOneWidget);

    await pumpAtWidth(700);
    expect(find.text('desktop'), findsOneWidget);
  });
}
