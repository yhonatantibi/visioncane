import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/field_trial.dart';

class FieldTrialStore {
  FieldTrialStore({this.directory});
  final Directory? directory;
  Future<Directory> _root() async => directory ?? await getApplicationDocumentsDirectory();

  Future<List<FieldTrial>> load() async {
    final root = await _root();
    final file = File('${root.path}/field-trials.json');
    if (!await file.exists()) return [];
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (json['schema_version'] != 1) throw const FormatException('Unsupported trial schema');
    return (json['trials'] as List).map((e) => FieldTrial.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<FieldTrial> trials) async {
    final root = await _root();
    await root.create(recursive: true);
    final temporary = File('${root.path}/field-trials.pending');
    await temporary.writeAsString(jsonEncode(fieldReport(trials)), flush: true);
    await temporary.rename('${root.path}/field-trials.json');
  }
}
