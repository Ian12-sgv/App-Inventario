import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/txn.dart';

class ReceiptPrinter {
  static const String _defaultCompanyName = 'By Rossi Gran bazar';
  static const String _defaultBusinessLocation = 'Gran bazar';
  static const String _defaultBusinessPhone = '04120635697';
  static const String _fontRegularAsset = 'assets/fonts/Arial.ttf';
  static const String _fontBoldAsset = 'assets/fonts/Arial Bold.ttf';

  static const PdfColor _ink = PdfColor.fromInt(0xFF20242C);
  static const PdfColor _line = PdfColor.fromInt(0xFFDDE2E8);
  static const PdfColor _paper = PdfColor.fromInt(0xFFFFFFFF);

  static Future<void> imprimirPagoVenta({
    required Txn txn,
    required Map<String, dynamic> sale,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildPagoVentaPdf(
      txn: txn,
      sale: sale,
      employeeName: employeeName,
      lines: lines,
      companyName: companyName,
    );
    await _printPdf(
      bytes,
      filename: 'comprobante_pago_${_shortId(txn.id)}.pdf',
    );
  }

  static Future<void> compartirPagoVentaPdf({
    required Txn txn,
    required Map<String, dynamic> sale,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildPagoVentaPdf(
      txn: txn,
      sale: sale,
      employeeName: employeeName,
      lines: lines,
      companyName: companyName,
    );
    await _sharePdf(
      bytes,
      filename: 'comprobante_pago_${_shortId(txn.id)}.pdf',
    );
  }

  static Future<void> compartirPagoVentaImagen({
    required Txn txn,
    required Map<String, dynamic> sale,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    Rect? sharePositionOrigin,
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildPagoVentaPdf(
      txn: txn,
      sale: sale,
      employeeName: employeeName,
      lines: lines,
      companyName: companyName,
    );
    await _shareImageFromPdf(
      bytes,
      filename: 'comprobante_pago_${_shortId(txn.id)}.png',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static Future<void> compartirPagoVenta({
    required Txn txn,
    required Map<String, dynamic> sale,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    String companyName = _defaultCompanyName,
  }) {
    return compartirPagoVentaPdf(
      txn: txn,
      sale: sale,
      employeeName: employeeName,
      lines: lines,
      companyName: companyName,
    );
  }

  static Future<void> imprimirVentaCompleta({
    required Map<String, dynamic> sale,
    required String saleId,
    required List<Txn> payments,
    required List<Map<String, dynamic>> lines,
    required String employeeName,
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildVentaCompletaPdf(
      sale: sale,
      saleId: saleId,
      payments: payments,
      lines: lines,
      employeeName: employeeName,
      companyName: companyName,
    );
    await _printPdf(
      bytes,
      filename: 'comprobante_venta_${_shortId(saleId)}.pdf',
    );
  }

  static Future<void> compartirVentaCompletaPdf({
    required Map<String, dynamic> sale,
    required String saleId,
    required List<Txn> payments,
    required List<Map<String, dynamic>> lines,
    required String employeeName,
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildVentaCompletaPdf(
      sale: sale,
      saleId: saleId,
      payments: payments,
      lines: lines,
      employeeName: employeeName,
      companyName: companyName,
    );
    await _sharePdf(
      bytes,
      filename: 'comprobante_venta_${_shortId(saleId)}.pdf',
    );
  }

  static Future<void> compartirVentaCompletaImagen({
    required Map<String, dynamic> sale,
    required String saleId,
    required List<Txn> payments,
    required List<Map<String, dynamic>> lines,
    required String employeeName,
    Rect? sharePositionOrigin,
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildVentaCompletaPdf(
      sale: sale,
      saleId: saleId,
      payments: payments,
      lines: lines,
      employeeName: employeeName,
      companyName: companyName,
    );
    await _shareImageFromPdf(
      bytes,
      filename: 'comprobante_venta_${_shortId(saleId)}.png',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static Future<void> compartirVentaCompleta({
    required Map<String, dynamic> sale,
    required String saleId,
    required List<Txn> payments,
    required List<Map<String, dynamic>> lines,
    required String employeeName,
    String companyName = _defaultCompanyName,
  }) {
    return compartirVentaCompletaPdf(
      sale: sale,
      saleId: saleId,
      payments: payments,
      lines: lines,
      employeeName: employeeName,
      companyName: companyName,
    );
  }

  static Future<void> imprimirGasto({
    required Map<String, dynamic> expense,
    required String expenseId,
    required List<Txn> payments,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildGastoPdf(
      expense: expense,
      expenseId: expenseId,
      payments: payments,
      employeeName: employeeName,
      companyName: companyName,
      lines: lines,
    );
    await _printPdf(
      bytes,
      filename: 'comprobante_gasto_${_shortId(expenseId)}.pdf',
    );
  }

  static Future<void> compartirGastoPdf({
    required Map<String, dynamic> expense,
    required String expenseId,
    required List<Txn> payments,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildGastoPdf(
      expense: expense,
      expenseId: expenseId,
      payments: payments,
      employeeName: employeeName,
      companyName: companyName,
      lines: lines,
    );
    await _sharePdf(
      bytes,
      filename: 'comprobante_gasto_${_shortId(expenseId)}.pdf',
    );
  }

  static Future<void> compartirGastoImagen({
    required Map<String, dynamic> expense,
    required String expenseId,
    required List<Txn> payments,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    Rect? sharePositionOrigin,
    String companyName = _defaultCompanyName,
  }) async {
    final bytes = await _buildGastoPdf(
      expense: expense,
      expenseId: expenseId,
      payments: payments,
      employeeName: employeeName,
      companyName: companyName,
      lines: lines,
    );
    await _shareImageFromPdf(
      bytes,
      filename: 'comprobante_gasto_${_shortId(expenseId)}.png',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static Future<void> compartirGasto({
    required Map<String, dynamic> expense,
    required String expenseId,
    required List<Txn> payments,
    required String employeeName,
    List<Map<String, dynamic>> lines = const [],
    String companyName = _defaultCompanyName,
  }) {
    return compartirGastoPdf(
      expense: expense,
      expenseId: expenseId,
      payments: payments,
      employeeName: employeeName,
      lines: lines,
      companyName: companyName,
    );
  }

  static Future<Uint8List> _buildPagoVentaPdf({
    required Txn txn,
    required Map<String, dynamic> sale,
    required String employeeName,
    required List<Map<String, dynamic>> lines,
    required String companyName,
  }) async {
    final totalSale = _toDouble(sale['totalUsd']);
    final concept = _firstText([
      sale['description'],
      sale['concept'],
      txn.note,
      'Venta',
    ]);
    final items = _saleReceiptLines(
      lines,
      fallbackLabel: concept,
      fallbackTotal: totalSale > 0 ? totalSale : txn.amount,
    );
    final computedTotal = totalSale > 0 ? totalSale : _sumLines(items);
    final data = _ReceiptDocumentData(
      companyName: companyName,
      businessLocation: _defaultBusinessLocation,
      businessPhone: _defaultBusinessPhone,
      dateLabel: _formatReceiptDate(txn.when),
      sellerLabel: _fallback(employeeName),
      paymentMethodLabel: _fallback(txn.paymentMethod),
      statusLabel: totalSale > 0 && (txn.amount + 0.000001) < totalSale
          ? 'Abono'
          : 'Pagada',
      transactionLabel: _transactionNumber(sale, fallbackId: txn.id),
      items: items,
      totalAmount: computedTotal,
    );
    return _buildReceiptPdf(data);
  }

  static Future<Uint8List> _buildVentaCompletaPdf({
    required Map<String, dynamic> sale,
    required String saleId,
    required List<Txn> payments,
    required List<Map<String, dynamic>> lines,
    required String employeeName,
    required String companyName,
  }) async {
    final rawWhen = _firstText([sale['occurredAt'], sale['occurred_at']]);
    final parsedWhen = DateTime.tryParse(rawWhen);
    final when = parsedWhen == null
        ? (payments.isNotEmpty ? payments.first.when : DateTime.now())
        : (parsedWhen.isUtc ? parsedWhen.toLocal() : parsedWhen);
    final totalUsd = _toDouble(sale['totalUsd']);
    final outstandingUsd = _toDouble(sale['outstandingUsd']);
    final status = _firstText([
      sale['statusLabel'],
      sale['status'],
      outstandingUsd > 0.01 ? 'Deuda' : 'Pagada',
    ]);
    final items = _saleReceiptLines(
      lines,
      fallbackLabel: _firstText([
        sale['description'],
        sale['concept'],
        'Venta',
      ]),
      fallbackTotal: totalUsd,
    );
    final computedTotal = totalUsd > 0 ? totalUsd : _sumLines(items);
    final data = _ReceiptDocumentData(
      companyName: companyName,
      businessLocation: _defaultBusinessLocation,
      businessPhone: _defaultBusinessPhone,
      dateLabel: _formatReceiptDate(when),
      sellerLabel: _fallback(employeeName),
      paymentMethodLabel: _paymentMethodLabel(
        payments,
        fallback: _firstText([
          sale['paymentMethodLabel'],
          sale['paymentMethod'],
          sale['payment_method'],
        ]),
      ),
      statusLabel: _fallback(status),
      transactionLabel: _transactionNumber(sale, fallbackId: saleId),
      items: items,
      totalAmount: computedTotal,
    );
    return _buildReceiptPdf(data);
  }

  static Future<Uint8List> _buildGastoPdf({
    required Map<String, dynamic> expense,
    required String expenseId,
    required List<Txn> payments,
    required String employeeName,
    required String companyName,
    required List<Map<String, dynamic>> lines,
  }) async {
    final rawWhen = _firstText([expense['occurredAt'], expense['occurred_at']]);
    final parsedWhen = DateTime.tryParse(rawWhen);
    final when = parsedWhen == null
        ? (payments.isNotEmpty ? payments.first.when : DateTime.now())
        : (parsedWhen.isUtc ? parsedWhen.toLocal() : parsedWhen);
    final totalUsd = _toDouble(expense['totalUsd'] ?? expense['amountUsd']);
    final outstandingUsd = _toDouble(expense['outstandingUsd']);
    final status = _firstText([
      expense['statusLabel'],
      expense['status'],
      outstandingUsd > 0.01 ? 'Deuda' : 'Pagada',
    ]);
    final items = _expenseReceiptLines(
      lines,
      fallbackLabel: _firstText([
        expense['description'],
        expense['concept'],
        'Gasto',
      ]),
      fallbackTotal: totalUsd,
    );
    final computedTotal = totalUsd > 0 ? totalUsd : _sumLines(items);
    final data = _ReceiptDocumentData(
      companyName: companyName,
      businessLocation: _defaultBusinessLocation,
      businessPhone: _defaultBusinessPhone,
      dateLabel: _formatReceiptDate(when),
      sellerLabel: _fallback(employeeName),
      paymentMethodLabel: _paymentMethodLabel(
        payments,
        fallback: _firstText([
          expense['paymentMethodLabel'],
          expense['paymentMethod'],
          expense['payment_method'],
        ]),
      ),
      statusLabel: _fallback(status),
      transactionLabel: _transactionNumber(expense, fallbackId: expenseId),
      items: items,
      totalAmount: computedTotal,
    );
    return _buildReceiptPdf(data);
  }

  static Future<Uint8List> _buildReceiptPdf(_ReceiptDocumentData data) async {
    final baseFont = await _loadFont(_fontRegularAsset);
    final boldFont = await _loadFont(_fontBoldAsset);
    final theme = baseFont == null
        ? null
        : pw.ThemeData.withFont(base: baseFont, bold: boldFont ?? baseFont);
    final doc = theme == null ? pw.Document() : pw.Document(theme: theme);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(54, 42, 54, 42),
          theme: theme,
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: _paper),
          ),
        ),
        build: (_) => [
          pw.Text(
            data.companyName,
            style: pw.TextStyle(
              fontSize: 23,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              _headerMeta('Ubicación', data.businessLocation),
              pw.SizedBox(width: 18),
              _headerMeta('Tel', data.businessPhone),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Divider(color: _line, thickness: 0.8),
          pw.SizedBox(height: 16),
          _infoRow('Fecha', data.dateLabel),
          pw.SizedBox(height: 8),
          _infoRow('Vendedor', data.sellerLabel),
          pw.SizedBox(height: 8),
          _infoRow('Método de pago', data.paymentMethodLabel),
          pw.SizedBox(height: 8),
          _infoRow('Estado', data.statusLabel),
          pw.SizedBox(height: 8),
          _infoRow('Número de transacción', data.transactionLabel),
          pw.SizedBox(height: 14),
          pw.Divider(color: _line, thickness: 0.8),
          pw.SizedBox(height: 8),
          _itemsTable(data.items),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Total:',
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.Text(
                _money(data.totalAmount),
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _headerMeta(String label, String text) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Text(text, style: const pw.TextStyle(fontSize: 11, color: _ink)),
      ],
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(label, style: pw.TextStyle(fontSize: 11, color: _ink)),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 11,
              color: _ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _itemsTable(List<_ReceiptLineItem> items) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.8),
        top: pw.BorderSide(color: _line, width: 0.8),
        bottom: pw.BorderSide(color: _line, width: 0.8),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(4.4),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          children: [
            _tableHeaderCell('Productos', align: pw.TextAlign.left),
            _tableHeaderCell('Cantidad'),
            _tableHeaderCell('Precio unitario'),
            _tableHeaderCell('Valor'),
          ],
        ),
        for (final item in items)
          pw.TableRow(
            children: [
              _tableCell(item.name, align: pw.TextAlign.left),
              _tableCell(_qty(item.qty)),
              _tableCell(_money(item.unitAmount)),
              _tableCell(_money(item.lineAmount)),
            ],
          ),
      ],
    );
  }

  static pw.Widget _tableHeaderCell(String text, {pw.TextAlign? align}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(2, 8, 2, 8),
      child: pw.Text(
        text,
        textAlign: align ?? pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(String text, {pw.TextAlign? align}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: pw.Text(
        text,
        textAlign: align ?? pw.TextAlign.right,
        style: const pw.TextStyle(fontSize: 11, color: _ink),
      ),
    );
  }

  static List<_ReceiptLineItem> _saleReceiptLines(
    List<Map<String, dynamic>> rows, {
    required String fallbackLabel,
    required double fallbackTotal,
  }) {
    if (rows.isEmpty) {
      final amount = fallbackTotal > 0 ? fallbackTotal : 0.0;
      return [
        _ReceiptLineItem(
          name: _fallback(fallbackLabel),
          qty: 1,
          unitAmount: amount,
          lineAmount: amount,
        ),
      ];
    }

    return rows.map((row) {
      final product = (row['product'] is Map)
          ? (row['product'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final qty = _toDouble(row['qty']);
      final safeQty = qty > 0 ? qty : 1.0;
      final unitAmount = _saleUnitPrice(row, product, safeQty, fallbackTotal);
      final lineAmount = _saleLineTotal(
        row,
        safeQty,
        unitAmount,
        fallbackTotal,
      );
      return _ReceiptLineItem(
        name: _receiptProductName(row),
        qty: safeQty,
        unitAmount: unitAmount,
        lineAmount: lineAmount,
      );
    }).toList();
  }

  static List<_ReceiptLineItem> _expenseReceiptLines(
    List<Map<String, dynamic>> rows, {
    required String fallbackLabel,
    required double fallbackTotal,
  }) {
    if (rows.isEmpty) {
      final amount = fallbackTotal > 0 ? fallbackTotal : 0.0;
      return [
        _ReceiptLineItem(
          name: _fallback(fallbackLabel),
          qty: 1,
          unitAmount: amount,
          lineAmount: amount,
        ),
      ];
    }

    return rows.map((row) {
      final qty = _toDouble(row['qty']);
      final safeQty = qty > 0 ? qty : 1.0;
      final unitCost = _toDouble(
        row['unitCostUsd'] ?? row['unitCost'] ?? row['costUsd'] ?? row['cost'],
      );
      final unitPrice = _toDouble(row['unitPriceUsd'] ?? row['unitPrice']);
      final unitAmount = unitCost > 0 ? unitCost : unitPrice;
      final lineAmount = _toDouble(row['lineTotalUsd'] ?? row['totalUsd']);
      return _ReceiptLineItem(
        name: _receiptProductName(row, fallback: fallbackLabel),
        qty: safeQty,
        unitAmount: unitAmount > 0
            ? unitAmount
            : (lineAmount > 0 ? lineAmount / safeQty : 0.0),
        lineAmount: lineAmount > 0
            ? lineAmount
            : (unitAmount > 0 ? unitAmount * safeQty : fallbackTotal),
      );
    }).toList();
  }

  static String _receiptProductName(
    Map<String, dynamic> row, {
    String fallback = 'Producto',
  }) {
    final product = (row['product'] is Map)
        ? (row['product'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final name = _firstText([
      product['description'],
      product['name'],
      product['reference'],
      product['barcode'],
      row['description'],
      row['name'],
      fallback,
    ]);
    final hierarchy = <String>[
      _firstText([product['line'], row['line'], row['linea']]),
      _firstText([
        product['subLine'],
        product['sub_line'],
        row['subLine'],
        row['sub_line'],
        row['sublinea'],
      ]),
      _firstText([product['category'], row['category'], row['categoria']]),
      _firstText([
        product['subCategory'],
        product['sub_category'],
        row['subCategory'],
        row['sub_category'],
        row['subcategoria'],
      ]),
    ].where((part) => part.isNotEmpty).toList();

    if (hierarchy.isEmpty) return name;
    return '$name\n${hierarchy.join(' / ')}';
  }

  static double _saleUnitPrice(
    Map<String, dynamic> row,
    Map<String, dynamic> product,
    double qty,
    double fallbackTotal,
  ) {
    final explicit = _toDouble(
      row['unitPriceUsd'] ??
          row['unitPrice'] ??
          row['priceRetailUsd'] ??
          row['priceRetail'] ??
          row['saleUnitPriceUsd'] ??
          row['salePriceUsd'] ??
          row['salePrice'] ??
          product['priceRetailUsd'] ??
          product['priceRetail'] ??
          product['salePriceUsd'] ??
          product['salePrice'] ??
          product['price'],
    );
    if (explicit > 0) return explicit;
    if (fallbackTotal > 0 && qty > 0) return fallbackTotal / qty;
    return 0;
  }

  static double _saleLineTotal(
    Map<String, dynamic> row,
    double qty,
    double unitPrice,
    double fallbackTotal,
  ) {
    final explicit = _toDouble(
      row['totalUsd'] ??
          row['saleTotalUsd'] ??
          row['saleLineTotalUsd'] ??
          row['subtotalUsd'] ??
          row['amountUsd'],
    );
    if (explicit > 0) return explicit;
    if (unitPrice > 0 && qty > 0) return unitPrice * qty;
    return fallbackTotal;
  }

  static Future<void> _printPdf(Uint8List bytes, {required String filename}) {
    return Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
  }

  static Future<void> _sharePdf(Uint8List bytes, {required String filename}) {
    return Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<void> _shareImageFromPdf(
    Uint8List bytes, {
    required String filename,
    Rect? sharePositionOrigin,
  }) async {
    Uint8List? pngBytes;
    await for (final page in Printing.raster(
      bytes,
      pages: const [0],
      dpi: 180,
    )) {
      pngBytes = await page.toPng();
      break;
    }
    if (pngBytes == null) {
      throw StateError('No se pudo generar la imagen del comprobante');
    }
    await SharePlus.instance.share(
      ShareParams(
        title: 'Comprobante',
        subject: 'Comprobante',
        text: 'Comprobante exportado desde By Rossi Gran bazar',
        files: [XFile.fromData(pngBytes, mimeType: 'image/png')],
        fileNameOverrides: [filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static Future<pw.Font?> _loadFont(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  static String _transactionNumber(
    Map<String, dynamic> source, {
    required String fallbackId,
  }) {
    return _firstText([
      source['transactionNumber'],
      source['transaction_number'],
      source['number'],
      source['consecutive'],
      source['sequential'],
      source['codigo'],
      _shortId(fallbackId),
    ]);
  }

  static String _paymentMethodLabel(
    List<Txn> payments, {
    required String fallback,
  }) {
    if (payments.isEmpty) return _fallback(fallback);
    final methods = payments
        .map((t) => t.paymentMethod.trim())
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList();
    if (methods.isEmpty) return _fallback(fallback);
    if (methods.length == 1) return methods.first;
    return 'Mixto';
  }

  static String _formatReceiptDate(DateTime date) {
    return DateFormat('d MMMM yyyy - HH:mm', 'es').format(date);
  }

  static double _sumLines(List<_ReceiptLineItem> items) {
    return items.fold(0.0, (sum, item) => sum + item.lineAmount);
  }

  static String _money(num value) {
    final n = value.toDouble();
    final hasCents = (n % 1).abs() > 0.000001;
    return hasCents ? '\$${n.toStringAsFixed(2)}' : '\$${n.toStringAsFixed(0)}';
  }

  static String _qty(num value) {
    final n = value.toDouble();
    if ((n % 1).abs() < 0.000001) {
      return n.toStringAsFixed(0);
    }
    return n.toStringAsFixed(2);
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
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
      ]);
    }
    return value.toString().trim();
  }

  static String _fallback(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? '-' : text;
  }

  static String _shortId(String id) {
    final text = id.trim();
    if (text.isEmpty) return '-';
    return text.length <= 8 ? text : text.substring(0, 8);
  }
}

class _ReceiptDocumentData {
  const _ReceiptDocumentData({
    required this.companyName,
    required this.businessLocation,
    required this.businessPhone,
    required this.dateLabel,
    required this.sellerLabel,
    required this.paymentMethodLabel,
    required this.statusLabel,
    required this.transactionLabel,
    required this.items,
    required this.totalAmount,
  });

  final String companyName;
  final String businessLocation;
  final String businessPhone;
  final String dateLabel;
  final String sellerLabel;
  final String paymentMethodLabel;
  final String statusLabel;
  final String transactionLabel;
  final List<_ReceiptLineItem> items;
  final double totalAmount;
}

class _ReceiptLineItem {
  const _ReceiptLineItem({
    required this.name,
    required this.qty,
    required this.unitAmount,
    required this.lineAmount,
  });

  final String name;
  final double qty;
  final double unitAmount;
  final double lineAmount;
}
