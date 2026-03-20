import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../models/txn.dart';
import '../state/app_state.dart';

class BalanceReportExporter {
  static const String _defaultCompanyName = 'By Rossy';
  static const String _logoAsset = 'assets/branding/logo_by.png';
  static const String _fontRegularAsset = 'assets/fonts/Arial.ttf';
  static const String _fontBoldAsset = 'assets/fonts/Arial Bold.ttf';
  static const PdfColor _border = PdfColor.fromInt(0xFFDDE2E8);
  static const PdfColor _muted = PdfColor.fromInt(0xFF7A828D);
  static const PdfColor _title = PdfColor.fromInt(0xFF2D3137);
  static const PdfColor _green = PdfColor.fromInt(0xFF1F9D55);
  static const PdfColor _footerBg = PdfColor.fromInt(0xFF24364A);

  static Future<void> shareDailyPdfReport({
    required AppState state,
    required List<Txn> txns,
    required DateTime day,
    String companyName = _defaultCompanyName,
  }) async {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final rows = await _buildRows(state: state, txns: txns);
    final summary = _buildSummary(rows);
    final bytes = await _buildPdfReport(
      state: state,
      day: normalizedDay,
      rows: rows,
      summary: summary,
      companyName: companyName,
    );

    await Printing.sharePdf(bytes: bytes, filename: _filename(normalizedDay));
  }

  static Future<void> shareDailyExcelReport({
    required AppState state,
    required List<Txn> txns,
    required DateTime day,
    Rect? sharePositionOrigin,
    String companyName = _defaultCompanyName,
  }) async {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final rows = await _buildRows(state: state, txns: txns);
    final summary = _buildSummary(rows);
    final bytes = _buildExcelReport(
      state: state,
      day: normalizedDay,
      rows: rows,
      summary: summary,
      companyName: companyName,
    );

    await SharePlus.instance.share(
      ShareParams(
        title: 'Balance',
        subject: 'Reporte de balance',
        text: 'Reporte diario de balance exportado desde $companyName',
        files: [XFile.fromData(bytes, mimeType: 'application/vnd.ms-excel')],
        fileNameOverrides: [_filename(normalizedDay, extension: 'xls')],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static Future<List<_BalanceReportRow>> _buildRows({
    required AppState state,
    required List<Txn> txns,
  }) async {
    final sorted = [...txns]
      ..sort((a, b) {
        final byWhen = a.when.compareTo(b.when);
        if (byWhen != 0) return byWhen;
        return a.id.compareTo(b.id);
      });

    final saleDescriptionCache = <String, String>{};
    final expenseDescriptionCache = <String, String>{};
    final dateFmt = DateFormat('dd/MM/yyyy', 'es');
    final rows = <_BalanceReportRow>[];

    for (final txn in sorted) {
      final sale = txn.sale ?? const <String, dynamic>{};
      final expense = txn.expense ?? const <String, dynamic>{};
      final saleId = (txn.saleId ?? sale['id'] ?? '').toString().trim();
      final expenseId = (txn.expenseId ?? expense['id'] ?? '')
          .toString()
          .trim();

      String description;
      if (saleId.isNotEmpty && _saleLooksInventory(sale)) {
        description = saleDescriptionCache.putIfAbsent(saleId, () => 'loading');
        if (description == 'loading') {
          description = await _saleDescription(state: state, sale: sale);
          saleDescriptionCache[saleId] = description;
        }
      } else if (expenseId.isNotEmpty || expense.isNotEmpty) {
        final cacheKey = expenseId.isEmpty ? txn.id : expenseId;
        description = expenseDescriptionCache.putIfAbsent(
          cacheKey,
          () => 'loading',
        );
        if (description == 'loading') {
          description = await _expenseDescription(
            state: state,
            expense: expense,
            expenseId: expenseId,
          );
          expenseDescriptionCache[cacheKey] = description;
        }
      } else {
        description = '';
      }

      description = description.trim().isEmpty
          ? _fallback(
              _firstText([
                txn.note,
                sale['description'],
                sale['concept'],
                expense['description'],
                expense['concept'],
              ]),
            )
          : description;

      rows.add(
        _BalanceReportRow(
          section: txn.type == 'income'
              ? _BalanceReportSection.sales
              : _BalanceReportSection.expenses,
          date: dateFmt.format(txn.when),
          type: _typeLabel(txn),
          seller: _sellerLabel(state, txn),
          description: description,
          contact: _contactLabel(txn),
          status: _statusLabel(txn),
          paymentMethod: _fallback(txn.paymentMethod),
          value: txn.amount,
          kind: (txn.kind ?? '').toString().trim().toUpperCase(),
        ),
      );
    }

    return rows;
  }

  static _BalanceSummary _buildSummary(List<_BalanceReportRow> rows) {
    double income = 0;
    double salesCredits = 0;
    double expenseCredits = 0;
    double expenses = 0;

    for (final row in rows) {
      final isAbono = row.kind == 'ABONO';
      if (row.section == _BalanceReportSection.sales) {
        if (isAbono) {
          salesCredits += row.value;
        } else {
          income += row.value;
        }
        continue;
      }
      if (isAbono) {
        expenseCredits += row.value;
      } else {
        expenses += row.value;
      }
    }

    return _BalanceSummary(
      income: income,
      salesCredits: salesCredits,
      expenseCredits: expenseCredits,
      expenses: expenses,
      total: income + salesCredits - expenseCredits - expenses,
    );
  }

  static Future<Uint8List> _buildPdfReport({
    required AppState state,
    required DateTime day,
    required List<_BalanceReportRow> rows,
    required _BalanceSummary summary,
    required String companyName,
  }) async {
    final salesRows = rows
        .where((row) => row.section == _BalanceReportSection.sales)
        .toList();
    final expenseRows = rows
        .where((row) => row.section == _BalanceReportSection.expenses)
        .toList();
    final generatedAt = DateTime.now();
    final dayFmt = DateFormat('dd/MM/yyyy', 'es');
    final generatedFmt = DateFormat('dd/MM/yyyy hh:mm a', 'es');
    final logo = await _loadLogo();
    final baseFont = await _loadFont(_fontRegularAsset);
    final boldFont = await _loadFont(_fontBoldAsset);
    final theme = baseFont == null
        ? null
        : pw.ThemeData.withFont(base: baseFont, bold: boldFont ?? baseFont);
    final doc = theme == null ? pw.Document() : pw.Document(theme: theme);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 18),
        footer: (_) => _footer(companyName: companyName, logo: logo),
        build: (context) => [
          _header(
            companyName: companyName,
            generatedBy: _fallback(state.userDisplayName),
            day: day,
            logo: logo,
          ),
          pw.SizedBox(height: 14),
          _metaStrip(
            fromDate: dayFmt.format(day),
            toDate: dayFmt.format(day),
            generatedAt: generatedFmt.format(generatedAt),
            totalTransactions: rows.length,
          ),
          pw.SizedBox(height: 8),
          _summaryStrip(summary),
          pw.SizedBox(height: 16),
          _section(
            title: 'Ventas y abonos a ventas',
            rows: salesRows,
            emptyLabel: 'No hay movimientos de ingresos en esta fecha.',
          ),
          pw.SizedBox(height: 16),
          _section(
            title: 'Gastos y abonos a gastos',
            rows: expenseRows,
            emptyLabel: 'No hay movimientos de egresos en esta fecha.',
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Uint8List _buildExcelReport({
    required AppState state,
    required DateTime day,
    required List<_BalanceReportRow> rows,
    required _BalanceSummary summary,
    required String companyName,
  }) {
    final salesRows = rows
        .where((row) => row.section == _BalanceReportSection.sales)
        .toList();
    final expenseRows = rows
        .where((row) => row.section == _BalanceReportSection.expenses)
        .toList();
    final generatedAt = DateTime.now();
    final dtFmt = DateFormat('dd/MM/yyyy hh:mm a', 'es');
    final dayFmt = DateFormat('dd/MM/yyyy', 'es');
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
        '<Font ss:FontName="Arial" ss:Size="16" ss:Bold="1"/>'
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
        '<Interior ss:Color="#EDEFF2" ss:Pattern="Solid"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="MetaStripCenter">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/>'
        '<Interior ss:Color="#EDEFF2" ss:Pattern="Solid"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="MetaStripRight">'
        '<Alignment ss:Horizontal="Right" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/>'
        '<Interior ss:Color="#EDEFF2" ss:Pattern="Solid"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SummaryLead">'
        '<Alignment ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SummaryLabel">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/>'
        '<Interior ss:Color="#F7F8FA" ss:Pattern="Solid"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SummaryValue">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="11" ss:Bold="1"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SummaryValueTotal">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="11" ss:Bold="1" ss:Color="#1F9D55"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SectionTitle">'
        '<Font ss:FontName="Arial" ss:Size="12" ss:Bold="1"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="SectionBadge">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
        '<Font ss:FontName="Arial" ss:Size="9" ss:Bold="1"/>'
        '<Interior ss:Color="#EDEFF2" ss:Pattern="Solid"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="Header">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
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
        '<Style ss:ID="Money">'
        '<Alignment ss:Horizontal="Right" ss:Vertical="Top"/>'
        '${_xmlBorders()}'
        '<NumberFormat ss:Format="\\\$#,##0.00"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="Qty">'
        '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/>'
        '${_xmlBorders()}'
        '<NumberFormat ss:Format="0"/>'
        '</Style>',
      )
      ..writeln(
        '<Style ss:ID="EmptyNotice">'
        '<Alignment ss:Vertical="Center" ss:WrapText="1"/>'
        '<Font ss:FontName="Arial" ss:Italic="1" ss:Color="#7A828D"/>'
        '${_xmlBorders()}'
        '</Style>',
      )
      ..writeln('</Styles>')
      ..writeln('<Worksheet ss:Name="Reporte"><Table>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="75"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="82"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="105"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="275"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="120"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="90"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="105"/>')
      ..writeln('<Column ss:AutoFitWidth="0" ss:Width="82"/>');

    _xmlRow(xml, [
      _xmlMergedStringCell(
        'Reporte de balance',
        styleId: 'Title',
        mergeAcross: 7,
      ),
    ]);
    _xmlRow(xml, const []);
    _xmlRow(xml, [
      _xmlStringCell('Empresa', styleId: 'MetaLabel'),
      _xmlMergedStringCell(companyName, mergeAcross: 2),
      _xmlStringCell('Generado por', styleId: 'MetaLabel'),
      _xmlMergedStringCell(_fallback(state.userDisplayName), mergeAcross: 2),
    ]);
    _xmlRow(xml, [
      _xmlStringCell('Fecha del reporte', styleId: 'MetaLabel'),
      _xmlMergedStringCell(dayFmt.format(day), mergeAcross: 2),
      _xmlStringCell('Generacion', styleId: 'MetaLabel'),
      _xmlMergedStringCell(dtFmt.format(generatedAt), mergeAcross: 2),
    ]);
    _xmlRow(xml, const []);
    _xmlRow(xml, [
      _xmlMergedStringCell(
        'Fecha de reporte: ${dayFmt.format(day)} - ${dayFmt.format(day)}',
        styleId: 'MetaStrip',
        mergeAcross: 2,
      ),
      _xmlMergedStringCell(
        dtFmt.format(generatedAt),
        styleId: 'MetaStripCenter',
        mergeAcross: 2,
      ),
      _xmlMergedStringCell(
        'Numero de transacciones: ${rows.length}',
        styleId: 'MetaStripRight',
        mergeAcross: 1,
      ),
    ]);
    _xmlRow(xml, const []);
    _xmlRow(xml, [
      _xmlMergedStringCell(
        'Ingresos + Abonos ventas - Abonos gastos - Gastos = Utilidad Total',
        styleId: 'SummaryLead',
        mergeAcross: 7,
      ),
    ]);
    _xmlRow(xml, [
      _xmlStringCell('Ingresos', styleId: 'SummaryLabel'),
      _xmlStringCell('Abonos ventas', styleId: 'SummaryLabel'),
      _xmlStringCell('Abonos gastos', styleId: 'SummaryLabel'),
      _xmlStringCell('Gastos', styleId: 'SummaryLabel'),
      _xmlMergedStringCell(
        'Utilidad Total',
        styleId: 'SummaryLabel',
        mergeAcross: 3,
      ),
    ]);
    _xmlRow(xml, [
      _xmlStringCell(_money(summary.income), styleId: 'SummaryValue'),
      _xmlStringCell(_money(summary.salesCredits), styleId: 'SummaryValue'),
      _xmlStringCell(_money(summary.expenseCredits), styleId: 'SummaryValue'),
      _xmlStringCell(_money(summary.expenses), styleId: 'SummaryValue'),
      _xmlMergedStringCell(
        _money(summary.total),
        styleId: 'SummaryValueTotal',
        mergeAcross: 3,
      ),
    ]);
    _xmlRow(xml, const []);
    _xmlSectionHeader(
      xml,
      title: 'Ventas y abonos a ventas',
      transactionCount: salesRows.length,
    );
    _xmlBalanceSheetRows(
      xml,
      rows: salesRows,
      emptyLabel: 'No hay movimientos de ingresos en esta fecha.',
    );
    _xmlRow(xml, const []);
    _xmlSectionHeader(
      xml,
      title: 'Gastos y abonos a gastos',
      transactionCount: expenseRows.length,
    );
    _xmlBalanceSheetRows(
      xml,
      rows: expenseRows,
      emptyLabel: 'No hay movimientos de egresos en esta fecha.',
    );
    xml
      ..writeln('</Table></Worksheet>')
      ..writeln('</Workbook>');

    return Uint8List.fromList(utf8.encode(xml.toString()));
  }

  static pw.Widget _header({
    required String companyName,
    required String generatedBy,
    required DateTime day,
    required pw.MemoryImage? logo,
  }) {
    final dayLabel = DateFormat("dd/MM/yyyy", 'es').format(day);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Reporte de balance',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: _title,
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              companyName,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _title,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generado por: $generatedBy',
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Fecha del reporte: $dayLabel',
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
          ],
        ),
        if (logo != null)
          pw.Container(
            width: 112,
            height: 44,
            alignment: pw.Alignment.centerRight,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
      ],
    );
  }

  static pw.Widget _metaStrip({
    required String fromDate,
    required String toDate,
    required String generatedAt,
    required int totalTransactions,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFEDEFF2),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              'Fecha de reporte: $fromDate - $toDate',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _muted,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              generatedAt,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _title,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              'Numero de transacciones: $totalTransactions',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryStrip(_BalanceSummary summary) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _border, width: 0.7),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: _summaryCell('Ingresos', summary.income)),
          _operatorCell('+'),
          pw.Expanded(
            child: _summaryCell('Abonos ventas', summary.salesCredits),
          ),
          _operatorCell('-'),
          pw.Expanded(
            child: _summaryCell('Abonos gastos', summary.expenseCredits),
          ),
          _operatorCell('-'),
          pw.Expanded(child: _summaryCell('Gastos', summary.expenses)),
          _operatorCell('='),
          pw.Expanded(
            child: _summaryCell(
              'Utilidad Total',
              summary.total,
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryCell(
    String label,
    double value, {
    bool highlight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 7,
              color: _muted,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _money(value),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 10.5,
              color: highlight ? _green : _title,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _operatorCell(String sign) {
    return pw.Container(
      width: 20,
      alignment: pw.Alignment.center,
      child: pw.Text(
        sign,
        style: pw.TextStyle(
          fontSize: 12,
          color: _title,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _section({
    required String title,
    required List<_BalanceReportRow> rows,
    required String emptyLabel,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: _title,
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFEDEFF2),
                borderRadius: pw.BorderRadius.circular(2),
              ),
              child: pw.Text(
                'Numero de transacciones: ${rows.length}',
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: _muted,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        if (rows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
            child: pw.Text(
              emptyLabel,
              style: const pw.TextStyle(fontSize: 8.5, color: _muted),
            ),
          )
        else
          _sectionTable(rows),
      ],
    );
  }

  static pw.Widget _sectionTable(List<_BalanceReportRow> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const [
        'Fecha',
        'Tipo',
        'Vendedor',
        'Descripcion',
        'Contacto',
        'Estado',
        'M. de pago',
        'Valor',
      ],
      data: rows
          .map(
            (row) => [
              row.date,
              row.type,
              row.seller,
              row.description,
              row.contact,
              row.status,
              row.paymentMethod,
              _money(row.value),
            ],
          )
          .toList(),
      border: pw.TableBorder.symmetric(
        inside: const pw.BorderSide(color: _border, width: 0.35),
        outside: const pw.BorderSide(color: _border, width: 0.35),
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
      headerStyle: pw.TextStyle(
        fontSize: 7,
        fontWeight: pw.FontWeight.bold,
        color: _muted,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7.5, color: _title),
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.0),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.25),
        3: pw.FlexColumnWidth(2.35),
        4: pw.FlexColumnWidth(1.0),
        5: pw.FlexColumnWidth(0.8),
        6: pw.FlexColumnWidth(1.0),
        7: pw.FlexColumnWidth(0.7),
      },
      cellAlignments: const <int, pw.Alignment>{7: pw.Alignment.centerRight},
    );
  }

  static pw.Widget _footer({
    required String companyName,
    required pw.MemoryImage? logo,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const pw.BoxDecoration(color: _footerBg),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (logo != null)
                pw.Container(
                  width: 18,
                  height: 18,
                  margin: const pw.EdgeInsets.only(right: 6),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Text(
            'Reporte diario generado desde la app',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 7),
          ),
          pw.Text(
            'Balance',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static Future<String> _saleDescription({
    required AppState state,
    required Map<String, dynamic> sale,
  }) async {
    final docId = (sale['inventoryDocId'] ?? sale['inventory_doc_id'] ?? '')
        .toString()
        .trim();
    if (docId.isEmpty) {
      return _fallback(_firstText([sale['description'], sale['concept']]));
    }
    final rows = await state.getInventoryDocLines(docId);
    return _descriptionFromRows(rows: rows, state: state);
  }

  static Future<String> _expenseDescription({
    required AppState state,
    required Map<String, dynamic> expense,
    required String expenseId,
  }) async {
    final rows = await state.getExpensePurchaseLines(
      expense: expense,
      expenseId: expenseId,
    );
    if (rows.isEmpty) {
      return _fallback(
        _firstText([expense['description'], expense['concept']]),
      );
    }
    return _descriptionFromRows(rows: rows, state: state);
  }

  static String _descriptionFromRows({
    required List<Map<String, dynamic>> rows,
    required AppState state,
  }) {
    final lines = <String>[];
    for (final row in rows) {
      final qty = _qty(row['qty'] ?? row['quantity'] ?? row['cantidad']);
      final product = _resolvedProduct(row: row, state: state);
      final text = _descriptionLine(product: product, qty: qty);
      if (text.isNotEmpty) lines.add(text);
    }
    return lines.isEmpty ? '-' : lines.join('\n');
  }

  static String _descriptionLine({
    required Map<String, dynamic> product,
    required String qty,
  }) {
    final name = _firstText([
      product['description'],
      product['name'],
      product['reference'],
      product['barcode'],
    ]);
    final details = <String>[
      _text(product['line']),
      _text(product['subLine']),
      _text(product['category']),
      _text(product['subCategory']),
    ].where((part) => part.isNotEmpty).toList();

    final prefix = qty.isEmpty ? '' : '$qty ';
    if (details.isEmpty) return '$prefix$name'.trim();
    return '$prefix$name (${details.join(' / ')})'.trim();
  }

  static Map<String, dynamic> _resolvedProduct({
    required Map<String, dynamic> row,
    required AppState state,
  }) {
    final rawProduct = (row['product'] is Map)
        ? (row['product'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final productId =
        (row['productId'] ?? row['product_id'] ?? rawProduct['id'] ?? '')
            .toString()
            .trim();

    Product? match;
    if (productId.isNotEmpty) {
      for (final candidate in state.products) {
        if (candidate.id == productId) {
          match = candidate;
          break;
        }
      }
    }

    return <String, dynamic>{
      'description':
          rawProduct['description'] ??
          rawProduct['name'] ??
          row['description'] ??
          row['name'] ??
          match?.name,
      'reference':
          rawProduct['reference'] ?? row['reference'] ?? match?.reference,
      'barcode': rawProduct['barcode'] ?? row['barcode'] ?? match?.barcode,
      'line': rawProduct['line'] ?? row['line'] ?? row['linea'] ?? match?.line,
      'subLine':
          rawProduct['subLine'] ??
          rawProduct['sub_line'] ??
          row['subLine'] ??
          row['sub_line'] ??
          row['sublinea'] ??
          match?.subLine,
      'category':
          rawProduct['category'] ??
          row['category'] ??
          row['categoria'] ??
          match?.category,
      'subCategory':
          rawProduct['subCategory'] ??
          rawProduct['sub_category'] ??
          row['subCategory'] ??
          row['sub_category'] ??
          row['subcategoria'] ??
          match?.subCategory,
    };
  }

  static String _sellerLabel(AppState state, Txn txn) {
    final entity = txn.sale ?? txn.expense ?? const <String, dynamic>{};
    return _fallback(
      _firstText([
        entity['employeeName'],
        entity['empleado'],
        entity['userName'],
        entity['createdByName'],
        entity['createdBy'],
        entity['user'],
        state.userDisplayName,
      ]),
    );
  }

  static String _contactLabel(Txn txn) {
    final entity = txn.sale ?? txn.expense ?? const <String, dynamic>{};
    return _fallback(
      _firstText([
        entity['contactName'],
        entity['contact'],
        entity['contacto'],
        entity['customerName'],
        entity['customer'],
        entity['clientName'],
        entity['client'],
        entity['cliente'],
        entity['supplierName'],
        entity['supplier'],
        entity['providerName'],
        entity['provider'],
        entity['proveedor'],
      ]),
    );
  }

  static String _statusLabel(Txn txn) {
    final entity = txn.sale ?? txn.expense ?? const <String, dynamic>{};
    final explicit = _firstText([entity['statusLabel'], entity['status']]);
    if (explicit.isNotEmpty) return explicit;

    final kind = (txn.kind ?? '').toString().trim().toUpperCase();
    if (kind == 'DEUDA') return 'Deuda';
    return 'Pagada';
  }

  static String _typeLabel(Txn txn) {
    final kind = (txn.kind ?? '').toString().trim().toUpperCase();
    if (kind == 'ABONO') {
      return txn.type == 'income' ? 'Abono venta' : 'Abono gasto';
    }
    if (txn.type == 'income') {
      return 'Venta';
    }
    if (kind == 'DEUDA') {
      return 'Gasto';
    }
    return 'Gasto';
  }

  static bool _saleLooksInventory(Map<String, dynamic> sale) {
    final rawType =
        sale['saleType'] ?? sale['sale_type'] ?? sale['type'] ?? sale['kind'];
    final saleType = (rawType ?? '').toString().trim().toUpperCase();
    if (saleType.contains('LIBRE')) return false;
    if (saleType.contains('INVENT')) return true;
    final docId = (sale['inventoryDocId'] ?? sale['inventory_doc_id'] ?? '')
        .toString()
        .trim();
    return docId.isNotEmpty;
  }

  static String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      return _firstText([
        value['name'],
        value['fullName'],
        value['description'],
        value['label'],
        value['phone'],
        value['email'],
      ]);
    }
    return value.toString().trim();
  }

  static String _fallback(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? '-' : text;
  }

  static String _qty(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || number <= 0) return '';
    return number % 1 == 0
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(2);
  }

  static String _money(num value) {
    final amount = value.toDouble();
    final hasCents = (amount % 1).abs() > 0.000001;
    return hasCents
        ? '\$${amount.toStringAsFixed(2)}'
        : '\$${amount.toStringAsFixed(0)}';
  }

  static String _filename(DateTime day, {String extension = 'pdf'}) {
    final stamp = DateFormat('yyyyMMdd').format(day);
    return 'balance_$stamp.$extension';
  }

  static Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final data = await rootBundle.load(_logoAsset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Font?> _loadFont(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  static void _xmlBalanceSheetRows(
    StringBuffer xml, {
    required List<_BalanceReportRow> rows,
    required String emptyLabel,
  }) {
    _xmlRow(xml, [
      _xmlStringCell('Fecha', styleId: 'Header'),
      _xmlStringCell('Tipo', styleId: 'Header'),
      _xmlStringCell('Vendedor', styleId: 'Header'),
      _xmlStringCell('Descripcion', styleId: 'Header'),
      _xmlStringCell('Contacto', styleId: 'Header'),
      _xmlStringCell('Estado', styleId: 'Header'),
      _xmlStringCell('M. de pago', styleId: 'Header'),
      _xmlStringCell('Valor', styleId: 'Header'),
    ]);

    if (rows.isEmpty) {
      _xmlRow(xml, [
        _xmlMergedStringCell(
          emptyLabel,
          styleId: 'EmptyNotice',
          mergeAcross: 7,
        ),
      ]);
      return;
    }

    for (final row in rows) {
      _xmlRow(xml, [
        _xmlStringCell(row.date, styleId: 'Cell'),
        _xmlStringCell(row.type, styleId: 'Cell'),
        _xmlStringCell(row.seller, styleId: 'Cell'),
        _xmlStringCell(row.description, styleId: 'Cell'),
        _xmlStringCell(row.contact, styleId: 'Cell'),
        _xmlStringCell(row.status, styleId: 'Cell'),
        _xmlStringCell(row.paymentMethod, styleId: 'Cell'),
        _xmlNumberCell(row.value, styleId: 'Money'),
      ]);
    }
  }

  static void _xmlSectionHeader(
    StringBuffer xml, {
    required String title,
    required int transactionCount,
  }) {
    _xmlRow(xml, [
      _xmlMergedStringCell(title, styleId: 'SectionTitle', mergeAcross: 5),
      _xmlMergedStringCell(
        'Numero de transacciones: $transactionCount',
        styleId: 'SectionBadge',
        mergeAcross: 1,
      ),
    ]);
    _xmlRow(xml, const []);
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

enum _BalanceReportSection { sales, expenses }

class _BalanceReportRow {
  const _BalanceReportRow({
    required this.section,
    required this.date,
    required this.type,
    required this.seller,
    required this.description,
    required this.contact,
    required this.status,
    required this.paymentMethod,
    required this.value,
    required this.kind,
  });

  final _BalanceReportSection section;
  final String date;
  final String type;
  final String seller;
  final String description;
  final String contact;
  final String status;
  final String paymentMethod;
  final double value;
  final String kind;
}

class _BalanceSummary {
  const _BalanceSummary({
    required this.income,
    required this.salesCredits,
    required this.expenseCredits,
    required this.expenses,
    required this.total,
  });

  final double income;
  final double salesCredits;
  final double expenseCredits;
  final double expenses;
  final double total;
}
