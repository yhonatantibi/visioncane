import 'package:flutter_test/flutter_test.dart';
import 'package:visioncane_app/domain/speech_voice.dart';

void main() {
  test('actual Android string zero accepted; network and unknown rejected', () {
    for (final local in ['0', 0, false, 'false', ' FALSE ']) {
      expect(isLocalVoice(local), isTrue);
    }
    for (final remote in ['1', 1, true, 'true', null, '', 'unknown']) {
      expect(isLocalVoice(remote), isFalse);
    }
  });
  test('only installed Hebrew local candidates survive mixed response', () {
    final voices = [
      {'name': 'he-local', 'locale': 'he-IL', 'network_required': '0'},
      {'name': 'remote', 'locale': 'he-IL', 'network_required': '1'},
      {'name': 'iw-local', 'locale': 'iw_IL', 'network_required': false},
      {'name': 'english', 'locale': 'en-US', 'network_required': '0'},
      {'name': 'missing', 'locale': 'he-IL', 'network_required': '0', 'features': 'notInstalled'},
      {'name': 'unknown', 'locale': 'he-IL'},
      null,
    ];
    expect(localHebrewVoices(voices, android: true).map((v) => v['name']), ['he-local', 'iw-local']);
    expect(localHebrewVoices(null, android: true), isEmpty);
  });
  test('iOS voice need not contain Android network flag', () {
    expect(localHebrewVoices([{'name': 'Carmit', 'locale': 'he-IL'}], android: false), hasLength(1));
  });
}
