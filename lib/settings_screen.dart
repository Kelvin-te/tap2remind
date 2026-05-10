import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'voice_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _triggerController = TextEditingController();
  bool _voiceEnabled = true;
  bool _autoSaveVoice = true;
  double _speechRate = 0.5;
  double _speechPitch = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _triggerController.text = VoiceService.triggerPhrase;
      _voiceEnabled = prefs.getBool('voice_enabled') ?? true;
      _autoSaveVoice = prefs.getBool('auto_save_voice') ?? true;
      _speechRate = prefs.getDouble('speech_rate') ?? 0.5;
      _speechPitch = prefs.getDouble('speech_pitch') ?? 1.0;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await VoiceService.setTriggerPhrase(_triggerController.text.trim());
    await prefs.setBool('voice_enabled', _voiceEnabled);
    await prefs.setBool('auto_save_voice', _autoSaveVoice);
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setDouble('speech_pitch', _speechPitch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.urbanist(fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voice Settings',
              style: GoogleFonts.urbanist(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            // Voice Trigger Phrase
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice Trigger Phrase',
                      style: GoogleFonts.urbanist(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _triggerController,
                      decoration: InputDecoration(
                        hintText: 'e.g., "hey remind", "okay remind"',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      style: GoogleFonts.urbanist(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Say this phrase followed by your reminder command',
                      style: GoogleFonts.urbanist(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Voice Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice Options',
                      style: GoogleFonts.urbanist(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text(
                        'Enable Voice Commands',
                        style: GoogleFonts.urbanist(),
                      ),
                      subtitle: Text(
                        'Allow voice input for reminders',
                        style: GoogleFonts.urbanist(fontSize: 12),
                      ),
                      value: _voiceEnabled,
                      onChanged: (value) {
                        setState(() => _voiceEnabled = value);
                      },
                    ),
                    SwitchListTile(
                      title: Text(
                        'Auto-save Voice Reminders',
                        style: GoogleFonts.urbanist(),
                      ),
                      subtitle: Text(
                        'Automatically save voice commands',
                        style: GoogleFonts.urbanist(fontSize: 12),
                      ),
                      value: _autoSaveVoice,
                      onChanged: (value) {
                        setState(() => _autoSaveVoice = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Speech Rate',
                      style: GoogleFonts.urbanist(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Slider(
                      value: _speechRate,
                      min: 0.3,
                      max: 1.0,
                      divisions: 14,
                      onChanged: (value) {
                        setState(() => _speechRate = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Speech Pitch',
                      style: GoogleFonts.urbanist(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Slider(
                      value: _speechPitch,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      onChanged: (value) {
                        setState(() => _speechPitch = value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _saveSettings();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Settings saved successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Save Settings',
                  style: GoogleFonts.urbanist(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
