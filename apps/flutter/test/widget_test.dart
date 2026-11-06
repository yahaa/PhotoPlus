import 'package:flutter_test/flutter_test.dart';
import 'package:photoplus/main.dart';

void main() {
  testWidgets('blank home smoke', (tester) async {
    await tester.pumpWidget(const PhotoPlusApp());
    expect(find.text('PhotoPlus'), findsWidgets);
  });
}
