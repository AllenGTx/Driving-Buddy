import 'package:flutter_test/flutter_test.dart';

import 'package:driving_buddy/features/voice_buddy/buddy_voice_config.dart';
import 'package:driving_buddy/features/voice_buddy/wake_word_matcher.dart';

void main() {
  test('Wake-only greetings return wakeOnly (0 LLM tokens)', () {
    for (final call in [
      'Rina',
      'rina rina',
      'ei rina',
      'hei rina',
      'eirina',
      'heirina',
      'Oi Rina',
      'Ey Rina!',
      'Halo Furina',
      'Eh Rina ya?',
      'P Rina dong',
      'Mbak Lina', // toleransi salah dengar fonetik STT
    ]) {
      final res = WakeWordMatcher.match(
        call,
        profile: BuddyVoiceProfile.furina,
        activeNickname: 'Rina',
      );
      expect(res.kind, WakeMatchKind.wakeOnly, reason: 'Failed on: $call');
    }
  });

  test('Direct question with wake-word strips prefix and extracts clean query', () {
    final res = WakeWordMatcher.match(
      'Oi Rina, dimana Indomaret terdekat?',
      profile: BuddyVoiceProfile.furina,
      activeNickname: 'Rina',
    );
    expect(res.kind, WakeMatchKind.commandWithWake);
    expect(res.remainingCommand, 'dimana Indomaret terdekat?');

    final res2 = WakeWordMatcher.match(
      'Furina semangatin aku dong',
      profile: BuddyVoiceProfile.furina,
      activeNickname: 'Rina',
    );
    expect(res2.kind, WakeMatchKind.commandWithWake);
    expect(res2.remainingCommand, 'semangatin aku dong');
  });

  test('Unrelated cabin conversation without wake-word is ignored', () {
    final res = WakeWordMatcher.match(
      'Belok kiri habis lampu merah depan',
      profile: BuddyVoiceProfile.furina,
      activeNickname: 'Rina',
    );
    expect(res.kind, WakeMatchKind.none);
  });

  test('Verbal cancel phrases ("gjd", "gak jadi", "batal", "never mind") trigger 0-token cancel', () {
    for (final phrase in [
      'gjd',
      'Eh gjd deh',
      'gak jadi',
      'ah ga jadi rina maaf ya',
      'nggak usah deh',
      'batal',
      'lupain aja',
      'never mind',
      'forget it',
    ]) {
      expect(
        WakeWordMatcher.isCancelIntent(
          phrase,
          profile: BuddyVoiceProfile.furina,
          activeNickname: 'Rina',
        ),
        isTrue,
        reason: 'Expected cancel intent on: $phrase',
      );
    }

    final withWake = WakeWordMatcher.match(
      'Oi Rina eh gjd deh',
      profile: BuddyVoiceProfile.furina,
      activeNickname: 'Rina',
    );
    expect(withWake.kind, WakeMatchKind.cancel);

    // Pastikan pertanyaan nyata yang mengandung kata "jadi" atau "batal" tidak salah dibatalkan
    for (final validQuestion in [
      'Kalau tidak jadi hujan kita lewat tol mana?',
      'Cara batalkan tiket kereta gimana ya?',
    ]) {
      expect(
        WakeWordMatcher.isCancelIntent(
          validQuestion,
          profile: BuddyVoiceProfile.furina,
          activeNickname: 'Rina',
        ),
        isFalse,
        reason: 'Should not cancel valid question: $validQuestion',
      );
    }
  });

  test('Multi-turn follow-up punchlines work without wake-word while polite sign-offs close cleanly', () {
    // Jawaban tebak-tebakan seperti "sapiderman" tidak dibatalkan dan tidak dianggap sign-off
    expect(
      WakeWordMatcher.isCancelIntent(
        'sapiderman',
        profile: BuddyVoiceProfile.furina,
        activeNickname: 'Rina',
      ),
      isFalse,
    );
    expect(
      WakeWordMatcher.isConversationSignOff(
        'sapiderman',
        profile: BuddyVoiceProfile.furina,
        activeNickname: 'Rina',
      ),
      isFalse,
    );

    // Ucapan penutup sopan dikenali agar Orb menutup sesudah salam penutup Buddy
    for (final signOff in [
      'oke makasih ya Rina',
      'udah cukup dulu makasih',
      'sip terima kasih',
      'udahan dulu ya',
      'bye Rina',
    ]) {
      expect(
        WakeWordMatcher.isConversationSignOff(
          signOff,
          profile: BuddyVoiceProfile.furina,
          activeNickname: 'Rina',
        ),
        isTrue,
        reason: 'Expected sign-off on: $signOff',
      );
    }

    // Pertanyaan lanjutan yang diawali "makasih" tetap lanjut ngobrol (bukan sign-off)
    expect(
      WakeWordMatcher.isConversationSignOff(
        'makasih, kalau SPBU terdekat dimana?',
        profile: BuddyVoiceProfile.furina,
        activeNickname: 'Rina',
      ),
      isFalse,
    );
  });

  test('Yo Jane, Yo John, and Yo Furina wake variants match reliably', () {
    for (final c in ['Yo Jane', 'yo jein', 'Yo Jen', 'yojane']) {
      expect(
        WakeWordMatcher.match(
          c,
          profile: BuddyVoiceProfile.jane,
          activeNickname: 'Jane',
        ).kind,
        WakeMatchKind.wakeOnly,
      );
    }
    for (final c in ['Yo John', 'yo jon', 'yojohn']) {
      expect(
        WakeWordMatcher.match(
          c,
          profile: BuddyVoiceProfile.john,
          activeNickname: 'John',
        ).kind,
        WakeMatchKind.wakeOnly,
      );
    }
    for (final c in ['Yo Furina', 'Yo Rina']) {
      expect(
        WakeWordMatcher.match(
          c,
          profile: BuddyVoiceProfile.furina,
          activeNickname: 'Rina',
        ).kind,
        WakeMatchKind.wakeOnly,
      );
    }
  });
}
