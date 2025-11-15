import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class AlertService {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;
  AlertService._internal();

  AudioPlayer? _audioPlayer;
  AudioPlayer? _ringtonePlayer;
  Timer? _alertTimer;
  Timer? _vibrationTimer;
  bool _isAlerting = false;
  bool _audioPlayerAvailable = true;
  bool _isRinging = false;

  /// Initialize audio player if available
  void _ensureAudioPlayer() {
    if (_audioPlayer == null && _audioPlayerAvailable) {
      try {
        _audioPlayer = AudioPlayer();
        // Configure audio player to use device's current audio output
        _audioPlayer!.setPlayerMode(PlayerMode.mediaPlayer);
      } catch (e) {
        print('AudioPlayer not available: $e');
        _audioPlayerAvailable = false;
      }
    }
  }

  /// Initialize ringtone player if available
  void _ensureRingtonePlayer() {
    if (_ringtonePlayer == null && _audioPlayerAvailable) {
      try {
        _ringtonePlayer = AudioPlayer();
        // Configure audio player to use device's current audio output
        // This ensures ringtone plays through speaker/earpiece/headphones as configured
        _ringtonePlayer!.setPlayerMode(PlayerMode.mediaPlayer);
      } catch (e) {
        print('Ringtone AudioPlayer not available: $e');
        _audioPlayerAvailable = false;
      }
    }
  }

  /// Start ringtone loop for incoming call
  Future<void> startRingtone() async {
    if (_isRinging) return;
    if (!_audioPlayerAvailable) {
      SystemSound.play(SystemSoundType.alert);
      _isRinging = true;
      return;
    }

    try {
      _ensureRingtonePlayer();
      if (_ringtonePlayer != null) {
        await _ringtonePlayer!.play(AssetSource('sounds/ringtone.mp3'));
        await _ringtonePlayer!.setReleaseMode(ReleaseMode.loop);
        _isRinging = true;
      } else {
        SystemSound.play(SystemSoundType.alert);
        _isRinging = true;
      }
    } on MissingPluginException {
      print('Ringtone plugin not available, using system sound');
      _audioPlayerAvailable = false;
      SystemSound.play(SystemSoundType.alert);
      _isRinging = true;
    } catch (e) {
      print('Error playing ringtone: $e');
      SystemSound.play(SystemSoundType.alert);
      _isRinging = true;
    }
  }

  /// Stop ringtone
  Future<void> stopRingtone() async {
    if (!_isRinging) return;
    _isRinging = false;
    if (_ringtonePlayer != null) {
      try {
        await _ringtonePlayer!.stop();
      } catch (e) {
        print('Error stopping ringtone: $e');
      }
    }
  }

  /// Trigger scam alert with vibration and sound
  Future<void> triggerScamAlert() async {
    if (_isAlerting) return;

    // Ensure ringtone is stopped when alarm starts
    await stopRingtone();

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
    if (_audioPlayerAvailable) {
      try {
        _ensureAudioPlayer();
        if (_audioPlayer != null) {
          await _audioPlayer!.play(AssetSource('sounds/alarm.mp3'));
          await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
        } else {
          // Fallback to system sound
          SystemSound.play(SystemSoundType.alert);
        }
      } on MissingPluginException {
        // AudioPlayer plugin not registered - use system sound
        print('AudioPlayer plugin not available, using system sound');
        _audioPlayerAvailable = false;
        SystemSound.play(SystemSoundType.alert);
      } catch (e) {
        // Fallback to system sound if asset not found or other error
        print('Error playing alarm sound: $e');
        SystemSound.play(SystemSoundType.alert);
      }
    } else {
      // Use system sound if AudioPlayer is not available
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

    if (_audioPlayer != null) {
      try {
        await _audioPlayer!.stop();
      } catch (e) {
        print('Error stopping audio: $e');
      }
    }
  }

  /// Check if alert is currently active
  bool get isAlerting => _isAlerting;
  bool get isRinging => _isRinging;
}
