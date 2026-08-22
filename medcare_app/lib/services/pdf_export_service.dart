import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One row of medicine-intake history, already resolved to plain
/// display strings by the caller (HistoryScreen).
class HistoryPdfRow {
  const HistoryPdfRow({
    required this.date,
    required this.time,
    required this.medicine,
    required this.period,
    required this.taken,
  });

  final String date;
  final String time;
  final String medicine;
  final String? period; // null when no schedule match could be inferred
  final bool taken; // true = Taken, false = Missed
}

/// Schedule/period labels may include a leading icon or emoji for
/// on-screen flair (e.g. "🌅 Morning") — the PDF's built-in font can't
/// render most emoji glyphs and shows a blank/missing-character box
/// instead. This strips anything before the first ASCII letter so the
/// PDF shows plain text only ("Morning") — the on-screen label itself
/// is untouched, this only affects what goes into the exported PDF.
String _plainPeriodLabel(String label) {
  final match = RegExp(r'[A-Za-z].*$').firstMatch(label);
  return match?.group(0) ?? label;
}

/// Builds the PDF bytes for a Word-style table: full grid borders on
/// every cell, a plain (unshaded) bold header row, and alternating
/// light-blue/white banded body rows — matching a standard
/// Table-Grid-with-banding look rather than a single solid-color
/// header block.
///
/// [format] is accepted (required by PdfPreview's build-callback
/// signature) but unused — this table's layout doesn't depend on the
/// target page format.
Future<Uint8List> buildHistoryPdfBytes(List<HistoryPdfRow> rows, PdfPageFormat format) async {
  final doc = pw.Document();

  const headers = ['Date', 'Time', 'Medicine', 'Period', 'Status'];
  const headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11);
  const cellStyle = pw.TextStyle(fontSize: 10);
  const cellPadding = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Center(
          child: pw.Text(
            'MedCare IoT Medicine Intake History',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        ),
        pw.Text(
          'Generated ${DateTime.now().toString().split('.').first}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.75),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2),
            1: pw.FlexColumnWidth(1.0),
            2: pw.FlexColumnWidth(1.8),
            3: pw.FlexColumnWidth(1.0),
            4: pw.FlexColumnWidth(1.0),
          },
          children: [
            // Header row — plain white, no fill color, bold text only.
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.white),
              children: headers
                  .map((h) => pw.Padding(padding: cellPadding, child: pw.Text(h, style: headerStyle)))
                  .toList(),
            ),
            // Body rows — alternating white / light-blue banding.
            for (var i = 0; i < rows.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : PdfColors.blue50),
                children: [
                  rows[i].date,
                  rows[i].time,
                  rows[i].medicine,
                  _plainPeriodLabel(rows[i].period ?? '—'),
                  rows[i].taken ? 'Taken' : 'Missed',
                ].map((v) => pw.Padding(padding: cellPadding, child: pw.Text(v, style: cellStyle))).toList(),
              ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}