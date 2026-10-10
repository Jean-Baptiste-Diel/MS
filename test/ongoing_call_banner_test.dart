import 'package:booking_system_flutter/component/ongoing_call_banner.dart';
import 'package:booking_system_flutter/screens/call/mison_call_screen.dart';
import 'package:booking_system_flutter/services/mison_call_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nb_utils/nb_utils.dart' show navigatorKey;

/// Écran qui se comporte comme l'écran d'appel vis-à-vis de la barre :
/// compté comme visible tant qu'il est affiché.
class _FakeCallScreen extends StatefulWidget {
  const _FakeCallScreen();
  @override
  State<_FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<_FakeCallScreen> {
  @override
  void initState() {
    super.initState();
    MisonCallScreen.visibleCount.value++;
  }

  @override
  void dispose() {
    MisonCallScreen.visibleCount.value--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IconButton(
          key: const Key('reduce'),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      );
}

void main() {
  testWidgets('la barre « Appel en cours » apparaît quand on réduit l\'appel', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('Accueil')),
      builder: (context, child) => OngoingCallBanner(child: child!),
    ));

    MisonCallSession.current.value = MisonCallSession.forTest();
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const _FakeCallScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Revenir'), findsNothing); // écran d'appel affiché : pas de barre

    await tester.tap(find.byKey(const Key('reduce')));
    await tester.pumpAndSettle();

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Revenir'), findsOneWidget); // barre visible après réduction

    // Fin de l'appel : la barre disparaît.
    MisonCallSession.current.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Revenir'), findsNothing);
  });
}
