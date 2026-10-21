import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/field_trial.dart';
import '../services/field_trial_store.dart';
import '../services/report_export.dart';

class FieldTrialsScreen extends StatefulWidget {
  const FieldTrialsScreen({super.key, required this.device, required this.mode,
    required this.model, required this.threshold, required this.speechEnabled,
    this.store});
  final String device, mode, model;
  final double threshold;
  final bool speechEnabled;
  final FieldTrialStore? store;
  @override
  State<FieldTrialsScreen> createState() => _FieldTrialsScreenState();
}

class _FieldTrialsScreenState extends State<FieldTrialsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _device = TextEditingController(text: widget.device);
  final _distance = TextEditingController();
  final _note = TextEditingController();
  late final FieldTrialStore _store = widget.store ?? FieldTrialStore();
  List<FieldTrial> _trials = [];
  String _scenario = 'chair', _lighting = 'bright', _sector = 'center';
  TrialOutcome? _outcome;
  bool _offline = false, _busy = true, _loadFailed = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final trials = await _store.load();
      if (mounted) setState(() { _trials = trials; });
    } catch (_) {
      if (mounted) setState(() {
        _loadFailed = true;
        _error = 'לא ניתן לקרוא את הדוח השמור. לא נדרוס אותו. חזור למסך הקודם ונסה שוב.';
      });
    } finally { if (mounted) setState(() { _busy = false; }); }
  }
  @override
  void dispose() { _device.dispose(); _distance.dispose(); _note.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_busy || _loadFailed || !_form.currentState!.validate()) return;
    if (_outcome == null) { setState(() { _error = 'בחר תוצאה לפי מה שראית בניסוי.'; }); return; }
    if (_trials.length >= 500) { setState(() { _error = 'הגעת למגבלת 500 ניסיונות. העתק את הדוח לפני המשך הבדיקות.'; }); return; }
    final trial = FieldTrial(at: DateTime.now(), device: _device.text,
      scenario: _scenario, mode: widget.mode, model: widget.model,
      threshold: widget.threshold, speechEnabled: widget.speechEnabled,
      outcome: _outcome!, lighting: _lighting, sector: _sector,
      distanceMeters: double.tryParse(_distance.text.trim()),
      offlineConfirmed: _offline, note: _note.text);
    final next = [..._trials, trial];
    setState(() { _busy = true; _error = null; });
    try {
      await _store.save(next);
      if (!mounted) return;
      setState(() { _trials = next; _outcome = null; _note.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('הניסיון נשמר במכשיר')));
    } catch (_) {
      if (mounted) setState(() { _error = 'השמירה נכשלה. הנתונים בטופס נשארו; אפשר לנסות שוב.'; });
    } finally { if (mounted) setState(() { _busy = false; }); }
  }

  Future<void> _copy(bool full) async {
    try {
      await Clipboard.setData(ClipboardData(text: full
        ? const JsonEncoder.withIndent('  ').convert(fieldReport(_trials)) : fieldSummary(_trials)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(full
        ? 'JSON הועתק. דוח ארוך כדאי להעביר בקובץ, ולא בהודעת וואטסאפ.' : 'הסיכום הועתק')));
    } catch (_) { if (mounted) setState(() { _error = 'לא ניתן להעתיק כעת. הנתונים השמורים לא השתנו.'; }); }
  }

  Widget _choice(String title, String value, Map<String, String> choices, ValueChanged<String> changed) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField<String>(
      initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: title, border: const OutlineInputBorder()),
      items: choices.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: _busy ? null : (v) { if (v != null) setState(() { changed(v); }); },
    ));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('רישום בדיקת שטח')),
    body: SafeArea(child: Form(key: _form, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('ממלאים אחרי התצפית', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const Text('המצלמה נעצרה כדי למלא דוח. חזור למסך הראשי להפעלת ניסוי נוסף. התוצאות ידניות ונשמרות במכשיר; הסרת האפליקציה עלולה למחוק אותן.'),
      const SizedBox(height: 12),
      Text('הגדרות במסך המצלמה: ${widget.mode} • ${widget.model} • סף ${(widget.threshold * 100).round()}%'),
      const Text('יש לרשום מיד אחרי הניסוי ולפני שינוי ההגדרות. מרחק מוזן לפי מדידה שלך, ואינו מחושב מהמצלמה.'),
      const SizedBox(height: 16),
      TextFormField(controller: _device, maxLength: 80, enabled: !_busy,
        decoration: const InputDecoration(labelText: 'דגם המכשיר', border: OutlineInputBorder()),
        validator: (v) => v == null || v.trim().isEmpty ? 'נדרש דגם כדי להשוות תוצאות' : null),
      _choice('מקרה בדיקה', _scenario, trialScenarios, (v) { _scenario = v; _outcome = null; }),
      _choice('תאורה', _lighting, const {'bright': 'טובה', 'dim': 'חלשה', 'backlit': 'אור מאחור'}, (v) => _lighting = v),
      _choice('מיקום בתמונה', _sector, const {'left': 'שמאל', 'center': 'מרכז', 'right': 'ימין', 'not_applicable': 'לא רלוונטי'}, (v) => _sector = v),
      TextFormField(controller: _distance, enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'מרחק שנמדד במטרים (רשות)', hintText: 'לדוגמה 1.5'),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return null;
          final n = double.tryParse(v.trim());
          return n == null || !n.isFinite || n <= 0 ? 'הזן מספר חיובי, עם נקודה עשרונית' : null;
        }),
      const SizedBox(height: 12),
      Text(_scenario == 'negative_control'
        ? 'בביקורת, הצלחה = לא הוכרז עצם מטרה שאינו שם; תוצאה שגויה = הכרזה כזאת.'
        : widget.mode == 'depth_experiment'
          ? 'בעומק, הצלחה פירושה הבחנה חזותית במכשול מול הרקע בלבד. אין בכך מדידת מרחק או גילוי סכנה.'
          : 'בזיהוי, הצלחה = העצם והצד זוהו כנדרש. החמצה = לא זוהה. תוצאה שגויה = שם או צד שגויים. בבדיקות עצירה ורשת, בודקים את ההתנהגות המתוארת.'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: TrialOutcome.values.map((o) => ChoiceChip(
        label: Text(outcomeLabel(o)), selected: _outcome == o,
        onSelected: _busy ? null : (_) => setState(() { _outcome = o; }),
      )).toList()),
      CheckboxListTile(contentPadding: EdgeInsets.zero, value: _offline,
        title: const Text('אישרתי: מצב טיסה, Wi-Fi כבוי ופתיחה מחדש ללא רשת'),
        onChanged: _busy ? null : (v) => setState(() { _offline = v ?? false; })),
      TextFormField(controller: _note, enabled: !_busy, maxLength: 300, maxLines: 3,
        decoration: const InputDecoration(labelText: 'מה בדיוק קרה? (רשות)', border: OutlineInputBorder())),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      FilledButton.icon(onPressed: _busy || _loadFailed ? null : _save,
        icon: const Icon(Icons.save_outlined), label: Text(_busy ? 'טוען / שומר…' : 'שמירת ניסיון')),
      const Divider(height: 32),
      Text('ניסיונות שמורים: ${_trials.length}', style: const TextStyle(fontSize: 20)),
      const Text('אין כאן ציון דיוק אוטומטי. הסיכום מפריד בין גרסאות, מצבי עבודה ומקרי בדיקה.'),
      OutlinedButton(onPressed: _trials.isEmpty || _busy ? null : () => _copy(false), child: const Text('העתקת סיכום בדיקות')),
      TextButton(onPressed: _trials.isEmpty || _busy ? null : () => _copy(true), child: const Text('העתקת JSON מלא')),
      OutlinedButton.icon(onPressed: _trials.isEmpty || _busy ? null : () => shareReport(
        context, const JsonEncoder.withIndent('  ').convert(fieldReport(_trials)), 'field-trials'),
        icon: const Icon(Icons.share_outlined), label: const Text('שיתוף דוח מלא כקובץ')),
      for (final t in _trials.reversed.take(10)) ListTile(contentPadding: EdgeInsets.zero,
        title: Text('${trialScenarios[t.scenario]} • ${outcomeLabel(t.outcome)}'),
        subtitle: Text('${t.device} • ${t.mode}\n${t.at.toLocal()}${t.note.isEmpty ? '' : '\n${t.note}'}')),
    ]))),
  );
}
