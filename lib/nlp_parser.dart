import 'package:chrono_dart/chrono_dart.dart' show Chrono;

class ParsedReminder {
  final String title;
  final String action;
  final ReminderCategory category;
  final DateTime scheduledTime;
  final double confidence;

  ParsedReminder({
    required this.title,
    required this.action,
    required this.category,
    required this.scheduledTime,
    required this.confidence,
  });
}

enum ReminderCategory {
  none,
  call,
  email,
  meeting,
  medicine,
  work,
  personal,
  travel,
  health,
  finance,
  social,
}

class NLPParser {
  static ParsedReminder parseNaturalLanguage(String text) {
    final lowerText = text.toLowerCase();
    print('Parsing text: "$text"');

    // Try chrono_dart first for comprehensive date parsing
    DateTime? scheduledTime;
    double confidence = 0.3;

    try {
      final results = Chrono.parse(text);
      if (results.isNotEmpty) {
        final parsedDate = results.first.date();
        final now = DateTime.now();
        print('Chrono parsed date: $parsedDate');

        // If the parsed date is in the past, assume it means next occurrence
        DateTime targetDate = parsedDate;
        if (parsedDate.isBefore(now)) {
          // For times without dates, assume next day
          if (parsedDate
                  .difference(DateTime(
                      parsedDate.year, parsedDate.month, parsedDate.day))
                  .inDays ==
              0) {
            targetDate = parsedDate.add(const Duration(days: 1));
          } else {
            // For other past dates, find next appropriate occurrence
            targetDate = _getNextOccurrence(parsedDate);
          }
        }

        scheduledTime = targetDate;
        confidence = 0.9;
        print('Final scheduled time: $scheduledTime');
      }
    } catch (e) {
      print('Chrono parsing failed: $e');
      // Fallback to manual parsing if chrono_dart fails
    }

    // Fallback patterns for common expressions
    if (scheduledTime == null) {
      Duration? fallbackDuration = _parseFallbackPatterns(lowerText);
      if (fallbackDuration != null) {
        scheduledTime = DateTime.now().add(fallbackDuration);
        confidence = 0.7;
        print(
            'Fallback duration: $fallbackDuration, scheduled time: $scheduledTime');
      }
    }

    // Default fallback
    if (scheduledTime == null) {
      scheduledTime = DateTime.now().add(const Duration(minutes: 30));
      confidence = 0.3;
      print('Default fallback time: $scheduledTime');
    }

    // Extract action/title using enhanced patterns (after time parsing)
    final title = _extractReminderTitle(text);
    final action = _extractAction(text);
    final category = detectCategory(text);

    print(
        'Parsed: title="$title", action="$action", time=$scheduledTime, confidence=$confidence');

    return ParsedReminder(
      title: title,
      action: action,
      category: category,
      scheduledTime: scheduledTime,
      confidence: confidence,
    );
  }

  static Duration? _parseFallbackPatterns(String lowerText) {
    // Enhanced time parsing with more patterns

    // Parse "in X minutes/hours/days/weeks/months"
    final inMatch = RegExp(r'in (\d+) (minute|hour|day|week|month)s?')
        .firstMatch(lowerText);
    if (inMatch != null) {
      final number = int.parse(inMatch.group(1)!);
      final unit = inMatch.group(2)!;
      if (unit.startsWith('minute')) return Duration(minutes: number);
      if (unit.startsWith('hour')) return Duration(hours: number);
      if (unit.startsWith('day')) return Duration(days: number);
      if (unit.startsWith('week')) return Duration(days: number * 7);
      if (unit.startsWith('month')) return Duration(days: number * 30);
    }

    // Parse "on [day] at [time]" pattern
    final onDayAtTimeMatch = RegExp(
            r'on (monday|tuesday|wednesday|thursday|friday|saturday|sunday) at (morning|afternoon|evening|night|noon|midnight|\d{1,2}(am|pm)?)')
        .firstMatch(lowerText);
    if (onDayAtTimeMatch != null) {
      final dayName = onDayAtTimeMatch.group(1)!;
      final timeStr = onDayAtTimeMatch.group(2)!;

      final now = DateTime.now();
      final targetDay = _getDayOfWeek(dayName);
      int daysUntil = (targetDay - now.weekday + 7) % 7;
      if (daysUntil == 0) daysUntil = 7; // If today, use next week

      Duration baseDuration = Duration(days: daysUntil);

      // Add time-specific duration
      if (timeStr.contains('morning')) {
        baseDuration += Duration(hours: 9 - now.hour);
      } else if (timeStr.contains('afternoon')) {
        baseDuration += Duration(hours: 14 - now.hour);
      } else if (timeStr.contains('evening') || timeStr.contains('night')) {
        baseDuration += Duration(hours: 19 - now.hour);
      } else if (timeStr.contains('noon')) {
        baseDuration += Duration(hours: 12 - now.hour);
      } else if (timeStr.contains('midnight')) {
        baseDuration += Duration(hours: 24 - now.hour);
      } else if (RegExp(r'\d{1,2}(am|pm)?').hasMatch(timeStr)) {
        final timeMatch = RegExp(r'(\d{1,2})(am|pm)?').firstMatch(timeStr)!;
        final hour = int.parse(timeMatch.group(1)!);
        final period = timeMatch.group(2);
        int targetHour = hour;
        if (period == 'pm' && hour < 12) targetHour += 12;
        if (period == 'am' && hour == 12) targetHour = 0;
        baseDuration += Duration(hours: targetHour - now.hour);
      }

      return baseDuration;
    }

    // Parse "on [day] in the [time_of_day]" pattern
    final onDayInTimeMatch = RegExp(
            r'on (monday|tuesday|wednesday|thursday|friday|saturday|sunday) in the (morning|afternoon|evening|night)')
        .firstMatch(lowerText);
    if (onDayInTimeMatch != null) {
      final dayName = onDayInTimeMatch.group(1)!;
      final timeStr = onDayInTimeMatch.group(2)!;

      final now = DateTime.now();
      final targetDay = _getDayOfWeek(dayName);
      int daysUntil = (targetDay - now.weekday + 7) % 7;
      if (daysUntil == 0) daysUntil = 7; // If today, use next week

      Duration baseDuration = Duration(days: daysUntil);

      // Add time-specific duration
      if (timeStr.contains('morning')) {
        baseDuration += Duration(hours: 9 - now.hour);
      } else if (timeStr.contains('afternoon')) {
        baseDuration += Duration(hours: 14 - now.hour);
      } else if (timeStr.contains('evening') || timeStr.contains('night')) {
        baseDuration += Duration(hours: 19 - now.hour);
      }

      return baseDuration;
    }

    // Parse "X minutes/hours/days/weeks/months from now/later"
    final fromNowMatch =
        RegExp(r'(\d+) (minute|hour|day|week|month)s? (from now|later)')
            .firstMatch(lowerText);
    if (fromNowMatch != null) {
      final number = int.parse(fromNowMatch.group(1)!);
      final unit = fromNowMatch.group(2)!;
      if (unit.startsWith('minute')) return Duration(minutes: number);
      if (unit.startsWith('hour')) return Duration(hours: number);
      if (unit.startsWith('day')) return Duration(days: number);
      if (unit.startsWith('week')) return Duration(days: number * 7);
      if (unit.startsWith('month')) return Duration(days: number * 30);
    }

    // Parse specific times of day with better handling
    if (lowerText.contains('tomorrow')) return const Duration(days: 1);
    if (lowerText.contains('tonight') || lowerText.contains('evening')) {
      return _getTonightDuration();
    }
    if (lowerText.contains('night')) {
      final now = DateTime.now();
      final night = DateTime(now.year, now.month, now.day, 22, 0);
      return now.isBefore(night)
          ? night.difference(now)
          : const Duration(hours: 24) + night.difference(now);
    }
    if (lowerText.contains('morning')) {
      final now = DateTime.now();
      final morning = DateTime(now.year, now.month, now.day, 9, 0);
      return now.isBefore(morning)
          ? morning.difference(now)
          : const Duration(hours: 24) + morning.difference(now);
    }
    if (lowerText.contains('afternoon')) {
      final now = DateTime.now();
      final afternoon = DateTime(now.year, now.month, now.day, 14, 0);
      return now.isBefore(afternoon)
          ? afternoon.difference(now)
          : const Duration(hours: 24) + afternoon.difference(now);
    }
    if (lowerText.contains('noon')) {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12, 0);
      return now.isBefore(noon)
          ? noon.difference(now)
          : const Duration(hours: 24) + noon.difference(now);
    }
    if (lowerText.contains('midnight')) {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day + 1, 0, 0);
      return midnight.difference(now);
    }

    // Parse relative time expressions
    if (lowerText.contains('soon')) return const Duration(minutes: 15);
    if (lowerText.contains('asap') || lowerText.contains('urgently'))
      return const Duration(minutes: 5);
    if (lowerText.contains('quickly')) return const Duration(minutes: 10);
    if (lowerText.contains('later')) return const Duration(hours: 2);
    if (lowerText.contains('eventually')) return const Duration(days: 1);

    // Parse "next/this + day of week"
    final dayOfWeekMatch = RegExp(
            r'(next|this) (monday|tuesday|wednesday|thursday|friday|saturday|sunday)')
        .firstMatch(lowerText);
    if (dayOfWeekMatch != null) {
      final now = DateTime.now();
      final targetDay = _getDayOfWeek(dayOfWeekMatch.group(2)!);
      final isNext = dayOfWeekMatch.group(1) == 'next';

      int daysUntil = (targetDay - now.weekday + 7) % 7;
      if (daysUntil == 0) daysUntil = 7; // If today, use next week
      if (isNext) daysUntil += 7; // Add another week for "next"

      return Duration(days: daysUntil);
    }

    return null;
  }

  static DateTime _getNextOccurrence(DateTime pastDate) {
    final now = DateTime.now();
    DateTime nextDate = pastDate;

    // Keep adding the time difference until we get a future date
    while (nextDate.isBefore(now)) {
      nextDate =
          nextDate.add(Duration(days: 7)); // Add a week for same day next week
    }

    return nextDate;
  }

  static Duration _getTonightDuration() {
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20, 0);
    if (now.isAfter(tonight)) {
      return const Duration(hours: 24) + tonight.difference(now);
    }
    return tonight.difference(now);
  }

  static int _getDayOfWeek(String dayName) {
    switch (dayName.toLowerCase()) {
      case 'monday':
        return DateTime.monday;
      case 'tuesday':
        return DateTime.tuesday;
      case 'wednesday':
        return DateTime.wednesday;
      case 'thursday':
        return DateTime.thursday;
      case 'friday':
        return DateTime.friday;
      case 'saturday':
        return DateTime.saturday;
      case 'sunday':
        return DateTime.sunday;
      default:
        return DateTime.monday;
    }
  }

  static String _extractReminderTitle(String text) {
    // Remove reminder trigger phrases and time-related phrases
    final patterns = [
      // Enhanced reminder trigger phrases
      RegExp(
          r'\b(remind me to|remind me about|remind me|need to|don'
          't forget to|remember to|wake me up|get me to|make sure i|alert me to|notify me to)\b',
          caseSensitive: false),
      // Time-related phrases
      RegExp(r'\b(in \d+ (minutes?|hours?|days?|weeks?|months?))\b',
          caseSensitive: false),
      RegExp(r'\b(\d+ (minutes?|hours?|days?|weeks?|months?) from now)\b',
          caseSensitive: false),
      RegExp(r'\b(\d+ (minutes?|hours?|days?|weeks?|months?) later)\b',
          caseSensitive: false),
      RegExp(r'\b(at \d{1,2}(:\d{2})?(am|pm)?)\b', caseSensitive: false),
      RegExp(
          r'\b(tomorrow|today|tonight|morning|afternoon|evening|night|noon|midnight)\b',
          caseSensitive: false),
      RegExp(
          r'\b(next (week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday|year))\b',
          caseSensitive: false),
      RegExp(
          r'\b(this (week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday|evening|morning|afternoon))\b',
          caseSensitive: false),
      RegExp(
          r'\b(yesterday|last (week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b',
          caseSensitive: false),
      // Relative time phrases
      RegExp(r'\b(soon|later|asap|urgently|quickly|eventually)\b',
          caseSensitive: false),
    ];

    String title = text;
    for (final pattern in patterns) {
      title = title.replaceAll(pattern, '').trim();
    }

    // Clean up extra spaces, articles, and common filler words
    final fillerWords = [
      r'\b(a|an|the|that|this|those|these)\b',
      r'\b(please|can you|could you|would you)\b',
      r'\b(hey|hi|hello|ok|okay)\b',
      r'\b(just|also|too|very|really|quite)\b',
      r'\b(remind me to|reminder|remember|make sure i)\b',
      r'\b(remind me to|remind me about|remind me|i need to|don'
          't forget to|remember to|wake me up|get me to|make sure i|alert me to|notify me to)\b'
    ];

    for (final filler in fillerWords) {
      title = title.replaceAll(RegExp(filler, caseSensitive: false), '').trim();
    }

    // Remove leading action words to prevent duplication, but be more careful
    // Only remove if it's clearly an action word at the start followed by more content
    final actionWords = [
      r'^(call|phone|ring|dial|contact|reach)\s+(\w+.*)',
      r'^(email|mail|send.*mail|write.*email|message)\s+(\w+.*)',
      r'^(meet|meeting|appointment|discuss|conference|interview)\s+(\w+.*)',
      r'^(take|medicine|pill|med|medication|dose|prescription)\s+(\w+.*)',
      r'^(buy|purchase|get|shop|order|acquire|pick up)\s+(\w+.*)',
      r'^(pay|payment|bill|invoice|settle|charge)\s+(\w+.*)',
      r'^(workout|exercise|gym|run|jog|train|fitness|sport)\s+(\w+.*)',
      r'^(study|learn|read|review|research|practice|homework)\s+(\w+.*)',
      r'^(clean|tidy|organize|declutter|wash|vacuum)\s+(\w+.*)',
      r'^(prepare|make.*food|bake|grill|meal)\s+(\w+.*)', // Removed 'cook' from this pattern
      r'^(sing|song|music|dance|play|perform)\s+(\w+.*)', // Fixed 'dance' pattern
      r'^(travel|trip|drive|fly|go.*to|visit|commute)\s+(\w+.*)',
      r'^(work|office|task|project|deadline|job)\s+(\w+.*)',
      r'^(personal|home|family|relax|rest|sleep)\s+(\w+.*)',
    ];

    for (final action in actionWords) {
      final match = RegExp(action, caseSensitive: false).firstMatch(title);
      if (match != null) {
        // Only remove action word if there's substantial content after it
        final remainingContent = match.group(2)!;
        if (remainingContent.trim().isNotEmpty) {
          title = remainingContent.trim();
          print('Action word removed: "${match.group(1)}" -> title: "$title"');
          break; // Only remove first matching action word
        }
      }
    }

    // Clean up extra spaces and punctuation
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    title = title.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '').trim();
    title = title.replaceAll(RegExp(r'[,\.;:!?]+'), '').trim();

    // Handle special cases
    if (title.isEmpty) {
      return 'Reminder';
    }

    // Capitalize first letter and ensure proper formatting
    title = title[0].toUpperCase() + title.substring(1).toLowerCase();

    // Fix common capitalization issues (proper nouns, etc.)
    title = _fixCapitalization(title);

    return title;
  }

  static String _fixCapitalization(String text) {
    // Fix capitalization for common words that should stay capitalized
    final properWords = {
      'monday': 'Monday',
      'tuesday': 'Tuesday',
      'wednesday': 'Wednesday',
      'thursday': 'Thursday',
      'friday': 'Friday',
      'saturday': 'Saturday',
      'sunday': 'Sunday',
      'january': 'January',
      'february': 'February',
      'march': 'March',
      'april': 'April',
      'may': 'May',
      'june': 'June',
      'july': 'July',
      'august': 'August',
      'september': 'September',
      'october': 'October',
      'november': 'November',
      'december': 'December',
      'christmas': 'Christmas',
      'new year': 'New Year',
      'valentine': 'Valentine',
    };

    String result = text;
    properWords.forEach((lower, proper) {
      result = result.replaceAll(
          RegExp(r'\b' + lower + r'\b', caseSensitive: false), proper);
    });

    return result;
  }

  static String _extractAction(String text) {
    final lowerText = text.toLowerCase();

    // Enhanced action patterns with more comprehensive matching
    final actionPatterns = {
      'call': r'\b(call|phone|ring|dial|contact|reach)\b',
      'email': r'\b(email|mail|send.*mail|write.*email|message)\b',
      'meeting':
          r'\b(meet|meeting|appointment|discuss|conference|interview|call.*with)\b',
      'medicine': r'\b(take|medicine|pill|med|medication|dose|prescription)\b',
      'buy': r'\b(buy|purchase|get|shop|order|acquire|pick up)\b',
      'pay': r'\b(pay|payment|bill|invoice|settle|charge)\b',
      'exercise': r'\b(workout|exercise|gym|run|jog|train|fitness|sport)\b',
      'study': r'\b(study|learn|read|review|research|practice|homework)\b',
      'clean': r'\b(clean|tidy|organize|declutter|wash|vacuum)\b',
      'cook': r'\b(cook|prepare|make.*food|bake|grill|meal)\b',
      'travel': r'\b(travel|trip|drive|fly|go.*to|visit|commute)\b',
      'work': r'\b(work|office|task|project|deadline|job)\b',
      'personal': r'\b(personal|home|family|relax|rest|sleep)\b',
      'health': r'\b(doctor|dentist|checkup|health|hospital|clinic)\b',
      'finance': r'\b(bank|transfer|deposit|withdraw|budget|save)\b',
      'social': r'\b(friend|party|celebration|birthday|anniversary|date)\b',
    };

    // Check for action patterns with priority scoring
    Map<String, int> actionScores = {};

    for (final entry in actionPatterns.entries) {
      final matches = RegExp(entry.value).allMatches(lowerText);
      if (matches.isNotEmpty) {
        actionScores[entry.key] = matches.length;
      }
    }

    if (actionScores.isEmpty) {
      return 'reminder';
    }

    // Return action with highest score (most matches)
    return actionScores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  static ReminderCategory detectCategory(String text) {
    final lowerText = text.toLowerCase();
    if (lowerText.contains('call')) return ReminderCategory.call;
    if (lowerText.contains('email') || lowerText.contains('mail'))
      return ReminderCategory.email;
    if (lowerText.contains('meeting') || lowerText.contains('appointment'))
      return ReminderCategory.meeting;
    if (lowerText.contains('medicine') ||
        lowerText.contains('pill') ||
        lowerText.contains('med')) return ReminderCategory.medicine;
    if (lowerText.contains('work') || lowerText.contains('office'))
      return ReminderCategory.work;
    if (lowerText.contains('personal') || lowerText.contains('home'))
      return ReminderCategory.personal;
    if (lowerText.contains('travel') ||
        lowerText.contains('trip') ||
        lowerText.contains('visit')) return ReminderCategory.travel;
    if (lowerText.contains('doctor') ||
        lowerText.contains('health') ||
        lowerText.contains('hospital')) return ReminderCategory.health;
    if (lowerText.contains('pay') ||
        lowerText.contains('bank') ||
        lowerText.contains('bill')) return ReminderCategory.finance;
    if (lowerText.contains('friend') ||
        lowerText.contains('party') ||
        lowerText.contains('birthday')) return ReminderCategory.social;
    return ReminderCategory.none;
  }
}
