import 'package:flutter_test/flutter_test.dart';
import 'package:agro_pass/main.dart'; // Vérifiez que le nom correspond à votre projet

void main() {
  testWidgets('Diagnostic test smoke test', (WidgetTester tester) async {
    // On construit notre application de test.
    // Note : Le test échouera probablement car Firebase ne peut pas s'initialiser 
    // dans un environnement de test unitaire sans "mocking", mais cela permet 
    // de vérifier que le code compile.
    await tester.pumpWidget(const AgroPassTestApp(
      fbStatus: "Test",
      fsStatus: "Test",
    ));

    // Vérifie que le titre du diagnostic s'affiche.
    expect(find.text('AGRO PASS - Diagnostic'), findsOneWidget);
  });
}