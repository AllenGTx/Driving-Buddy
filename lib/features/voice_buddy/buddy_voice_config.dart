import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BuddyVoiceProfile {
  jane,
  john,
  furina;

  String localizedLabel({required bool isEnglish}) {
    if (isEnglish) {
      switch (this) {
        case BuddyVoiceProfile.jane:
          return 'Jane (Female Buddy)';
        case BuddyVoiceProfile.john:
          return 'John (Male Buddy)';
        case BuddyVoiceProfile.furina:
          return 'Furina (Special Buddy)';
      }
    }
    switch (this) {
      case BuddyVoiceProfile.jane:
        return 'Jane (Buddy Wanita)';
      case BuddyVoiceProfile.john:
        return 'John (Buddy Pria)';
      case BuddyVoiceProfile.furina:
        return 'Furina (Buddy Spesial)';
    }
  }

  String get label => localizedLabel(isEnglish: false);

  String get defaultNickname {
    switch (this) {
      case BuddyVoiceProfile.furina:
        return 'Rina';
      case BuddyVoiceProfile.john:
        return 'John';
      case BuddyVoiceProfile.jane:
        return 'Jane';
    }
  }
}

class BuddyVoiceConfig extends ChangeNotifier {
  BuddyVoiceConfig._();

  static final BuddyVoiceConfig instance = BuddyVoiceConfig._();

  static const String _prefProfile = 'buddy_voice_profile';
  static const String _prefCustomName = 'buddy_custom_nickname';

  BuddyVoiceProfile _profile = BuddyVoiceProfile.furina;
  String _customNickname = '';
  bool _loaded = false;

  BuddyVoiceProfile get profile => _profile;

  String get activeNickname {
    final trimmed = _customNickname.trim();
    return trimmed.isNotEmpty ? trimmed : _profile.defaultNickname;
  }

  String get rawCustomNickname => _customNickname;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProf = prefs.getString(_prefProfile);
      if (savedProf != null) {
        _profile = BuddyVoiceProfile.values.firstWhere(
          (v) => v.name == savedProf,
          orElse: () => BuddyVoiceProfile.furina,
        );
      }
      _customNickname = prefs.getString(_prefCustomName) ?? '';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setProfile(BuddyVoiceProfile next) async {
    if (_profile == next) return;
    _profile = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefProfile, next.name);
    } catch (_) {}
  }

  Future<void> setCustomNickname(String name) async {
    final cleaned = name.trim();
    if (_customNickname == cleaned) return;
    _customNickname = cleaned;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cleaned.isEmpty) {
        await prefs.remove(_prefCustomName);
      } else {
        await prefs.setString(_prefCustomName, cleaned);
      }
    } catch (_) {}
  }
}
