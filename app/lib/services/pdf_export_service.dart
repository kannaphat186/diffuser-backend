import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/service_log_model.dart';

class _PdfFonts {
  const _PdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

class PdfExportService {
  PdfExportService._();

  // Nullable so a failed load can be retried on the next export attempt.
  static Future<_PdfFonts>? _fontCache;

  static Future<_PdfFonts> _loadFonts() {
    _fontCache ??= _loadFontsImpl().catchError((Object e) {
      // Clear the cache so the next export attempt will retry font loading
      // instead of permanently failing for the lifetime of the app.
      _fontCache = null;
      // ignore: only_throw_errors
      throw e;
    });
    return _fontCache!;
  }

  static Future<_PdfFonts> _loadFontsImpl() async {
    // Use the full Variable Font (217 KB) which covers the complete Thai Unicode
    // range. The two individual files (Regular/Bold) are 37 KB subsets that
    // miss many Thai glyphs and produce hollow-box rendering in PDFs.
    final varData = await rootBundle
        .load('assets/fonts/NotoSansThai-VariableFont_wdth,wght.ttf');

    if (varData.lengthInBytes < 100000) {
      throw StateError(
        'Thai font file is too small (${varData.lengthInBytes} bytes). '
        'Expected the full Variable Font (≥200 KB). '
        'Replace assets/fonts/NotoSansThai-VariableFont_wdth,wght.ttf '
        'with the complete font from fonts.google.com/noto.',
      );
    }

    final font = pw.Font.ttf(varData);
    return _PdfFonts(regular: font, bold: font);
  }

  static String _safeText(String? value, {String fallback = '-'}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return fallback;
    return text
        .replaceAll('\u0000', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }

  static String _fmtDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = dt.year.toString();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$dd/$mm/$yy $hh:$mi';
    } catch (_) {
      return isoDate;
    }
  }

  static Future<Uint8List> _buildPdfBytes({
    required List<ServiceLogModel> logs,
    String? customerName,
  }) async {
    final fonts = await _loadFonts();
    final font = fonts.regular;
    final fontBold = fonts.bold;
    final pdf = pw.Document();
    final now = DateTime.now();
    final generated = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final baseStyle = pw.TextStyle(
      font: font,
      fontSize: 8,
      fontFallback: [fontBold],
    );
    final boldStyle = pw.TextStyle(
      font: fontBold,
      fontSize: 9,
      fontFallback: [font],
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold, italic: font, boldItalic: fontBold),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Scent & Sense Service Report',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 18,
                fontFallback: [fontBold, font],
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              customerName?.isNotEmpty == true
                  ? 'Customer: ${_safeText(customerName)}'
                  : 'All customers',
              style: pw.TextStyle(font: font, fontFallback: [font]),
            ),
            pw.Text(
              'Generated: $generated',
              style: pw.TextStyle(font: font, fontFallback: [font]),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.blueGrey300),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: pw.TextStyle(
              font: font,
              fontSize: 9,
              fontFallback: [font],
            ),
          ),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Type',
              'Device',
              'Customer',
              'Description',
              'Technician',
            ],
            data: logs.map((log) => [
              _fmtDate(log.createdAt),
              _safeText(log.typeDisplayEn),
              _safeText(
                log.deviceName.isNotEmpty ? log.deviceName : log.deviceSerial,
              ),
              _safeText(log.customerName),
              _safeText(log.description, fallback: '-'),
              _safeText(log.technicianName),
            ]).toList(),
            headerStyle: boldStyle.copyWith(
              color: PdfColors.white,
            ),
            cellStyle: baseStyle,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(6),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> exportAndShare({
    required List<ServiceLogModel> logs,
    String? customerName,
  }) async {
    final bytes = await _buildPdfBytes(logs: logs, customerName: customerName);
    final name = 'service_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: name);
  }

  static Future<String> exportToFile({
    required List<ServiceLogModel> logs,
    String? customerName,
  }) async {
    final bytes = await _buildPdfBytes(logs: logs, customerName: customerName);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/service_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
