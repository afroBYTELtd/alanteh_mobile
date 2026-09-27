/// Client-side rules for booking a ride for later.
///
/// They mirror the Control Center (docs/MOBILE_API_RIDES.md, "Scheduled
/// rides"): a pickup 60 minutes to 7 days ahead. The server re-checks and
/// is authoritative; these rules only keep the picker honest.
library;

const scheduledPickupMinimumLead = Duration(minutes: 60);
const scheduledPickupMaximumLead = Duration(days: 7);
const scheduledPickupSlotMinutes = 15;

enum ScheduledPickupProblem { tooSoon, tooFar }

DateTime _floorToSlot(DateTime value) {
  final minute = value.minute - value.minute % scheduledPickupSlotMinutes;
  return DateTime(value.year, value.month, value.day, value.hour, minute);
}

/// The first bookable slot: an hour from [now], rounded up to 15 minutes.
DateTime earliestScheduledPickup(DateTime now) {
  final threshold = now.add(scheduledPickupMinimumLead);
  final floored = _floorToSlot(threshold);
  if (floored == threshold) {
    return floored;
  }
  return floored.add(const Duration(minutes: scheduledPickupSlotMinutes));
}

/// The last bookable slot: seven days from [now], rounded down.
DateTime latestScheduledPickup(DateTime now) {
  return _floorToSlot(now.add(scheduledPickupMaximumLead));
}

/// The bookable 15-minute slots on [day] (local calendar day).
List<DateTime> scheduledPickupSlotsOn(DateTime day, DateTime now) {
  final earliest = earliestScheduledPickup(now);
  final latest = latestScheduledPickup(now);
  final slots = <DateTime>[];
  var slot = DateTime(day.year, day.month, day.day);
  final nextDay = DateTime(day.year, day.month, day.day + 1);
  while (slot.isBefore(nextDay)) {
    if (!slot.isBefore(earliest) && !slot.isAfter(latest)) {
      slots.add(slot);
    }
    slot = DateTime(
      slot.year,
      slot.month,
      slot.day,
      slot.hour,
      slot.minute + scheduledPickupSlotMinutes,
    );
  }
  return slots;
}

ScheduledPickupProblem? checkScheduledPickup(DateTime pickup, DateTime now) {
  if (pickup.isBefore(now.add(scheduledPickupMinimumLead))) {
    return ScheduledPickupProblem.tooSoon;
  }
  if (pickup.isAfter(now.add(scheduledPickupMaximumLead))) {
    return ScheduledPickupProblem.tooFar;
  }
  return null;
}

const _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = <String>[
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

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// "Sat 3 Oct, 09:00" in device local time, as the push notifications say.
String formatScheduledPickup(DateTime pickup) {
  final local = pickup.toLocal();
  return '${_weekdays[local.weekday - 1]} ${local.day} '
      '${_months[local.month - 1]}, '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

/// "09:00" in device local time, for picking a slot within a chosen day.
String formatScheduledPickupClock(DateTime pickup) {
  final local = pickup.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

/// "Sat 3 Oct" in device local time.
String formatScheduledDate(DateTime day) {
  final local = day.toLocal();
  return '${_weekdays[local.weekday - 1]} ${local.day} '
      '${_months[local.month - 1]}';
}
