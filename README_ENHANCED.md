# Tap2Remind - Enhanced Voice Reminder App

A sophisticated reminder app with advanced natural language processing and voice command capabilities.

## ✨ Features

### 🎯 Enhanced Natural Language Processing
- **Smart Time Parsing**: Understands "tomorrow at 3pm", "in 2 hours", "next Friday", etc.
- **Action Detection**: Recognizes 15+ action types (call, email, meeting, medicine, travel, etc.)
- **Title Extraction**: Automatically cleans up reminder text to extract the core message
- **Confidence Scoring**: Rates parsing accuracy for better reliability

### 🎤 Voice Commands
- **Custom Trigger Phrase**: Default "hey remind", customizable in settings
- **Auto-save**: Automatically saves voice commands with full JSON data
- **Text-to-Speech**: Speaks confirmation messages back to you
- **Permission Management**: Handles microphone and notification permissions

### 🎨 Modern UI
- **Urbanist Font**: Clean, modern typography throughout the app
- **Material 3**: Latest Material Design components
- **Smart Categories**: Color-coded reminders with icons
- **Quick Actions**: Fast preset times and templates

## 🚀 Usage Examples

### Voice Commands:
- *"Hey remind, call mom tomorrow at 3pm"*
- *"Hey remind, buy groceries in 2 hours"*
- *"Hey remind, take medicine every morning"*
- *"Hey remind, meeting with team next Friday"*

### Text Input:
- *"Email boss about project deadline"*
- *"Doctor appointment next Tuesday afternoon"*
- *"Pay electricity bill in 3 days"*
- *"Workout at the gym tomorrow morning"*

## 📱 App Structure

### Core Files:
- **`main.dart`** - Simplified main app file (400+ lines → cleaner)
- **`nlp_parser.dart`** - Advanced natural language processing
- **`voice_service.dart`** - Speech recognition and TTS
- **`settings_screen.dart`** - Customizable voice settings

### Dependencies:
- `google_fonts` - Urbanist font
- `chrono_dart` - Advanced date parsing
- `speech_to_text` - Voice recognition
- `flutter_tts` - Text-to-speech
- `flutter_local_notifications` - Reminder notifications

## 🎛️ Customization

### Voice Settings:
- **Trigger Phrase**: Change from "hey remind" to any phrase
- **Speech Rate**: Adjust TTS speaking speed (0.5x - 2.0x)
- **Speech Pitch**: Control voice pitch (0.5 - 2.0)
- **Auto-save**: Toggle automatic voice command saving

### Categories:
- Call (Green) 📞
- Email (Blue) 📧  
- Meeting (Purple) 👥
- Medicine (Red) 💊
- Work (Orange) 💼
- Personal (Pink) 🏠
- Travel (Teal) ✈️
- Health (Red) 🏥
- Finance (Amber) 💰
- Social (Purple) 👥

## 🔧 Technical Features

### NLP Parser:
- **15+ Action Types**: call, email, meeting, medicine, buy, pay, exercise, study, clean, cook, travel, work, personal, health, finance, social
- **Time Patterns**: "in X minutes", "X hours later", "tomorrow", "next Monday", "noon", "midnight", etc.
- **Smart Cleanup**: Removes filler words, fixes capitalization, handles punctuation
- **Fallback Logic**: Graceful degradation when chrono_dart fails

### Voice Service:
- **Continuous Listening**: 30-second sessions with 3-second pause detection
- **JSON Storage**: Saves full command data with confidence scores
- **Error Handling**: Comprehensive error reporting and fallbacks
- **Permission Flow**: Automatic microphone and notification requests

## 📊 Data Storage

### Saved Voice Data:
```json
{
  "command": "call mom tomorrow at 3pm",
  "title": "Call mom", 
  "action": "call",
  "category": 0,
  "scheduledTime": "2024-01-15T15:00:00.000Z",
  "confidence": 0.9,
  "createdAt": "2024-01-14T10:30:00.000Z"
}
```

### Reminders:
- Persistent storage with SharedPreferences
- Recent reminders (last 10)
- Recurring reminders (daily, weekly, monthly)
- Category-based organization

## 🎯 Smart Features

### Confidence-Based Processing:
- **High Confidence (>0.7)**: Uses parsed title
- **Medium Confidence (0.4-0.7)**: Uses enhanced parsing
- **Low Confidence (<0.4)**: Falls back to manual input

### Time Intelligence:
- **Past Date Handling**: Automatically assumes next occurrence
- **Relative Times**: "soon" (15min), "asap" (5min), "later" (2hrs)
- **Day-Specific**: Proper handling of "morning" (9am), "afternoon" (2pm), "night" (10pm)

## 🔒 Privacy & Security

### Local Storage:
- All data stored locally on device
- No cloud synchronization required
- Voice data processed locally

### Permissions:
- Microphone: For voice input only
- Notifications: For reminder alerts
- No internet access required for core features

---

**Tap2Remind** - Your intelligent voice assistant for perfect reminders!
