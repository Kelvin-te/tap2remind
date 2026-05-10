import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'nlp_parser.dart';
import 'voice_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Initialize voice service
  await VoiceService.initialize();

  runApp(const Tap2RemindApp());
}

class Tap2RemindApp extends StatelessWidget {
  const Tap2RemindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tap2Remind',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        textTheme: GoogleFonts.urbanistTextTheme().copyWith(
          bodyLarge: GoogleFonts.urbanist(fontWeight: FontWeight.w300),
          bodyMedium: GoogleFonts.urbanist(fontWeight: FontWeight.w300),
          headlineSmall: GoogleFonts.urbanist(fontWeight: FontWeight.w300),
          labelMedium: GoogleFonts.urbanist(fontWeight: FontWeight.w300),
        ),
      ),
      home: const ReminderScreen(),
    );
  }
}

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  final TextEditingController _textController = TextEditingController();
  List<Reminder> _reminders = [];
  List<Reminder> _recentReminders = [];
  List<String> _quickTemplates = ['Call', 'Email', 'Meeting', 'Medicine'];
  bool _isListening = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadReminders();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.notification.request();
  }

  Future<void> _startListening() async {
    if (!(await VoiceService.isAvailable())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }

    setState(() => _isListening = true);

    VoiceService.startListening(
      onResult: (command) {
        _handleVoiceCommand(command);
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speech error: $error')),
        );
        setState(() => _isListening = false);
      },
      onListeningStart: () {
        setState(() => _isListening = true);
      },
      onListeningEnd: () {
        setState(() => _isListening = false);
      },
    );
  }

  Future<void> _stopListening() async {
    VoiceService.stopListening();
    setState(() => _isListening = false);
  }

  Future<void> _handleVoiceCommand(String command) async {
    // Parse the command using NLP
    final parsed = NLPParser.parseNaturalLanguage(command);

    // Save voice reminder automatically
    await VoiceService.saveVoiceReminder(command, parsed);

    // Set the reminder
    _setReminderWithParsedData(parsed);

    // Speak confirmation
    final response = VoiceService.generateConfirmationResponse(parsed);
    await VoiceService.speak(response);

    // Update text field
    _textController.text = command;
  }

  ReminderCategory _detectCategory(String text) {
    return NLPParser.detectCategory(text);
  }

  void _addToRecent(Reminder reminder) {
    setState(() {
      _recentReminders.insert(0, reminder);
      if (_recentReminders.length > 10) {
        _recentReminders = _recentReminders.take(10).toList();
      }
    });
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final reminderStrings = prefs.getStringList('reminders') ?? [];
    final recentStrings = prefs.getStringList('recent_reminders') ?? [];
    setState(() {
      _reminders =
          reminderStrings.map((str) => Reminder.fromString(str)).toList();
      _recentReminders =
          recentStrings.map((str) => Reminder.fromString(str)).toList();
    });
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final reminderStrings = _reminders.map((r) => r.toString()).toList();
    final recentStrings = _recentReminders.map((r) => r.toString()).toList();
    await prefs.setStringList('reminders', reminderStrings);
    await prefs.setStringList('recent_reminders', recentStrings);
  }

  Future<void> _scheduleReminder(String text, Duration delay,
      {RecurrenceType? recurrence}) async {
    final category = _detectCategory(text);
    final reminder = Reminder(
      text: text,
      scheduledTime: DateTime.now().add(delay),
      category: category,
      recurrence: recurrence ?? RecurrenceType.none,
    );

    _addToRecent(reminder);

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'tap2remind_channel',
      'Tap2Remind Notifications',
      channelDescription: 'Reminder notifications from Tap2Remind',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      reminder.id,
      'Reminder',
      text,
      tz.TZDateTime.from(reminder.scheduledTime, tz.local),
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    setState(() {
      _reminders.add(reminder);
    });
    await _saveReminders();

    _textController.clear();
    final recurrenceText =
        recurrence != null && recurrence != RecurrenceType.none
            ? ' (${_formatRecurrence(recurrence!)})'
            : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Reminder set for ${_formatDuration(delay)}$recurrenceText')),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} minutes';
    } else if (duration.inHours < 24) {
      return '${duration.inHours} hours';
    } else {
      return '${duration.inDays} days';
    }
  }

  String _formatRecurrence(RecurrenceType recurrence) {
    switch (recurrence) {
      case RecurrenceType.daily:
        return 'Daily';
      case RecurrenceType.weekly:
        return 'Weekly';
      case RecurrenceType.monthly:
        return 'Monthly';
      case RecurrenceType.none:
        return '';
    }
  }

  Color _getCategoryColor(ReminderCategory category) {
    switch (category) {
      case ReminderCategory.call:
        return Colors.green;
      case ReminderCategory.email:
        return Colors.blue;
      case ReminderCategory.meeting:
        return Colors.purple;
      case ReminderCategory.medicine:
        return Colors.red;
      case ReminderCategory.work:
        return Colors.orange;
      case ReminderCategory.personal:
        return Colors.pink;
      case ReminderCategory.travel:
        return Colors.teal;
      case ReminderCategory.health:
        return Colors.red.shade300;
      case ReminderCategory.finance:
        return Colors.amber;
      case ReminderCategory.social:
        return Colors.purple.shade300;
      case ReminderCategory.none:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'What should I remind you?',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.black87,
                              ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _showAdvanced = !_showAdvanced),
                    icon: Icon(
                        _showAdvanced ? Icons.expand_less : Icons.expand_more),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText:
                            'Type or speak your reminder... (Say "${VoiceService.triggerPhrase}")',
                        hintStyle:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade500,
                                ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening ? Colors.red : Colors.grey,
                          ),
                          onPressed:
                              _isListening ? _stopListening : _startListening,
                        ),
                      ),
                      autofocus: true,
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          final parsed = NLPParser.parseNaturalLanguage(value);
                          _setReminderWithParsedData(parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (_showAdvanced) ...[
                const SizedBox(height: 15),
                // Quick Templates
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickTemplates.length,
                    itemBuilder: (context, index) {
                      final template = _quickTemplates[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(template),
                          onSelected: (_) => _setTemplateReminder(template),
                          backgroundColor: Colors.grey.shade200,
                        ),
                      );
                    },
                  ),
                ),

                // Recent Reminders
                if (_recentReminders.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recentReminders.take(5).length,
                      itemBuilder: (context, index) {
                        final reminder = _recentReminders[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor:
                                  _getCategoryColor(reminder.category),
                              radius: 8,
                            ),
                            label: Text(
                              reminder.text.length > 15
                                  ? '${reminder.text.substring(0, 15)}...'
                                  : reminder.text,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () => _setRecentReminder(reminder),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _QuickTimeButton(
                    icon: '10 min',
                    duration: const Duration(minutes: 10),
                    onTap: () => _setReminder(const Duration(minutes: 10)),
                  ),
                  _QuickTimeButton(
                    icon: '1 hr',
                    duration: const Duration(hours: 1),
                    onTap: () => _setReminder(const Duration(hours: 1)),
                  ),
                  _QuickTimeButton(
                    icon: 'Tonight',
                    duration: _getTonightDuration(),
                    onTap: () => _setReminder(_getTonightDuration()),
                  ),
                  _QuickTimeButton(
                    icon: 'Tomorrow',
                    duration: const Duration(days: 1),
                    onTap: () => _setReminder(const Duration(days: 1)),
                  ),
                  _QuickTimeButton(
                    icon: 'Advanced',
                    duration: const Duration(minutes: 30),
                    onTap: () => _showAdvancedOptions(_textController.text),
                    isSpecial: true,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Expanded(
                child: _reminders.isEmpty
                    ? Center(
                        child: Text(
                          'No reminders set',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey,
                                  ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _reminders.length,
                        itemBuilder: (context, index) {
                          final reminder = _reminders[index];
                          return ReminderCard(
                            reminder: reminder,
                            onDelete: () => _deleteReminder(index),
                            onComplete: () => _completeReminder(index),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Duration _getTonightDuration() {
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20, 0);
    if (now.isAfter(tonight)) {
      return const Duration(hours: 24);
    }
    return tonight.difference(now);
  }

  void _setReminder(Duration duration, {RecurrenceType? recurrence}) {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _scheduleReminder(text, duration, recurrence: recurrence);
    }
  }

  void _setReminderWithParsedData(ParsedReminder parsed,
      {RecurrenceType? recurrence}) {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      // Use the parsed title if it's better than the raw text
      final reminderText = parsed.confidence > 0.7 ? parsed.title : text;
      final delay = parsed.scheduledTime.difference(DateTime.now());
      _scheduleReminder(
          reminderText, delay.isNegative ? const Duration(minutes: 30) : delay,
          recurrence: recurrence);
    }
  }

  void _setTemplateReminder(String template) {
    _textController.text = template;
    _setReminder(const Duration(minutes: 30));
  }

  void _setRecentReminder(Reminder reminder) {
    _textController.text = reminder.text;
    final delay = reminder.scheduledTime.difference(DateTime.now());
    if (delay.isNegative) {
      _setReminder(const Duration(minutes: 30),
          recurrence: reminder.recurrence);
    } else {
      _setReminder(delay, recurrence: reminder.recurrence);
    }
  }

  void _completeReminder(int index) {
    final reminder = _reminders[index];
    if (reminder.recurrence != RecurrenceType.none) {
      // Schedule next occurrence
      final nextTime =
          _getNextOccurrence(reminder.scheduledTime, reminder.recurrence);
      final nextReminder = reminder.copyWith(scheduledTime: nextTime);
      setState(() {
        _reminders[index] = nextReminder;
      });
      _saveReminders();
    } else {
      // Remove completed reminder
      setState(() {
        _reminders.removeAt(index);
      });
      _saveReminders();
    }
  }

  DateTime _getNextOccurrence(DateTime current, RecurrenceType recurrence) {
    switch (recurrence) {
      case RecurrenceType.daily:
        return current.add(const Duration(days: 1));
      case RecurrenceType.weekly:
        return current.add(const Duration(days: 7));
      case RecurrenceType.monthly:
        return DateTime(current.year, current.month + 1, current.day,
            current.hour, current.minute);
      case RecurrenceType.none:
        return current;
    }
  }

  void _showAdvancedOptions(String text) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Advanced options for: "$text"'),
              subtitle: Text('Category: ${_detectCategory(text).name}'),
            ),
            const Divider(),
            ListTile(
              title: const Text('Time'),
              subtitle: Text(() {
                final parsed = NLPParser.parseNaturalLanguage(text);
                final duration =
                    parsed.scheduledTime.difference(DateTime.now());
                return duration.inMinutes < 60
                    ? 'In ${duration.inMinutes} minutes'
                    : 'Smart time detected';
              }()),
              trailing: const Icon(Icons.access_time),
            ),
            ListTile(
              title: const Text('Recurrence'),
              subtitle: const Text('Set repeating reminder'),
              trailing: DropdownButton<RecurrenceType>(
                value: null,
                items: RecurrenceType.values
                    .where((type) => type != RecurrenceType.none)
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(_formatRecurrence(type)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    Navigator.pop(context);
                    final parsed = NLPParser.parseNaturalLanguage(text);
                    _setReminderWithParsedData(parsed, recurrence: value);
                  }
                },
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text('Quick times'),
              subtitle: const Text('Or choose from preset times'),
            ),
            ...[15, 30, 60, 120, 240].map((minutes) => ListTile(
                  title: Text(
                      'In $minutes ${minutes == 1 ? 'minute' : 'minutes'}'),
                  onTap: () {
                    Navigator.pop(context);
                    _setReminder(Duration(minutes: minutes));
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReminder(int index) async {
    setState(() {
      _reminders.removeAt(index);
    });
    await _saveReminders();
  }
}

class _QuickTimeButton extends StatelessWidget {
  final String icon;
  final Duration duration;
  final VoidCallback onTap;
  final bool isSpecial;

  const _QuickTimeButton({
    required this.icon,
    required this.duration,
    required this.onTap,
    this.isSpecial = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSpecial ? Colors.blue : Colors.grey.shade300,
            width: isSpecial ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSpecial ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Text(
          icon,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isSpecial ? Colors.blue : null,
                fontWeight: isSpecial ? FontWeight.w500 : null,
              ),
        ),
      ),
    );
  }
}

class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onDelete;
  final VoidCallback? onComplete;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onDelete,
    this.onComplete,
  });

  Color _getCategoryColor(ReminderCategory category) {
    switch (category) {
      case ReminderCategory.call:
        return Colors.green;
      case ReminderCategory.email:
        return Colors.blue;
      case ReminderCategory.meeting:
        return Colors.purple;
      case ReminderCategory.medicine:
        return Colors.red;
      case ReminderCategory.work:
        return Colors.orange;
      case ReminderCategory.personal:
        return Colors.pink;
      case ReminderCategory.travel:
        return Colors.teal;
      case ReminderCategory.health:
        return Colors.red.shade300;
      case ReminderCategory.finance:
        return Colors.amber;
      case ReminderCategory.social:
        return Colors.purple.shade300;
      case ReminderCategory.none:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(ReminderCategory category) {
    switch (category) {
      case ReminderCategory.call:
        return Icons.phone;
      case ReminderCategory.email:
        return Icons.email;
      case ReminderCategory.meeting:
        return Icons.people;
      case ReminderCategory.medicine:
        return Icons.medication;
      case ReminderCategory.work:
        return Icons.work;
      case ReminderCategory.personal:
        return Icons.home;
      case ReminderCategory.travel:
        return Icons.flight;
      case ReminderCategory.health:
        return Icons.local_hospital;
      case ReminderCategory.finance:
        return Icons.account_balance;
      case ReminderCategory.social:
        return Icons.people;
      case ReminderCategory.none:
        return Icons.notification_important;
    }
  }

  String _formatRecurrence(RecurrenceType recurrence) {
    switch (recurrence) {
      case RecurrenceType.daily:
        return 'Daily';
      case RecurrenceType.weekly:
        return 'Weekly';
      case RecurrenceType.monthly:
        return 'Monthly';
      case RecurrenceType.none:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isActive =
        reminder.scheduledTime.isAfter(now) && !reminder.isCompleted;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: reminder.category != ReminderCategory.none
            ? CircleAvatar(
                backgroundColor:
                    _getCategoryColor(reminder.category).withOpacity(0.2),
                radius: 16,
                child: Icon(
                  _getCategoryIcon(reminder.category),
                  color: _getCategoryColor(reminder.category),
                  size: 16,
                ),
              )
            : null,
        title: Text(
          reminder.text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                decoration: isActive ? null : TextDecoration.lineThrough,
                color: isActive ? Colors.black87 : Colors.grey,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatTime(reminder.scheduledTime),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isActive ? Colors.grey.shade600 : Colors.grey,
                  ),
            ),
            if (reminder.recurrence != RecurrenceType.none)
              Text(
                _formatRecurrence(reminder.recurrence),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              IconButton(
                color: Colors.green,
                icon: const Icon(Icons.check),
                onPressed: () => onComplete?.call(),
              ),
            Container(
              height: 20,
              width: 1,
              color: Colors.grey,
            ),
            IconButton(
              color: Colors.red,
              icon: const Icon(Icons.close),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = time.difference(now);

    if (difference.isNegative) {
      return 'Completed';
    } else if (difference.inMinutes < 60) {
      return 'In ${difference.inMinutes} minutes';
    } else if (difference.inHours < 24) {
      return 'In ${difference.inHours} hours';
    } else {
      return 'Tomorrow at ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

enum RecurrenceType {
  none,
  daily,
  weekly,
  monthly,
}

class Reminder {
  final String text;
  final DateTime scheduledTime;
  final int id;
  final ReminderCategory category;
  final RecurrenceType recurrence;
  final bool isCompleted;

  Reminder({
    required this.text,
    required this.scheduledTime,
    this.category = ReminderCategory.none,
    this.recurrence = RecurrenceType.none,
    this.isCompleted = false,
  }) : id = DateTime.now().millisecondsSinceEpoch % 100000;

  Reminder.fromString(String str)
      : text = str.split('|')[0],
        scheduledTime = DateTime.parse(str.split('|')[1]),
        id = int.parse(str.split('|')[2]),
        category = ReminderCategory.values[int.parse(str.split('|')[3])],
        recurrence = RecurrenceType.values[int.parse(str.split('|')[4])],
        isCompleted = str.split('|')[5] == 'true';

  @override
  String toString() =>
      '$text|${scheduledTime.toIso8601String()}|$id|${category.index}|${recurrence.index}|$isCompleted';

  Reminder copyWith({
    String? text,
    DateTime? scheduledTime,
    ReminderCategory? category,
    RecurrenceType? recurrence,
    bool? isCompleted,
  }) {
    return Reminder(
      text: text ?? this.text,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      category: category ?? this.category,
      recurrence: recurrence ?? this.recurrence,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
