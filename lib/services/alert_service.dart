import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class AlertService {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;
  AlertService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alertTimer;
  Timer? _vibrationTimer;
  bool _isAlerting = false;

  /// Trigger scam alert with vibration and sound
  Future<void> triggerScamAlert() async {
    if (_isAlerting) return;

    _isAlerting = true;

    // Start vibration pattern using HapticFeedback
    // Pattern: vibrate every 700ms (500ms vibrate + 200ms pause)
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 700), (
      timer,
    ) {
      HapticFeedback.heavyImpact();
      // Also try medium impact for variation
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.mediumImpact();
      });
    });

    // Play alarm sound
    try {
      // You'll need to add an alarm sound file to assets
      // For now, using system sound
      await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      // Fallback to system sound if asset not found
      SystemSound.play(SystemSoundType.alert);
    }

    // Stop alert after 30 seconds
    _alertTimer = Timer(const Duration(seconds: 30), () {
      stopAlert();
    });
  }

  /// Stop the scam alert
  Future<void> stopAlert() async {
    if (!_isAlerting) return;

    _isAlerting = false;
    _alertTimer?.cancel();
    _alertTimer = null;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;

    await _audioPlayer.stop();
  }

  /// Check if alert is currently active
  bool get isAlerting => _isAlerting;
}
