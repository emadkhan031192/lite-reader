import 'package:flutter_test/flutter_test.dart';
import 'package:litereader/core/utils/format.dart';

void main() {
  group('formatBytes', () {
    test('zero', () {
      expect(formatBytes(0), '0 B');
    });

    test('bytes under 1 KB', () {
      expect(formatBytes(1023), '1023 B');
    });

    test('kilobytes', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('megabytes', () {
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('gigabytes', () {
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });

  test('formatPercent rounds to a whole percent', () {
    expect(formatPercent(0.425), '43%');
    expect(formatPercent(0), '0%');
    expect(formatPercent(1), '100%');
  });

  test('formatPageIndicator', () {
    expect(formatPageIndicator(12, 48), '12 / 48');
  });

  test('formatShortDate contains the year', () {
    expect(formatShortDate(DateTime(2026, 10, 11)), contains('2026'));
  });
}
