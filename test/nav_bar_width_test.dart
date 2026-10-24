import 'package:flutter_test/flutter_test.dart';
import 'package:habit_loop/features/shell/app_shell.dart';

void main() {
  group('Floating nav bar width', () {
    test('sizes to its items on a wide screen', () {
      expect(floatingNavBarWidth(800, 4), 84 * 4);
    });

    test('shrinks to fit inside the side margins on a narrow phone', () {
      expect(floatingNavBarWidth(320, 4), 320 - 32);
    });

    test('never goes negative while the window has no width yet', () {
      expect(floatingNavBarWidth(0, 4), 0);
      expect(floatingNavBarWidth(20, 4), 0);
    });
  });
}
