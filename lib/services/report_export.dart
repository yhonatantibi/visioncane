import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Only opens the OS chooser after a tap. Never chooses a recipient or sends.
Future<void> shareReport(BuildContext context, String json, String kind) async {
  try {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final root = await getTemporaryDirectory();
    final folder = Directory('${root.path}/visioncane-exports');
    await folder.create(recursive: true);
    // Keep a bounded set of exports, and never touch another app/cache folder.
    final old = await folder.list().where((f) => f is File).cast<File>().toList();
    for (final file in old) {
      if (DateTime.now().difference(await file.lastModified()).inDays >= 1) await file.delete();
    }
    final file = File('${folder.path}/VisionCane-$kind-${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json, encoding: utf8, flush: true);
    if (!context.mounted) return;
    await SharePlus.instance.share(ShareParams(
      title: 'דוח VisionCane', files: [XFile(file.path, mimeType: 'application/json')],
      sharePositionOrigin: origin,
    ));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('פתיחת השיתוף נכשלה. אפשר להעתיק את הסיכום במקום.')));
  }
}
