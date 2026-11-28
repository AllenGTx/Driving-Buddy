import 'buddy_voice_config.dart';

enum WakeMatchKind {
  none,
  wakeOnly,
  commandWithWake,
  cancel,
}

class WakeMatchResult {
  const WakeMatchResult({
    required this.kind,
    this.remainingCommand = '',
    this.matchedAlias = '',
  });

  final WakeMatchKind kind;
  final String remainingCommand;
  final String matchedAlias;
}

class WakeWordMatcher {
  // Variasi sapaan lisan sehari-hari Bahasa Indonesia & Inggris (termasuk 'ei', 'ey', 'hei', 'ya', dll.)
  static const Set<String> _greetings = {
    'oi', 'oy', 'oiy', 'woi', 'woy', 'hoy',
    'ei', 'eii', 'ey', 'eyy', 'eh', 'ehh',
    'hei', 'heii', 'hey', 'heyy', 'hai', 'haii', 'hi', 'hii',
    'halo', 'hallo', 'haloo', 'alo', 'allo', 'helo', 'hello',
    'ya', 'yah', 'a', 'o', 'uh', 'um', 'emm', 'hmm', 'ok', 'oke', 'okay',
    'p', 'ping', 'tes', 'test', 'cek',
    'bro', 'sis', 'kak', 'kakak', 'mbak', 'mba', 'mas', 'bang', 'abng',
    'cuy', 'gan', 'min', 'bos', 'bestie', 'sob', 'nona', 'tuan', 'bu', 'pak',
    'tolong', 'permisi', 'punten', 'misi', 'dengerin', 'bangun', 'aktif',
    'ayo', 'yuk', 'coba', 'we', 'wey', 'wei', 'yo', 'yoo',
    'pagi', 'siang', 'sore', 'malam', 'malem', 'selamat', 'assalamualaikum',
    'spada', 'hadir', 'bantu', 'please', 'dear',
  };

  static const Set<String> _trailingFillers = {
    'dong', 'ya', 'yah', 'yaa', 'deh', 'nih', 'sih', 'gak', 'ga', 'nggak', 'kah',
    'disana', 'situ', 'hadir', 'kan', 'yuk', 'cuy', 'kak', 'mbak', 'mas',
    'sayang', 'plis', 'please', 'bisa', 'dengar', 'denger', 'aktif',
    'halo', 'hai', 'hei', 'ei', 'ey', 'oi', 'oy', 'eh',
  };

  static const Set<String> _cancelFillers = {
    'eh', 'ehh', 'ei', 'ah', 'ahh', 'oh', 'oalah', 'uh', 'umm', 'hmm',
    'duh', 'aduh', 'waduh', 'sorry', 'sori', 'maaf', 'punten',
    'udah', 'sudah', 'yaudah', 'ya', 'yah', 'yaa', 'deh', 'dong',
    'kok', 'sih', 'nih', 'aja', 'saja', 'dulu', 'kak', 'mbak', 'mas',
    'bro', 'sis', 'cuy',
  };

  static const Set<String> _singleCancelTokens = {
    'gjd', 'gajadi', 'gkjadi', 'gakjadi', 'nggajadi', 'nggakjadi', 'enggakjadi',
    'gausah', 'gakusah', 'gkusa', 'gkusah',
    'batal', 'batalkan', 'cancel', 'canceled', 'cancelled',
    'nevermind', 'lupain', 'lupakan', 'skip', 'nothing',
  };

  static const Set<String> _multiCancelPhrases = {
    'ga jadi', 'gak jadi', 'gk jadi', 'ngga jadi', 'nggak jadi',
    'engga jadi', 'enggak jadi', 'kagak jadi', 'nda jadi', 'ndak jadi',
    'tak jadi', 'tidak jadi',
    'ga usah', 'gak usah', 'gk usah', 'ngga usah', 'nggak usah',
    'engga usah', 'enggak usah', 'tidak usah', 'tak usah',
    'never mind', 'forget it', 'leave it',
  };

  static const Set<String> _signOffFillers = {
    'eh', 'oh', 'ok', 'oke', 'okay', 'sip', 'siap', 'mantap', 'baik',
    'ya', 'yah', 'yaa', 'deh', 'dong', 'nih', 'sih', 'aja', 'saja', 'dulu',
    'udah', 'sudah', 'yaudah', 'segitu', 'itu',
    'kak', 'mbak', 'mas', 'bro', 'sis', 'cuy', 'sayang', 'bestie',
    'banyak', 'sekali', 'banget', 'for', 'now', 'so', 'much',
  };

  static const Set<String> _signOffCoreWords = {
    'makasih', 'terimakasih', 'trimakasih', 'trims', 'makasi', 'tengkyu',
    'terima', 'kasih',
    'thanks', 'thank', 'you',
    'cukup', 'udahan', 'selesai',
    'bye', 'byebye', 'dadah', 'dah', 'sampai', 'jumpa', 'done',
  };

  static final RegExp _gluedPrefixPattern = RegExp(
    r'^(oi|oy|woi|woy|ei|ey|eh|hei|heii|hey|heyy|hai|hi|halo|hallo|haloo|alo|yo|yoo|ya)(rina|rinaa|furina|jane|jein|jeni|jan|jen|john|jon|jhon|buddy|badi)$',
  );

  static bool _matchesAlias(String word, Set<String> aliases, String nickLow) {
    if (aliases.contains(word)) return true;
    if (_gluedPrefixPattern.hasMatch(word)) return true;
    if (nickLow.isNotEmpty && word == '$nickLow$nickLow') return true;
    if (nickLow.length >= 4 && word.length >= 3 && _levenshtein(word, nickLow) <= 1) {
      return true;
    }
    return false;
  }

  /// Deteksi lokal (0 token) untuk ucapan pembatalan seperti "gjd",
  /// "eh gak jadi deh", "batal", "ga usah", atau "never mind".
  static bool isCancelIntent(
    String rawTranscript, {
    BuddyVoiceProfile profile = BuddyVoiceProfile.furina,
    String activeNickname = 'Rina',
  }) {
    final cleaned = rawTranscript
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return false;

    final words = cleaned.split(' ');
    if (words.length > 7) return false;

    final aliases = aliasesFor(profile, activeNickname);
    final nickLow = activeNickname.toLowerCase().trim();

    final core = <String>[];
    for (final w in words) {
      if (_matchesAlias(w, aliases, nickLow) ||
          _greetings.contains(w) ||
          _cancelFillers.contains(w)) {
        continue;
      }
      core.add(w);
    }

    if (core.isEmpty) return false;
    if (core.length == 1 && _singleCancelTokens.contains(core.first)) {
      return true;
    }
    final joinedCore = core.join(' ');
    return _multiCancelPhrases.contains(joinedCore);
  }

  /// Deteksi lokal apakah ucapan pendek pengguna adalah penutup obrolan sopan
  /// (mis. "oke makasih ya Rina", "udah cukup dulu", "sip makasih", "bye"),
  /// sehingga sesudah Buddy menjawab salam penutup, Orb langsung menutup otomatis.
  static bool isConversationSignOff(
    String rawTranscript, {
    BuddyVoiceProfile profile = BuddyVoiceProfile.furina,
    String activeNickname = 'Rina',
  }) {
    final cleaned = rawTranscript
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return false;

    final words = cleaned.split(' ');
    if (words.length > 7) return false;

    final aliases = aliasesFor(profile, activeNickname);
    final nickLow = activeNickname.toLowerCase().trim();

    final core = <String>[];
    for (final w in words) {
      if (_matchesAlias(w, aliases, nickLow) || _signOffFillers.contains(w)) {
        continue;
      }
      core.add(w);
    }

    if (core.isEmpty) return false;
    return core.every(_signOffCoreWords.contains);
  }

  static Set<String> aliasesFor(BuddyVoiceProfile profile, String activeNickname) {
    final base = <String>{
      activeNickname.toLowerCase().trim(),
      'buddy',
      'badi',
      'driving buddy',
    };
    switch (profile) {
      case BuddyVoiceProfile.furina:
        base.addAll({
          'rina', 'rinaa', 'rinna', 'riina', 'rin', 'reina', 'raina', 'rena',
          'ina', 'trina', 'brina', 'prina', 'srina', 'lina', 'fina', 'wina',
          'tina', 'karina', 'mina', 'nina', 'dina', 'vina', 'verina', 'arina',
          'orina', 'irina', 'erina', 'urina', 'forin', 'furinah', 'rinah',
          'furina', 'furinaa', 'forina', 'farina', 'ferina', 'purina', 'vurina',
          'florina', 'felina', 'falina', 'furin', 'kurina', 'rinarina',
          'eirina', 'heirina', 'oirina', 'halorina', 'hairina', 'yorina', 'yofurina', 'heifurina',
        });
        break;
      case BuddyVoiceProfile.john:
        base.addAll({
          'john', 'jon', 'jhon', 'joni', 'johan', 'johny', 'johnny', 'zon', 'don', 'jo',
          'yon', 'jong', 'yoon', 'jun', 'chon', 'jean', 'shan', 'shon', 'yohan', 'yohn',
          'yoan', 'joan', 'joon', 'sean', 'shawn', 'zone', 'yojon', 'yojo',
          'heijohn', 'heijon', 'haijohn', 'haijon', 'oijohn', 'oijon', 'eijohn', 'halojohn', 'yojohn',
        });
        break;
      case BuddyVoiceProfile.jane:
        base.addAll({
          'jane', 'jen', 'jeni', 'jein', 'jenny', 'jenn', 'jenna', 'zen', 'jain', 'jeyn', 'jeane',
          'jan', 'jean', 'yen', 'yohane', 'yozen', 'jaen', 'jaine', 'jehn', 'jeny',
          'heijane', 'heijen', 'haijane', 'haijen', 'oijane', 'oijen', 'eijane', 'eijen', 'halojane', 'halojen', 'yojane', 'yojein', 'yojen',
        });
        break;
    }
    base.removeWhere((s) => s.isEmpty);
    return base;
  }

  static WakeMatchResult match(
    String rawTranscript, {
    required BuddyVoiceProfile profile,
    required String activeNickname,
  }) {
    final cleaned = rawTranscript
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) {
      return const WakeMatchResult(kind: WakeMatchKind.none);
    }

    final words = cleaned.split(' ');
    final aliases = aliasesFor(profile, activeNickname);
    final nickLow = activeNickname.toLowerCase().trim();

    int nameIndex = -1;
    String matched = '';

    // Cari posisi nama Buddy pada 5 kata pertama agar sapaan berulang seperti "eh ei rina rina" tertangkap
    final scanLimit = words.length < 5 ? words.length : 5;
    for (int i = 0; i < scanLimit; i++) {
      final w = words[i];
      if (_matchesAlias(w, aliases, nickLow)) {
        bool prefixValid = true;
        for (int j = 0; j < i; j++) {
          if (!_greetings.contains(words[j]) && !_matchesAlias(words[j], aliases, nickLow)) {
            prefixValid = false;
            break;
          }
        }
        if (prefixValid) {
          nameIndex = i;
          matched = w;
          break;
        }
      }
    }

    if (nameIndex < 0) {
      return const WakeMatchResult(kind: WakeMatchKind.none);
    }

    // Lewati pengulangan nama berturut-turut seperti "rina rina" atau "hei rina rina"
    int commandStartIndex = nameIndex + 1;
    while (commandStartIndex < words.length &&
        (_matchesAlias(words[commandStartIndex], aliases, nickLow) ||
            _greetings.contains(words[commandStartIndex]))) {
      commandStartIndex++;
    }

    final afterWords = words.sublist(commandStartIndex);
    final meaningfulAfter = afterWords
        .where((w) => !_trailingFillers.contains(w) && !_matchesAlias(w, aliases, nickLow))
        .toList();

    if (meaningfulAfter.isEmpty) {
      return WakeMatchResult(
        kind: WakeMatchKind.wakeOnly,
        matchedAlias: matched,
      );
    }

    if (isCancelIntent(
      afterWords.join(' '),
      profile: profile,
      activeNickname: activeNickname,
    )) {
      return WakeMatchResult(
        kind: WakeMatchKind.cancel,
        matchedAlias: matched,
      );
    }

    final origTokens = rawTranscript.trim().split(RegExp(r'\s+'));
    final remainder = origTokens.length > commandStartIndex
        ? origTokens
              .sublist(commandStartIndex)
              .join(' ')
              .replaceFirst(RegExp(r'^[,.:;?!\-\s]+'), '')
              .trim()
        : afterWords.join(' ');

    return WakeMatchResult(
      kind: WakeMatchKind.commandWithWake,
      remainingCommand: remainder,
      matchedAlias: matched,
    );
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final del = prev[j + 1] + 1;
        final ins = curr[j] + 1;
        final sub = prev[j] + cost;
        curr[j + 1] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      for (int j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[b.length];
  }
}
