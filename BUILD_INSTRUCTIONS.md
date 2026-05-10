# Tap2Remind - Build Instructions

## Quick Setup for Android Deployment

### Prerequisites
1. Install Flutter SDK from https://flutter.dev/docs/get-started/install/windows
2. Install Android Studio with Android SDK
3. Set up Android emulator or physical device

### Build Steps

1. **Install Dependencies**
   ```bash
   flutter pub get
   ```

2. **Check Environment**
   ```bash
   flutter doctor
   ```

3. **Build APK**
   ```bash
   flutter build apk --release
   ```

4. **Find Your APK**
   The built APK will be located at:
   `build/app/outputs/flutter-apk/app-release.apk`

### Alternative: Build App Bundle (Recommended for Play Store)
```bash
flutter build appbundle --release
```

### Testing on Device
```bash
flutter run
```

### Key Features Implemented
- Ultra-simple single-screen interface
- Quick time buttons (10 min, 1 hr, Tonight, Tomorrow)
- Smart time suggestions when typing
- Local notifications
- Auto-cleanup of completed reminders
- No accounts or setup required

### App Permissions
- RECEIVE_BOOT_COMPLETED (for reminders after device restart)
- VIBRATE (for notification vibration)
- WAKE_LOCK (to wake device for notifications)
- SCHEDULE_EXACT_ALARM (for precise reminder timing)
- POST_NOTIFICATIONS (Android 13+ notification permission)

### Deployment Notes
- Target SDK: 33 (Android 13)
- Min SDK: 21 (Android 5.0)
- App ID: com.example.tap2remind
- Version: 1.0.0
