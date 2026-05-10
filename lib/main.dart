import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tap2remind/nlp_parser.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chrono_dart/chrono_dart.dart' show Chrono;
import 'settings_screen.dart';
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

  // Handle notifications when they're received and when user taps them
  flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      print('=== NOTIFICATION TRIGGERED ===');
      print('Notification ID: ${response.id}');
      print('Notification payload: ${response.payload}');
      print('Action type: ${response.actionId}');

      // Handle the notification action
      if (response.payload != null) {
        print('Processing reminder notification');
        // You can add additional logic here like:
        // - Show reminder details dialog
        // - Mark reminder as completed
        // - Navigate to reminder details
        // - Play completion sound
      }
    },
  );

  // Handle app launch from notification
  flutterLocalNotificationsPlugin
      .getNotificationAppLaunchDetails()
      .then((details) {
    if (details != null) {
      print('=== APP LAUNCHED FROM NOTIFICATION ===');
      print('Launch details: ${details.notificationResponse?.payload}');
    }
  });

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
        primarySwatch: Colors.green,
        useMaterial3: true,
        textTheme: GoogleFonts.urbanistTextTheme().copyWith(
          bodyLarge: GoogleFonts.urbanist(fontWeight: FontWeight.w400),
          bodyMedium: GoogleFonts.urbanist(fontWeight: FontWeight.w400),
          headlineSmall: GoogleFonts.urbanist(fontWeight: FontWeight.w500),
          labelMedium: GoogleFonts.urbanist(
            fontWeight: FontWeight.w400,
            fontSize: 13,
          ),
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
  // Speech functionality temporarily disabled
  bool _isListening = false;
  String _lastSpokenText = '';
  bool _showAdvanced = false;
  String _lastProcessedCommand = ''; // Prevent duplicate processing

  // Timer for live countdown updates
  Timer? _countdownTimer;
  Map<int, String> _countdownTexts = {};

  void initState() {
    super.initState();
    _loadReminders();
    _requestPermissions();
    _initializeVoiceService();

    // Add listener to update UI when text changes
    _textController.addListener(() {
      setState(() {});
    });

    // Start countdown timer
    _startCountdownTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _updateCountdownTexts();
      });
    });
  }

  void _updateCountdownTexts() {
    final now = DateTime.now();
    for (int i = 0; i < _reminders.length; i++) {
      final reminder = _reminders[i];
      final duration = reminder.scheduledTime.difference(now);

      if (duration.isNegative) {
        _countdownTexts[reminder.id] = 'Overdue';
      } else if (duration.inSeconds <= 0) {
        // When countdown hits exactly 0 seconds, trigger notification and stop countdown
        _countdownTexts[reminder.id] = 'Now!';
        _triggerImmediateNotification(reminder);
        _countdownTimer?.cancel();
      } else {
        _countdownTexts[reminder.id] = _formatCountdown(duration);
      }
    }
  }

  void _triggerImmediateNotification(Reminder reminder) {
    print('=== TRIGGERING IMMEDIATE NOTIFICATION ===');
    print('Reminder: ${reminder.text}');

    // Trigger notification immediately
    final androidDetails = AndroidNotificationDetails(
      'tap2remind_channel',
      'Tap2Remind Notifications',
      channelDescription: 'Immediate reminder notification',
      importance: Importance.high,
      priority: Priority.high,
    );

    final platformDetails = NotificationDetails(android: androidDetails);

    flutterLocalNotificationsPlugin.show(
      reminder.id,
      'Kumbu Reminder',
      reminder.text,
      platformDetails,
      payload: reminder.text,
    );

    print('Immediate notification sent for ID: ${reminder.id}');
  }

  String _formatCountdown(Duration duration) {
    if (duration.inSeconds <= 0) {
      return 'Now!';
    } else if (duration.inSeconds <= 60) {
      return '${duration.inSeconds} secs';
    } else if (duration.inMinutes < 60) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return '$minutes mins $seconds secs';
    } else if (duration.inHours < 24) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '$hours hrs $minutes mins';
    } else {
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      return '$days days $hours hrs';
    }
  }

  Future<void> _requestPermissions() async {
    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    print('Microphone permission on startup: $micStatus');

    if (micStatus.isPermanentlyDenied) {
      print('Microphone permission permanently denied');
    } else if (micStatus.isDenied) {
      print('Microphone permission denied - will request again when needed');
    } else if (micStatus.isGranted) {
      print('Microphone permission granted');
    }

    // Request notification permission
    final notifStatus = await Permission.notification.request();
    print('Notification permission on startup: $notifStatus');
  }

  Future<void> _initializeVoiceService() async {
    try {
      await VoiceService.initialize();
      print('Voice service initialized successfully');
    } catch (e) {
      print('Voice service initialization error: $e');
    }
  }

  Future<void> _initializeSpeech() async {
    if (!(await VoiceService.isAvailable())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }
  }

  Future<void> _startListening() async {
    print('Starting speech recognition...');

    // Request microphone permission if not granted
    final micStatus = await Permission.microphone.request();
    print('Microphone permission status: $micStatus');

    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Microphone permission required for speech recognition. Please enable it in settings.',
          ),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
      return;
    }

    // Check if voice service is available
    final available = await VoiceService.isAvailable();
    print('Speech recognition available: $available');

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available on this device.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isListening = true);
    print('Voice listening started...');

    VoiceService.startListening(
      onResult: (command) {
        print('Voice result: $command');
        _handleVoiceCommand(command);
      },
      onError: (error) {
        print('Voice error: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Speech error: $error'),
            duration: Duration(seconds: 2),
          ),
        );
        setState(() => _isListening = false);
      },
      onListeningStart: () {
        print('Voice listening started callback');
        setState(() => _isListening = true);
      },
      onListeningEnd: () {
        print('Voice listening ended');
        setState(() => _isListening = false);
      },
    );
  }

  Future<void> _stopListening() async {
    VoiceService.stopListening();
    setState(() => _isListening = false);
  }

  Future<void> _handleVoiceCommand(String command) async {
    print('Handling voice command: $command');

    // Prevent duplicate processing of the same command
    if (_lastProcessedCommand == command) {
      print('Duplicate command detected - skipping');
      return;
    }
    _lastProcessedCommand = command;

    // Always put the recognized text in the input field
    setState(() {
      _textController.text = command;
    });

    // Parse the command using NLP
    final parsed = _parseNaturalLanguage(command);
    print(
        'Parsed reminder: title="${parsed.title}", time="${parsed.scheduledTime}", confidence=${parsed.confidence}');

    // Check if we have all necessary reminder data
    bool hasCompleteData = parsed.title.isNotEmpty &&
        parsed.scheduledTime.isAfter(DateTime.now()) &&
        parsed.confidence > 0.5;

    if (hasCompleteData) {
      print('Complete reminder data detected - auto-creating reminder');

      // Save voice reminder automatically
      await VoiceService.saveVoiceReminder(command, parsed);

      // Set the reminder
      _setReminderWithParsedData(parsed);

      // Speak confirmation
      final response = VoiceService.generateConfirmationResponse(parsed);
      await VoiceService.speak(response);

      // Clear the input field after successful creation
      setState(() {
        _textController.clear();
        _lastProcessedCommand = ''; // Reset for next command
      });
    } else {
      print(
          'Incomplete reminder data - keeping text in input field for manual editing');

      // Speak what was understood
      await VoiceService.speak(
          "I heard: ${parsed.title}. Please set the time manually or try again.");

      // Reset for next command
      setState(() {
        _lastProcessedCommand = '';
      });
    }
  }

  ReminderCategory _detectCategory(String text) {
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
    return ReminderCategory.none;
  }

  // Use NLP parser from nlp_parser.dart
  ParsedReminder _parseNaturalLanguage(String text) {
    return NLPParser.parseNaturalLanguage(text);
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
    print('Saving ${reminderStrings.length} reminders to storage');
    await prefs.setStringList('reminders', reminderStrings);
    await prefs.setStringList('recent_reminders', recentStrings);
    print('Reminders saved successfully');
  }

  Future<void> _scheduleReminder(
    String text,
    Duration delay, {
    RecurrenceType? recurrence,
  }) async {
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

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    try {
      // Get local timezone
      final location = tz.local;
      print('Using timezone: ${location.name}');

      // Convert scheduled time to timezone-aware datetime
      final scheduledDateTime =
          tz.TZDateTime.from(reminder.scheduledTime, location);
      print('Scheduled time (local): ${reminder.scheduledTime}');
      print('Scheduled time (TZ): $scheduledDateTime');

      // Check if the time is in the future
      final now = tz.TZDateTime.now(location);
      print('Current time (TZ): $now');

      if (scheduledDateTime.isBefore(now)) {
        print('Warning: Scheduled time is in the past, adjusting to future');
        // Add 1 minute to make it future
        final adjustedTime = scheduledDateTime.add(const Duration(minutes: 1));
        print('Adjusted time: $adjustedTime');

        await flutterLocalNotificationsPlugin.zonedSchedule(
          reminder.id,
          'Reminder',
          text,
          adjustedTime,
          platformChannelSpecifics,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: null,
        );
      } else {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          reminder.id,
          'Reminder',
          text,
          scheduledDateTime,
          platformChannelSpecifics,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: null,
        );
      }

      print('Notification scheduled successfully for ID: ${reminder.id}');
    } catch (e) {
      // Continue even if notification fails
      print('Notification scheduling failed: $e');
      print('Stack trace: ${StackTrace.current}');
    }

    setState(() {
      _reminders.add(reminder);
    });
    print('Adding reminder: ${reminder.text}');
    await _saveReminders();
    print('Reminder saved. Total reminders: ${_reminders.length}');

    _textController.clear();
    final recurrenceText =
        recurrence != null && recurrence != RecurrenceType.none
            ? ' (${_formatRecurrence(recurrence)})'
            : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reminder set for ${_formatDuration(delay)}$recurrenceText',
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 60) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      if (minutes == 0 && seconds > 0) {
        return '< 1 minute';
      } else if (minutes == 1) {
        return '1 minute';
      } else {
        return '$minutes minutes';
      }
    } else if (duration.inHours < 24) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      if (minutes > 0) {
        return '$hours hours $minutes minutes';
      } else {
        return '$hours hours';
      }
    } else {
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      if (hours > 0) {
        return '$days days $hours hours';
      } else {
        return '$days days';
      }
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
        return 'No repeat';
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
      default:
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
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: Colors.black87),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _showAdvanced = !_showAdvanced),
                    icon: Icon(
                      _showAdvanced ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings),
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
                        hintText: 'Type or speak your reminder...',
                        hintStyle:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_textController.text.isNotEmpty)
                              IconButton(
                                icon:
                                    const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _textController.clear();
                                  setState(() {});
                                },
                                tooltip: 'Clear text',
                              ),
                            IconButton(
                              padding: EdgeInsets.all(10),
                              icon: Icon(
                                _isListening ? Icons.mic : Icons.mic_none,
                                color: _isListening ? Colors.red : Colors.grey,
                              ),
                              onPressed: _isListening
                                  ? _stopListening
                                  : _startListening,
                              tooltip: _isListening
                                  ? 'Stop listening'
                                  : 'Start voice input',
                            ),
                          ],
                        ),
                      ),
                      autofocus: true,
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          final parsed = _parseNaturalLanguage(value);
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
                              backgroundColor: _getCategoryColor(
                                reminder.category,
                              ),
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
                    icon: 'Custom',
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
                          'No reminders set (${_reminders.length})',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(0),
                        itemCount: _reminders.length,
                        itemBuilder: (context, index) {
                          final reminder = _reminders[index];
                          return ReminderCard(
                            reminder: reminder,
                            onDelete: () => _deleteReminder(index),
                            onComplete: () => _completeReminder(index),
                            countdownText: _countdownTexts[reminder.id],
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
      // If it's past 8 PM, set for tomorrow at 8 PM
      final tomorrowTonight = DateTime(now.year, now.month, now.day + 1, 20, 0);
      return tomorrowTonight.difference(now);
    }
    return tonight.difference(now);
  }

  void _setReminder(Duration duration, {RecurrenceType? recurrence}) {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _scheduleReminder(text, duration, recurrence: recurrence);
    } else {
      // Use default reminder text when field is empty
      _scheduleReminder('General reminder', duration, recurrence: recurrence);
    }
  }

  void _setReminderWithParsedData(
    ParsedReminder parsed, {
    RecurrenceType? recurrence,
  }) {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      // Use the parsed title if it's better than the raw text
      final reminderText = parsed.confidence > 0.7 ? parsed.title : text;
      final delay = parsed.scheduledTime.difference(DateTime.now());
      _scheduleReminder(
        reminderText,
        delay.isNegative ? const Duration(minutes: 30) : delay,
        recurrence: recurrence,
      );
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
      _setReminder(
        const Duration(minutes: 30),
        recurrence: reminder.recurrence,
      );
    } else {
      _setReminder(delay, recurrence: reminder.recurrence);
    }
  }

  void _completeReminder(int index) {
    final reminder = _reminders[index];
    if (reminder.recurrence != RecurrenceType.none) {
      // Schedule next occurrence
      final nextTime = _getNextOccurrence(
        reminder.scheduledTime,
        reminder.recurrence,
      );
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
        return DateTime(
          current.year,
          current.month + 1,
          current.day,
          current.hour,
          current.minute,
        );
      case RecurrenceType.none:
        return current;
    }
  }

  // Custom quick time chip widget
  Widget _QuickTimeChip({
    required String label,
    required int minutes,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.urbanist(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  void _showAdvancedOptions(String text) {
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    RecurrenceType selectedRecurrence = RecurrenceType.none;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.65,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Custom Reminder',
                      style: GoogleFonts.urbanist(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Current text preview
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reminder text:',
                      style: GoogleFonts.urbanist(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      text,
                      style: GoogleFonts.urbanist(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Date picker
              Text(
                'Date',
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.green),
                    const SizedBox(width: 10),
                    Text(
                      '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                      style: GoogleFonts.urbanist(fontSize: 16),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setModalState(() => selectedDate = date);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Time picker
              Text(
                'Time',
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.green),
                    const SizedBox(width: 10),
                    Text(
                      selectedTime.format(context),
                      style: GoogleFonts.urbanist(fontSize: 16),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (time != null) {
                          setModalState(() => selectedTime = time);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Recurrence
              Text(
                'Repeat',
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<RecurrenceType>(
                  value: selectedRecurrence,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: RecurrenceType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            _formatRecurrence(type),
                            style: GoogleFonts.urbanist(fontSize: 16),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setModalState(() => selectedRecurrence = value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Quick time buttons
              Text(
                'Quick Times',
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickTimeChip(
                    label: '15 min',
                    minutes: 15,
                    onTap: () {
                      final now = DateTime.now();
                      selectedDate = now;
                      selectedTime = TimeOfDay.fromDateTime(
                          now.add(const Duration(minutes: 15)));
                      setModalState(() {});
                    },
                  ),
                  _QuickTimeChip(
                    label: '30 min',
                    minutes: 30,
                    onTap: () {
                      final now = DateTime.now();
                      selectedDate = now;
                      selectedTime = TimeOfDay.fromDateTime(
                          now.add(const Duration(minutes: 30)));
                      setModalState(() {});
                    },
                  ),
                  _QuickTimeChip(
                    label: '1 hour',
                    minutes: 60,
                    onTap: () {
                      final now = DateTime.now();
                      selectedDate = now;
                      selectedTime = TimeOfDay.fromDateTime(
                          now.add(const Duration(hours: 1)));
                      setModalState(() {});
                    },
                  ),
                  _QuickTimeChip(
                    label: 'Tomorrow',
                    minutes: 1440,
                    onTap: () {
                      final tomorrow =
                          DateTime.now().add(const Duration(days: 1));
                      selectedDate = tomorrow;
                      selectedTime = TimeOfDay.fromDateTime(tomorrow);
                      setModalState(() {});
                    },
                  ),
                ],
              ),

              const Spacer(),

              // Create button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Create final DateTime
                    final finalDateTime = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );

                    Navigator.pop(context);

                    // Create reminder with custom date/time
                    _setReminderWithParsedData(
                      ParsedReminder(
                        title: text,
                        action: 'reminder',
                        category: _detectCategory(text),
                        scheduledTime: finalDateTime,
                        confidence: 1.0,
                      ),
                      recurrence: selectedRecurrence,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Create Reminder',
                    style: GoogleFonts.urbanist(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 7),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSpecial ? Colors.green : Colors.grey.shade300,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSpecial ? Colors.green.withValues(alpha: 0.1) : null,
        ),
        child: Text(
          icon,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isSpecial ? Colors.green : null,
                fontWeight: FontWeight.w500,
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
  final String? countdownText;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onDelete,
    this.onComplete,
    this.countdownText,
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
      default:
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
      default:
        return Icons.notifications_active;
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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 10),
        leading: CircleAvatar(
          backgroundColor: _getCategoryColor(
            reminder.category,
          ).withValues(alpha: 0.2),
          radius: 16,
          child: Icon(
            _getCategoryIcon(reminder.category),
            color: _getCategoryColor(reminder.category),
            size: 16,
          ),
        ),
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
              countdownText ?? _formatTime(reminder.scheduledTime),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isActive ? Colors.grey.shade600 : Colors.grey,
                    fontWeight: countdownText != null
                        ? FontWeight.bold
                        : FontWeight.normal,
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
            if (isActive) Container(height: 20, width: 1, color: Colors.grey),
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

enum RecurrenceType { none, daily, weekly, monthly }

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
