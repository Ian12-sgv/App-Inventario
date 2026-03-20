import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';

class InventoryExporter {
  static const String _defaultCompanyName = 'By Rossy';
  static const String _logoAsset = 'assets/branding/logo_by.png';

  static Future<void> sharePdfReport({
    required List<Product> products,
    required String generatedBy,
    String? warehouseName,
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildPdfReport(
      products: products,
      generatedBy: generatedBy,
      warehouseName: warehouseName,
      companyName: companyName,
    );

    await Printing.sharePdf(bytes: bytes, filename: _filename('pdf'));
  }

  static Future<void> shareExcelReport({
    required List<Product> products,
    required String generatedBy,
    String? warehouseName,
    Rect? sharePositionOrigin,
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = _buildExcelReport(
      products: products,
      generatedBy: generatedBy,
      warehouseName: warehouseName,
      companyName: companyName,
    );

    await SharePlus.instance.share(
      ShareParams(
        title: 'Inventario',
        subject: 'Reporte de inventario',
        text: 'Reporte de inventario exportado desde $companyName',
        files: [XFile.fromData(bytes, mimeType: 'application/vnd.ms-excel')],
        fileNameOverrides: [_filename('xls')],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static Future<Uint8List> _buildPdfReport({
    required List<Product> products,
    required String generatedBy,
    required String? warehouseName,
    required String companyName,
  }) async {
    final sorted = _sortedProducts(products);
    final totalCost = _totalCost(sorted);
    final totalRetail = _totalRetail(sorted);
    final generatedAt = DateTime.now();
    final dtFmt = DateFormat('dd/MM/yyyy hh:mm a', 'es');
    final logo = await _loadLogo();

    final doc = pw.Document();
    final headers = <String>[
      'Nombre',
      'Linea',
      'Sub linea',
      'Categoria',
      'Sub categoria',
      'Cant.',
      'Costo unitario',
      'Precio unitario',
      'Costo inventario',
      'Precio inventario',
    ];
    final rows = sorted
        .map(
          (product) => [
            product.name.trim(),
            _fallback(product.line),
            _fallback(product.subLine),
            _fallback(product.category),
            _fallback(product.subCategory),
            _qty(product.stock),
            _money(product.costUsd),
            _money(product.priceRetailUsd),
            _money(product.costUsd * product.stock),
            _money(product.priceRetailUsd * product.stock),
          ],
        )
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 24),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                companyName,
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 9,
                ),
              ),
              pw.Text(
                'Pagina ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Reporte de inventario',
                    style: pw.TextStyle(
                      fontSize: 23,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Generado por: ${_fallback(generatedBy)}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Bodega: ${_fallback(warehouseName)}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              if (logo != null)
                pw.Container(
                  width: 86,
                  height: 46,
                  alignment: pw.Alignment.centerRight,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F3F4F6'),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Generacion: ${dtFmt.format(generatedAt)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Numero de productos: ${sorted.length}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryCard(
                  label: 'Costo total del inventario',
                  value: _money(totalCost),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryCard(
                  label: 'Precio total del inventario',
                  value: _money(totalRetail),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Resumen de inventario',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            border: pw.TableBorder.all(
              color: PdfColor.fromHex('#D8DEE6'),
              width: 0.45,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#EEF1F5'),
            ),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
            cellStyle: const pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey900,
            ),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 5,
            ),
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(2.1),
              1: pw.FlexColumnWidth(1.15),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.05),
              4: pw.FlexColumnWidth(1.05),
              5: pw.FlexColumnWidth(0.8),
              6: pw.FlexColumnWidth(0.95),
              7: pw.FlexColumnWidth(1.0),
              8: pw.FlexColumnWidth(1.05),
              9: pw.FlexColumnWidth(1.05),
            },
            cellAlignments: const <int, pw.Alignment>{
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
            },
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Uint8List _buildExcelReport({
    required List<Product> products,
    required String generatedBy,
    required String? warehouseName,
    required String companyName,
  }) {
    final sorted = _sortedProducts(products);
    final totalCost = _totalCost(sorted);
    final totalRetail = _totalRetail(sorted);
    final generatedAt = DateTime.now();
    final dtFmt = DateFormat('dd/MM/yyyy hh:mm a', 'es');
    final xml = StringBuffer()
      ..writeln('<?xml version="1.0"?>')
      ..writeln('<?mso-application progid="Excel.Sheet"?>')
      ..writeln(
        '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:o="urn:schemas-microsoft-com:office:office" '
        'xmlns:x="urn:schemas-microsoft-com:office:excel" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">',
      )
      ..writeln('<Styles>')
      ..writeln(
        '<Style ss:ID="Default" ss:Name="Normal">'
        '<Alignment ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="10"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="Title">'
        '<Font ss:FontName="Arial" ss:Size="18" ss:Bold="1"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="MetaLabel">'
        '<Font ss:FontName="Arial" ss:Bold="1"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="MetaStrip">'
        '<Alignment ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/>'
        '<Interior ss:Color="#F3F4F6" ss:Pattern="Solid"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="MetaStripRight">'
        '<Alignment ss:Horizontal="Right" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/>'
        '<Interior ss:Color="#F3F4F6" ss:Pattern="Solid"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SummaryLabel">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/>'
        '<Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SummaryValue">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="16" ss:Bold="1"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SectionTitle">'
        '<Font ss:FontName="Arial" ss:Size="12" ss:Bold="1"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="Header">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/>'
        '<Font ss:FontName="Arial" ss:Bold="1"/>'
        '<Interior ss:Color="#EEF1F5" ss:Pattern="Solid"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="Cell">'
        '<Alignment ss:Vertical="Top" ss:WrapText="1"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="Qty">'
        '<Alignment ss:Horizontal="Right" ss:Vertical="Top"/>'
        '${_xmlBorders()}'
        '<NumberFormat ss:Format="0.###"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="Money">'
        '<Alignment ss:Horizontal="Right" ss:Vertical="Top"/>'
        '${_xmlBorders()}'
        '<NumberFormat ss:Format="\\\$#,##0.00"/>'
        '</Style>',
      )
      ..writeln('</Styles>')
      ..writeln('<Worksheet ss:Name="Reporte"><Table>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="165"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="92"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="96"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="96"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="96"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="64"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="90"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="92"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="96"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="96"/>');

    _xmlRow(xml, [
      _xmlMergedStringCell(
        'Reporte de inventario',
        styleId: 'Title',
        mergeAcross: 9,
      ),
    ]);
    _xmlRow(xml, const []);
    _xmlRow(xml, [
      _xmlStringCell('Empresa', styleId: 'MetaLabel'),
      _xmlMergedStringCell(companyName, mergeAcross: 3),
      _xmlStringCell('Generado por', styleId: 'MetaLabel'),
      _xmlMergedStringCell(_fallback(generatedBy), mergeAcross: 3),
    ]);
    _xmlRow(xml, [
      _xmlStringCell('Bodega', styleId: 'MetaLabel'),
      _xmlMergedStringCell(_fallback(warehouseName), mergeAcross: 3),
      _xmlMergedStringCell('', mergeAcross: 5),
    ]);
    _xmlRow(xml, [
      _xmlMergedStringCell(
        'Generacion: ${dtFmt.format(generatedAt)}',
        styleId: 'MetaStrip',
        mergeAcross: 4,
      ),
      _xmlMergedStringCell(
        'Numero de productos: ${sorted.length}',
        styleId: 'MetaStripRight',
        mergeAcross: 4,
      ),
    ]);
    _xmlRow(xml, const []);
    _xmlRow(xml, [
      _xmlMergedStringCell(
        'Costo total del inventario',
        styleId: 'SummaryLabel',
        mergeAcross: 4,
      ),
      _xmlMergedStringCell(
        'Precio total del inventario',
        styleId: 'SummaryLabel',
        mergeAcross: 4,
      ),
    ]);
    _xmlRow(xml, [
      _xmlMergedStringCell(
        _money(totalCost),
        styleId: 'SummaryValue',
        mergeAcross: 4,
      ),
      _xmlMergedStringCell(
        _money(totalRetail),
        styleId: 'SummaryValue',
        mergeAcross: 4,
      ),
    ]);
    _xmlRow(xml, const []);
    _xmlRow(xml, [
      _xmlMergedStringCell(
        'Resumen de inventario',
        styleId: 'SectionTitle',
        mergeAcross: 9,
      ),
    ]);
    _xmlRow(xml, const []);

    _xmlRow(xml, [
      _xmlStringCell('Nombre', styleId: 'Header'),
      _xmlStringCell('Linea', styleId: 'Header'),
      _xmlStringCell('Sub linea', styleId: 'Header'),
      _xmlStringCell('Categoria', styleId: 'Header'),
      _xmlStringCell('Sub categoria', styleId: 'Header'),
      _xmlStringCell('Cantidad', styleId: 'Header'),
      _xmlStringCell('Costo unitario', styleId: 'Header'),
      _xmlStringCell('Precio unitario', styleId: 'Header'),
      _xmlStringCell('Costo inventario', styleId: 'Header'),
      _xmlStringCell('Precio inventario', styleId: 'Header'),
    ]);

    for (final product in sorted) {
      _xmlRow(xml, [
        _xmlStringCell(product.name.trim(), styleId: 'Cell'),
        _xmlStringCell(_fallback(product.line), styleId: 'Cell'),
        _xmlStringCell(_fallback(product.subLine), styleId: 'Cell'),
        _xmlStringCell(_fallback(product.category), styleId: 'Cell'),
        _xmlStringCell(_fallback(product.subCategory), styleId: 'Cell'),
        _xmlNumberCell(product.stock, styleId: 'Qty'),
        _xmlNumberCell(product.costUsd, styleId: 'Money'),
        _xmlNumberCell(product.priceRetailUsd, styleId: 'Money'),
        _xmlNumberCell(product.costUsd * product.stock, styleId: 'Money'),
        _xmlNumberCell(
          product.priceRetailUsd * product.stock,
          styleId: 'Money',
        ),
      ]);
    }

    xml
      ..writeln('</Table></Worksheet>')
      ..writeln('</Workbook>');

    return Uint8List.fromList(utf8.encode(xml.toString()));
  }

  static Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final data = await rootBundle.load(_logoAsset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static List<Product> _sortedProducts(List<Product> input) {
    final list = List<Product>.of(input);
    list.sort((a, b) {
      int compare(String left, String right) =>
          left.toLowerCase().compareTo(right.toLowerCase());

      final line = compare(a.line, b.line);
      if (line != 0) return line;

      final subLine = compare(a.subLine, b.subLine);
      if (subLine != 0) return subLine;

      final category = compare(a.category, b.category);
      if (category != 0) return category;

      final subCategory = compare(a.subCategory, b.subCategory);
      if (subCategory != 0) return subCategory;

      final name = compare(a.name, b.name);
      if (name != 0) return name;

      return compare(a.reference, b.reference);
    });
    return list;
  }

  static double _totalCost(List<Product> products) => products.fold(
    0,
    (sum, product) => sum + (product.costUsd * product.stock),
  );

  static double _totalRetail(List<Product> products) => products.fold(
    0,
    (sum, product) => sum + (product.priceRetailUsd * product.stock),
  );

  static String _filename(String extension) {
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'inventario_$stamp.$extension';
  }

  static String _fallback(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? 'Sin configurar' : text;
  }

  static String _money(num value) {
    final number = value.toDouble();
    if ((number % 1).abs() < 0.000001) {
      return '\$${number.toStringAsFixed(0)}';
    }
    return '\$${number.toStringAsFixed(2)}';
  }

  static String _qty(num value) {
    final number = value.toDouble();
    if ((number % 1).abs() < 0.000001) {
      return number.toStringAsFixed(0);
    }
    return number
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static pw.Widget _summaryCard({
    required String label,
    required String value,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#D9DEE5')),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static String _xmlBorders() {
    return '<Borders>'
        '<Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D8DEE6"/>'
        '<Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D8DEE6"/>'
        '<Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D8DEE6"/>'
        '<Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D8DEE6"/>'
        '</Borders>';
  }

  static void _xmlRow(StringBuffer buffer, List<String> cells) {
    buffer.write('<Row>');
    for (final cell in cells) {
      buffer.write(cell);
    }
    buffer.writeln('</Row>');
  }

  static String _xmlStringCell(String value, {String? styleId}) {
    final style = styleId == null ? '' : ' ss:StyleID="$styleId"';
    return '<Cell$style><Data ss:Type="String">${_escapeXml(value)}</Data></Cell>';
  }

  static String _xmlMergedStringCell(
    String value, {
    String? styleId,
    int mergeAcross = 0,
  }) {
    final style = styleId == null ? '' : ' ss:StyleID="$styleId"';
    final merge = mergeAcross > 0 ? ' ss:MergeAcross="$mergeAcross"' : '';
    return '<Cell$style$merge><Data ss:Type="String">${_escapeXml(value)}</Data></Cell>';
  }

  static String _xmlNumberCell(num value, {String? styleId}) {
    final style = styleId == null ? '' : ' ss:StyleID="$styleId"';
    final normalized = value is int
        ? value.toString()
        : value
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
    return '<Cell$style><Data ss:Type="Number">$normalized</Data></Cell>';
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
