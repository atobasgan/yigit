import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/app.dart';

void main() {
  testWidgets('bas-konuş tuşu dokunduğun anda tepki verir', (tester) async {
    await tester.pumpWidget(const TelsizUygulamasi());
    expect(find.text('BAS KONUŞ'), findsOneWidget);

    // Parmağı tuşa koy: uzun basma beklemeden hemen "KONUŞ" olmalı.
    final parmak = await tester.startGesture(tester.getCenter(find.text('BAS KONUŞ')));
    await tester.pump();
    expect(find.text('KONUŞ'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await parmak.up();
    await tester.pump();
    expect(find.text('BAS KONUŞ'), findsOneWidget);
    expect(find.textContaining('Konuşma 1:'), findsOneWidget);
  });

  testWidgets('ACİL DUR tuşu görünür ve çalışır', (tester) async {
    await tester.pumpWidget(const TelsizUygulamasi());
    await tester.tap(find.text('ACİL DUR'));
    await tester.pump();
    expect(find.textContaining('Faz 6'), findsOneWidget);
  });
}
