import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'nlp_parser.dart';

class VoiceService {
  static final SpeechToText _speech = SpeechToText();
  static final FlutterTts _tts = FlutterTts();
  static bool _isInitialized = false;
  static bool _isListening = false;
  static String _triggerPhrase = "hey Kumbu";
  static List<Map<String, dynamic>> _savedReminders = [];

  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize speech recognition
    final available = await _speech.initialize(
      onError: (error) {
        print('Speech initialization error: $error');
      },
      onStatus: (status) {
        print('Speech status: $status');
      },
    );

    if (!available) {
      print('Speech recognition not available on this device');
    }

    // Initialize text-to-speech with slower, more natural speech
    await _tts.setLanguage("en_US");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5); // Slowed down from 0.9 to 0.5
    await _tts.setVolume(1.0);

    await _loadSettings();
    await _loadSavedReminders();

    _isInitialized = true;
  }

  static Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _triggerPhrase = prefs.getString('trigger_phrase') ?? "hey kumbu";
  }

  static Future<void> _loadSavedReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStrings = prefs.getStringList('voice_reminders') ?? [];
    _savedReminders = savedStrings
        .map((str) => jsonDecode(str) as Map<String, dynamic>)
        .toList();
  }

  static Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final remindersJson = _savedReminders.map((r) => jsonEncode(r)).toList();
    await prefs.setStringList('voice_reminders', remindersJson);
  }

  static Future<void> setTriggerPhrase(String phrase) async {
    _triggerPhrase = phrase.toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_trigger', _triggerPhrase);
  }

  static String get triggerPhrase => _triggerPhrase;

  static Future<bool> isAvailable() async {
    return await _speech.initialize();
  }

  static void startListening({
    required Function(String) onResult,
    required Function(String) onError,
    required VoidCallback onListeningStart,
    required VoidCallback onListeningEnd,
  }) async {
    if (!_isInitialized) await initialize();
    if (!await isAvailable()) {
      onError("Speech recognition not available");
      return;
    }

    _isListening = true;
    onListeningStart();
    String? finalTranscript;

    // Set up status listener before starting
    _speech.statusListener = (status) {
      print('Speech status: $status');
      if (status == 'done' || status == 'notListening') {
        _isListening = false;
        print('Listening ended - processing final transcript');

        // Only process the command after listening stops
        if (finalTranscript != null && finalTranscript!.isNotEmpty) {
          final transcript = finalTranscript!.toLowerCase();
          print('Processing final transcript: $transcript');

          // Check for trigger phrase
          if (transcript.contains(_triggerPhrase.toLowerCase())) {
            final fullCommand =
                transcript.replaceAll(_triggerPhrase.toLowerCase(), '').trim();
            final command = fullCommand;
            print('Final extracted command: $command');

            if (command.isNotEmpty) {
              print(
                  'Trigger phrase detected - processing command after listening stopped');
              onResult(command);
            } else {
              print('Trigger phrase detected but command is empty');
            }
          } else {
            print('No trigger phrase detected - putting text in input field');
            onResult(finalTranscript!);
          }
        }

        onListeningEnd();
      }
    };

    await _speech.listen(
      onResult: (result) {
        print(
            'Speech result: ${result.recognizedWords} (final: ${result.finalResult})');
        final recognizedWords = result.recognizedWords;
        if (recognizedWords.isNotEmpty) {
          final transcript = recognizedWords.toLowerCase();
          print('Transcript: $transcript');

          // Store the final transcript but don't process yet
          if (result.finalResult) {
            finalTranscript = recognizedWords;
            print('Final transcript stored: $finalTranscript');
          }

          // Always update the input field with current speech for visual feedback
          if (transcript.contains(_triggerPhrase.toLowerCase())) {
            final fullCommand =
                transcript.replaceAll(_triggerPhrase.toLowerCase(), '').trim();
            if (fullCommand.isNotEmpty) {
              // Update input field but don't create reminder yet
              print('Updating input field with: $fullCommand');
            }
          } else {
            print('Updating input field with: $recognizedWords');
          }
        }
      },
      onSoundLevelChange: (level) {
        print('Sound level: $level');
      },
      cancelOnError: false,
      partialResults: true,
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 3),
      listenMode: ListenMode.confirmation,
    );
  }

  static void stopListening() {
    _speech.stop();
    _isListening = false;
  }

  static Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();
    await _tts.speak(text);
  }

  static Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  static bool get isListening => _isListening;

  static Future<void> saveVoiceReminder(
      String command, ParsedReminder parsed) async {
    final reminderData = {
      'command': command,
      'title': parsed.title,
      'action': parsed.action,
      'category': parsed.category.index,
      'scheduledTime': parsed.scheduledTime.toIso8601String(),
      'confidence': parsed.confidence,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _savedReminders.insert(0, reminderData);
    if (_savedReminders.length > 50) {
      _savedReminders = _savedReminders.take(50).toList();
    }

    await _saveReminders();
  }

  static List<Map<String, dynamic>> get savedReminders => _savedReminders;

  static Future<void> clearSavedReminders() async {
    _savedReminders.clear();
    await _saveReminders();
  }

  static String generateConfirmationResponse(ParsedReminder parsed) {
    final timeUntil = parsed.scheduledTime.difference(DateTime.now());
    String timeText;

    // Use same countdown formatting as main app
    if (timeUntil.inSeconds <= 0) {
      timeText = "Now!";
    } else if (timeUntil.inSeconds <= 60) {
      timeText = "${timeUntil.inSeconds} seconds";
    } else if (timeUntil.inMinutes < 60) {
      final minutes = timeUntil.inMinutes;
      final seconds = timeUntil.inSeconds % 60;
      timeText = "$minutes minutes $seconds seconds";
    } else if (timeUntil.inHours < 24) {
      final hours = timeUntil.inHours;
      final minutes = timeUntil.inMinutes % 60;
      timeText = "$hours hours $minutes minutes";
    } else {
      final days = timeUntil.inDays;
      final hours = timeUntil.inHours % 24;
      timeText = "$days days $hours hours";
    }

    // Smart title cleaning - only remove action word if it's clearly duplicated
    String cleanTitle = parsed.title.toLowerCase();
    final actionLower = parsed.action.toLowerCase();

    // Only remove action word if it appears at the start AND there's more content after it
    if (cleanTitle.startsWith('$actionLower ')) {
      cleanTitle = cleanTitle.substring(actionLower.length).trim();
    }

    // Don't remove action words that are part of the actual title content
    // For example: "cook meat" should stay as "cook meat", not become "meat"

    return "Reminder set: ${parsed.action} ${cleanTitle} in $timeText.";
  }
}
