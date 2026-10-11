/// Human-readable file size, e.g. "12.4 MB".
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Short date for meta lines, e.g. "11 Oct 2026".
String formatShortDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// "12 / 48" style page indicator.
String formatPageIndicator(int current, int total) => '$current / $total';

/// Reading progress 0..1 as a whole percent string, e.g. "42%".
String formatPercent(double progress) =>
    '${(progress.clamp(0.0, 1.0) * 100).round()}%';

/// Signed date for the signature "Signed `date`" text.
String formatSignedDate(DateTime date) => formatShortDate(date);
