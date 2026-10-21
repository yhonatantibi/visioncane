/// Android flutter_tts 4.2.5 uses STRING "0" / "1", not a boolean.
bool isLocalVoice(Object? value) => value == false || value == 0 ||
    const ['0', 'false'].contains(value?.toString().trim().toLowerCase());

bool isHebrewLocale(Object? value) => const ['he', 'iw', 'heb'].contains(
    value?.toString().trim().toLowerCase().replaceAll('_', '-').split('-').first);

List<Map<String, String>> localHebrewVoices(Object? raw, {required bool android}) {
  if (raw is! List<Object?>) return [];
  final selected = <Map<String, String>>[];
  for (final value in raw) {
    if (value is! Map<Object?, Object?>) continue;
    final name = value['name']?.toString() ?? '';
    final locale = value['locale']?.toString() ?? '';
    final features = value['features']?.toString().toLowerCase() ?? '';
    if (name.isEmpty || !isHebrewLocale(locale) || features.contains('notinstalled') ||
        (android && !isLocalVoice(value['network_required']))) continue;
    selected.add({'name': name, 'locale': locale});
  }
  return selected;
}
