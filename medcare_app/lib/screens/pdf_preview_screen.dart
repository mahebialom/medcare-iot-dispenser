import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../theme/app_colors.dart';

/// Opens the PDF preview as a modal overlay sliding up over whatever
/// screen called it.
///
/// The bottom bar is fully custom, NOT the `printing` package's
/// built-in action row — that default bar renders as bare, unlabeled,
/// flat-gray icons with no visual relationship to the rest of the
/// app. This replaces it with a proper Material 3 button row (Print /
/// Share) styled the same way as the Save/Cancel row in
/// settings_screen.dart, so it actually looks like it belongs to
/// MedCare IoT. Orientation toggle, page-format switch, and debug
/// info (part of the old default bar) are dropped — they added
/// clutter without adding anything most users would ever touch here;
/// Print and Share/Save cover the actions that matter.
Future<void> showPdfPreviewSheet(
  BuildContext context, {
  required AppColors c,
  required Future<Uint8List> Function(PdfPageFormat format) bytesBuilder,
  required String fileName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.90,
      child: Column(
        children: [
          // Slim drag handle — signals "swipe to dismiss."
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: c.muted.withOpacity(0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // ── Header: close (left) · title (center) · actions (right) ──
          SizedBox(
            height: 35,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.close, size: 20, color: c.muted),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                Text('PDF Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: c.ink)),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.print_outlined, size: 20, color: c.primary),
                          tooltip: 'Print',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Printing.layoutPdf(onLayout: bytesBuilder),
                        ),
                        IconButton(
                          icon: Icon(Icons.ios_share, size: 20, color: c.primary),
                          tooltip: 'Share / Save',
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            final bytes = await bytesBuilder(PdfPageFormat.a4);
                            // Generate filename: MedCare_YYMMDD_HHMMSS.pdf
                            final now = DateTime.now();
                            final dateStr =
                                '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
                            final timeStr =
                                '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
                            final generatedFileName = 'MedCare_${dateStr}_${timeStr}.pdf';
                            await Printing.sharePdf(bytes: bytes, filename: generatedFileName);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              // Built-in action bar fully suppressed — only the raw
              // document view remains from the package itself; all
              // actions now live in the header row above.
              child: PdfPreview(
                build: bytesBuilder,
                allowPrinting: false,
                allowSharing: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                actions: const [],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Small floating circular close button — same "translucent pill
/// behind a plain icon" language as _HeaderIcon in app_root.dart,
/// just circular and sized down for overlaying corner content instead
/// of sitting in a header row.



// class _CloseChip extends StatelessWidget {
//   const _CloseChip({required this.c, required this.onTap});
//   final AppColors c;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: onTap,
//         customBorder: const CircleBorder(),
//         child: Container(
//           width: 32,
//           height: 32,
//           alignment: Alignment.center,
//           decoration: BoxDecoration(
//             shape: BoxShape.circle,
//             color: c.ink.withOpacity(0.55),
//           ),
//           child: const Icon(Icons.close, size: 18, color: Colors.white),
//         ),
//       ),
//     );
//   }
// }