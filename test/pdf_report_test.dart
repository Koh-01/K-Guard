import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nfc_guard/models.dart';
import 'package:nfc_guard/pdf_report.dart';

void main() {
  test('builds a PDF with check-ins, photo proofs and incidents', () async {
    final dir = await Directory.systemTemp.createTemp('pdf_test');
    final photo = File('${dir.path}/p.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 1280, height: 720)));
    final t = DateTime(2026, 8, 3, 21, 5);
    final bytes = await buildPdfReport(PdfReportInput(
      siteName: 'Palm Court',
      year: 2026,
      month: 8,
      sentBy: 'test',
      checkpointNames: ['Gate', 'Roof'],
      logs: [
        for (var i = 0; i < 60; i++)
          CheckinLog(
            tagId: 'T',
            checkpointName: 'Gate',
            guardName: 'KOH',
            time: t.add(Duration(hours: i)),
            known: true,
            photoRequired: i % 10 == 0,
            photoPath: i % 20 == 0 ? photo.path : null,
          ),
      ],
      incidents: [
        Incident(
          time: t,
          guardName: 'KOH',
          category: 'light',
          description: 'Lamp post 3 flickering',
          mediaType: 'photo',
          photoPaths: [photo.path, '/missing/file.jpg'],
        ),
      ],
    ));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000)); // includes the photos
    await dir.delete(recursive: true);
  });
}
