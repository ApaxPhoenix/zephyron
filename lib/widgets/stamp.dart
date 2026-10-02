const List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const List<String> months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String clock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

DateTime day(DateTime time) => DateTime(time.year, time.month, time.day);

String brief(DateTime time) {
  final today = day(DateTime.now());
  final gap = today.difference(day(time)).inDays;
  if (gap <= 0) return clock(time);
  if (gap == 1) return 'Yesterday';
  if (gap < 7) return weekdays[time.weekday - 1];
  if (time.year == today.year) return '${time.day} ${months[time.month - 1]}';
  return '${time.day}/${time.month}/${time.year % 100}';
}

String heading(DateTime time) {
  final today = day(DateTime.now());
  final gap = today.difference(day(time)).inDays;
  if (gap <= 0) return 'Today';
  if (gap == 1) return 'Yesterday';
  if (gap < 7) return weekdays[time.weekday - 1];
  final base =
      '${weekdays[time.weekday - 1]}, ${time.day} ${months[time.month - 1]}';
  return time.year == today.year ? base : '$base ${time.year}';
}

String ago(DateTime time) {
  final gap = DateTime.now().difference(time);
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} h ago';
  return brief(time);
}
