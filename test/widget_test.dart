import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/app/app.dart';

void main() {
  testWidgets('home offers the three main menu choices', (tester) async {
    await tester.pumpWidget(const SheetMusicRookieApp());

    expect(find.text('Sheet Music Rookie'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Treble Clef'), findsOneWidget);
    expect(find.text('Bass Clef'), findsOneWidget);

    await tester.tap(find.text('Treble Clef'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an octave range'), findsOneWidget);
    expect(find.text('8 down'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('8 up'), findsOneWidget);
  });
}
