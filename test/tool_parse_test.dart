import 'package:flutter_test/flutter_test.dart';
import 'package:litereader/features/tools/split_screen.dart' show parseRanges;

/// parseRanges is the pure range parser behind the Split screen's
/// "By range" mode. Invalid input yields an empty list (documented in
/// split_screen.dart), never a partial result.
void main() {
  group('parseRanges', () {
    test('parses comma-separated ranges', () {
      expect(
        parseRanges('1-5, 6-10', 12),
        [
          [1, 5],
          [6, 10],
        ],
      );
    });

    test('single range and whitespace', () {
      expect(parseRanges(' 3-3 ', 12), [
        [3, 3],
      ]);
    });

    test('rejects a zero start', () {
      expect(parseRanges('0-3', 12), isEmpty);
    });

    test('rejects a reversed range', () {
      expect(parseRanges('5-2', 12), isEmpty);
    });

    test('rejects non-numeric input', () {
      expect(parseRanges('abc', 12), isEmpty);
    });

    test('rejects a range past the last page', () {
      expect(parseRanges('1-99', 12), isEmpty);
    });

    test('one bad part invalidates the whole input', () {
      expect(parseRanges('1-5, nope', 12), isEmpty);
    });

    test('empty text', () {
      expect(parseRanges('', 12), isEmpty);
    });
  });
}
