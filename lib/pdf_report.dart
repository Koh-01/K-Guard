import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'incident_categories.dart';
import 'location_service.dart';
import 'models.dart';

/// Everything the PDF needs, gathered on the main isolate (the PDF is built in a background isolate).
class PdfReportInput {
  final String siteName;
  final int year;
  final int month;
  final String sentBy;
  final List<String> checkpointNames;
  final List<CheckinLog> logs; // newest first
  final List<Incident> incidents; // newest first
  final List<RejectedCheckin> rejected; // newest first
  final Uint8List? cjkFont;

  PdfReportInput({
    required this.siteName,
    required this.year,
    required this.month,
    required this.sentBy,
    required this.checkpointNames,
    required this.logs,
    required this.incidents,
    this.rejected = const [],
    this.cjkFont,
  });
}

/// Brand shown as a small watermark in the PDF footer.
const watermarkText = 'KTech Solution';

/// Telegram bots can upload up to 50 MB.
const _maxPdfBytes = 45 * 1024 * 1024;

/// System fonts that contain Chinese glyphs as TrueType (the PDF library can't read .ttc/.otf).
const _cjkFontCandidates = [
  '/system/fonts/DroidSansChinese.ttf',
  '/system/fonts/NotoSansSC-Regular.ttf',
  '/system/fonts/DroidSansFallback.ttf',
  '/system/fonts/DroidSansFallbackFull.ttf',
  '/system/fonts/MiLanProVF.ttf',
  '/system/fonts/HarmonyOSHans.ttf',
];

/// Loads a Chinese-capable system font so Chinese guard / checkpoint names render in the PDF.
Future<Uint8List?> loadCjkFont() async {
  for (final path in _cjkFontCandidates) {
    final f = File(path);
    try {
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
  }
  return null;
}

/// Builds the monthly PDF report. Photos are downscaled; if the result is still too big for
/// Telegram, it is rebuilt with smaller photos.
Future<Uint8List> buildPdfReport(PdfReportInput input) => Isolate.run(() async {
      var bytes = await _build(input, maxPx: 900, quality: 70);
      if (bytes.length > _maxPdfBytes) {
        bytes = await _build(input, maxPx: 560, quality: 55);
      }
      if (bytes.length > _maxPdfBytes) {
        bytes = await _build(input, maxPx: 360, quality: 45);
      }
      return bytes;
    });

final _green = PdfColor.fromHex('#2E7D32');
final _red = PdfColor.fromHex('#C62828');
final _grey = PdfColor.fromHex('#757575');
final _headerBg = PdfColor.fromHex('#E8EAF6');
final _indigo = PdfColor.fromHex('#283593');

Future<Uint8List> _build(PdfReportInput input,
    {required int maxPx, required int quality}) async {
  final cjk = input.cjkFont == null
      ? null
      : pw.Font.ttf(ByteData.sublistView(input.cjkFont!));
  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    fontFallback: [if (cjk != null) cjk],
  );

  final dateFmt = DateFormat('yyyy-MM-dd');
  final timeFmt = DateFormat('HH:mm');
  final monthTitle =
      DateFormat('MMMM yyyy').format(DateTime(input.year, input.month));
  final logs = input.logs.reversed.toList(); // oldest first
  final incidents = input.incidents.reversed.toList();

  // ---- photos (resized once, reused) ----
  final photoCache = <String, pw.MemoryImage?>{};
  Future<pw.MemoryImage?> photo(String? path) async {
    if (path == null) return null;
    if (photoCache.containsKey(path)) return photoCache[path];
    pw.MemoryImage? result;
    try {
      final decoded = img.decodeImage(await File(path).readAsBytes());
      if (decoded != null) {
        var im = img.bakeOrientation(decoded);
        if (im.width > maxPx || im.height > maxPx) {
          im = im.width >= im.height
              ? img.copyResize(im,
                  width: maxPx, interpolation: img.Interpolation.average)
              : img.copyResize(im,
                  height: maxPx, interpolation: img.Interpolation.average);
        }
        result = pw.MemoryImage(img.encodeJpg(im, quality: quality));
      }
    } catch (_) {}
    return photoCache[path] = result;
  }

  // ---- statistics ----
  final perCheckpoint = {for (final n in input.checkpointNames) n: 0};
  final perGuard = <String, int>{};
  var unknown = 0;
  for (final l in logs) {
    if (l.known) {
      perCheckpoint[l.checkpointName] =
          (perCheckpoint[l.checkpointName] ?? 0) + 1;
    } else {
      unknown++;
    }
    perGuard[l.guardName] = (perGuard[l.guardName] ?? 0) + 1;
  }
  final missedCheckpoints = perCheckpoint.entries
      .where((e) => e.value == 0)
      .map((e) => e.key)
      .toList();
  final required = logs.where((l) => l.photoRequired).toList();
  final withPhoto = logs.where((l) => l.photoPath != null).toList();
  final missingPhotos = required.where((l) => l.photoMissing).length;
  final rejected = input.rejected.reversed.toList(); // oldest first
  final gpsProblems = logs.where((l) => l.gpsProblem).length + rejected.length;

  // ---- widgets ----
  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: _indigo)),
      );

  pw.Widget stat(String label, String value, {PdfColor? color}) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
              color: _headerBg, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: color)),
                pw.SizedBox(height: 2),
                pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _grey)),
              ]),
        ),
      );

  pw.Widget countTable(String title, Map<String, int> counts) =>
      pw.TableHelper.fromTextArray(
        headers: [title, 'Check-ins'],
        data: [
          for (final e in counts.entries) [e.key, '${e.value}']
        ],
        headerStyle:
            const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        headerDecoration: pw.BoxDecoration(color: _headerBg),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {1: pw.Alignment.centerRight},
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1)
        },
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      );

  pw.Widget cell(String text, {PdfColor? color, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 8.5,
                color: color,
                fontWeight: bold ? pw.FontWeight.bold : null)),
      );

  pw.Widget gpsCell(CheckinLog l) {
    final text = LocationService.label(l.gpsStatus, l.distanceM);
    if (text.isEmpty) return cell('-', color: _grey);
    return l.gpsProblem
        ? cell(text, color: _red, bold: true)
        : cell(text, color: l.gpsStatus == 'ok' ? _green : _grey);
  }

  final logTable = pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: {
      0: const pw.FixedColumnWidth(58),
      1: const pw.FixedColumnWidth(34),
      2: const pw.FlexColumnWidth(3),
      3: const pw.FlexColumnWidth(2),
      4: const pw.FixedColumnWidth(56),
      5: const pw.FixedColumnWidth(44),
      6: const pw.FixedColumnWidth(74),
    },
    children: [
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: _headerBg),
        children: [
          for (final h in [
            'Date',
            'Time',
            'Checkpoint',
            'Guard',
            'Status',
            'Photo',
            'GPS'
          ])
            cell(h, bold: true),
        ],
      ),
      for (final l in logs)
        pw.TableRow(children: [
          cell(dateFmt.format(l.time)),
          cell(timeFmt.format(l.time)),
          cell(l.checkpointName),
          cell(l.guardName),
          l.known
              ? cell('OK', color: _green)
              : cell('Unregistered', color: _red),
          !l.photoRequired
              ? cell('-', color: _grey)
              : l.photoPath != null
                  ? cell('Taken', color: _green)
                  : cell('MISSING', color: _red, bold: true),
          gpsCell(l),
        ]),
    ],
  );

  // Photo proofs: two per row, each row a separate widget so pages break cleanly.
  final photoRows = <pw.Widget>[];
  for (var i = 0; i < withPhoto.length; i += 2) {
    final items = <pw.Widget>[];
    for (final l in withPhoto.skip(i).take(2)) {
      final image = await photo(l.photoPath);
      items.add(pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.all(4),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  height: 190,
                  alignment: pw.Alignment.center,
                  color: PdfColors.grey200,
                  child: image == null
                      ? pw.Text('Photo file not found',
                          style: pw.TextStyle(fontSize: 8, color: _grey))
                      : pw.Image(image, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                    '${dateFmt.format(l.time)} ${timeFmt.format(l.time)} · ${l.checkpointName}',
                    style: const pw.TextStyle(
                        fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                pw.Text(l.guardName,
                    style: pw.TextStyle(fontSize: 8, color: _grey)),
              ]),
        ),
      ));
    }
    if (items.length == 1) items.add(pw.Expanded(child: pw.SizedBox()));
    photoRows.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: items));
  }

  final incidentBlocks = <pw.Widget>[];
  for (final i in incidents) {
    final c = categoryById(i.category);
    final images = <pw.Widget>[];
    for (final p in i.photoPaths) {
      final image = await photo(p);
      if (image != null) {
        images.add(pw.Container(
          width: 160,
          height: 120,
          margin: const pw.EdgeInsets.only(right: 6),
          color: PdfColors.grey200,
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ));
      }
    }
    final evidence = [
      if (i.videoPath != null) 'video',
      if (i.photoPaths.isNotEmpty) '${i.photoPaths.length} photo(s)',
      if (i.voicePath != null) 'voice note',
    ].join(' + ');
    // Inseparable: an incident card is never split across two pages.
    incidentBlocks.add(pw.Inseparable(
        child: pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child:
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          pw.Text(c.label,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: _red)),
          pw.Spacer(),
          pw.Text('${dateFmt.format(i.time)} ${timeFmt.format(i.time)}',
              style: const pw.TextStyle(fontSize: 9)),
        ]),
        pw.SizedBox(height: 3),
        pw.Text(
            'Guard: ${i.guardName}${i.location != null ? '   ·   Location: ${i.location}' : ''}'
            '${evidence.isNotEmpty ? '   ·   Evidence: $evidence' : ''}',
            style: pw.TextStyle(fontSize: 8.5, color: _grey)),
        if (i.description.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(i.description, style: const pw.TextStyle(fontSize: 9)),
        ],
        if (images.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Row(children: images)
        ],
        if (i.videoPath != null || i.voicePath != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
                'Video / voice note was sent to owners on Telegram when reported.',
                style: pw.TextStyle(fontSize: 7.5, color: _grey)),
          ),
      ]),
    )));
  }

  final doc = pw.Document(
      theme: theme, title: '${input.siteName} Patrol Report $monthTitle');
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: theme,
    ),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text('${input.siteName} · Patrol Report · $monthTitle',
                style: pw.TextStyle(fontSize: 8, color: _grey)),
          ),
    footer: (ctx) => pw.Row(children: [
      pw.Text(watermarkText, style: pw.TextStyle(fontSize: 7, color: _grey)),
      pw.Spacer(),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: _grey)),
    ]),
    build: (ctx) => [
      pw.Text(input.siteName,
          style:
              const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.Text('Patrol Report · $monthTitle',
          style: pw.TextStyle(fontSize: 14, color: _indigo)),
      pw.SizedBox(height: 4),
      pw.Text(
          'Generated ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} · ${input.sentBy}',
          style: pw.TextStyle(fontSize: 8, color: _grey)),
      pw.SizedBox(height: 14),
      pw.Row(children: [
        stat('Check-ins', '${logs.length}'),
        stat('Photo proofs',
            '${required.length - missingPhotos} / ${required.length}'),
        stat('Missing photos', '$missingPhotos',
            color: missingPhotos > 0 ? _red : _green),
        stat('Incidents', '${incidents.length}',
            color: incidents.isNotEmpty ? _red : null),
        stat('Unregistered', '$unknown', color: unknown > 0 ? _red : null),
        stat('GPS problems', '$gpsProblems',
            color: gpsProblems > 0 ? _red : null),
      ]),
      if (missedCheckpoints.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
              'Not patrolled this month: ${missedCheckpoints.join(', ')}',
              style: pw.TextStyle(
                  fontSize: 10, color: _red, fontWeight: pw.FontWeight.bold)),
        ),
      heading('Summary'),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: countTable('Checkpoint', perCheckpoint)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: countTable('Guard', perGuard)),
      ]),
      heading('Check-in log'),
      if (logs.isEmpty)
        pw.Text('No check-ins this month.',
            style: const pw.TextStyle(fontSize: 9))
      else
        logTable,
      if (photoRows.isNotEmpty) ...[
        pw.Inseparable(
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              heading('Photo proofs (${withPhoto.length})'),
              photoRows.first,
            ])),
        ...photoRows.skip(1),
      ],
      if (rejected.isNotEmpty) ...[
        heading('Rejected check-ins (GPS): ${rejected.length}'),
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
              'These scans were refused because the phone was not at the checkpoint. '
              'Tap "Map" to see where the phone actually was.',
              style: pw.TextStyle(fontSize: 8, color: _grey)),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FixedColumnWidth(58),
            1: const pw.FixedColumnWidth(34),
            2: const pw.FlexColumnWidth(3),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FixedColumnWidth(90),
            5: const pw.FixedColumnWidth(36),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: _headerBg),
              children: [
                for (final h in [
                  'Date',
                  'Time',
                  'Checkpoint',
                  'Guard',
                  'Reason',
                  'Map'
                ])
                  cell(h, bold: true),
              ],
            ),
            for (final r in rejected)
              pw.TableRow(children: [
                cell(dateFmt.format(r.time)),
                cell(timeFmt.format(r.time)),
                cell(r.checkpointName),
                cell(r.guardName),
                cell(LocationService.rejectReason(r.reason, r.distanceM),
                    color: _red, bold: r.reason != 'none'),
                r.mapsLink == null
                    ? cell('-', color: _grey)
                    : pw.UrlLink(
                        destination: r.mapsLink!,
                        child: cell('Map', color: PdfColors.blue700),
                      ),
              ]),
          ],
        ),
      ],
      if (incidentBlocks.isNotEmpty) ...[
        pw.Inseparable(
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              heading('Incidents (${incidents.length})'),
              incidentBlocks.first,
            ])),
        ...incidentBlocks.skip(1),
      ],
    ],
  ));
  return doc.save();
}
