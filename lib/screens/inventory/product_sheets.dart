import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../ui/app_theme.dart';
import '../../ui/input_formatters.dart';

Future<void> showPurchaseSheet(BuildContext context) async {
  context.read<AppState>().openNewExpenseSheetFromInventory();
}

Future<void> showProductSheet(BuildContext context, Product p) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF5F5F6),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (_) => _ProductSheet(product: p),
  );
}

Future<void> showCreateProductSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF4F5F7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _CreateProductSheet(),
  );
}

Future<void> showEditProductSheet(BuildContext context, Product p) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF4F5F7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _EditProductSheet(product: p),
  );
}

Widget _productImagePreview({
  required BuildContext context,
  String? imageUrl,
  String? localPath,
  double size = 92,
  BorderRadius? radius,
}) {
  final borderRadius = radius ?? BorderRadius.circular(18);
  final hasLocal = (localPath ?? '').trim().isNotEmpty;
  final resolved = context.read<AppState>().resolveApiUrl(imageUrl);

  Widget child;
  if (hasLocal) {
    child = ClipRRect(
      borderRadius: borderRadius,
      child: Image.file(
        File(localPath!.trim()),
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  } else if ((resolved ?? '').trim().isNotEmpty) {
    child = ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        resolved!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            _productImagePlaceholder(size: size, radius: borderRadius),
      ),
    );
  } else {
    child = _productImagePlaceholder(size: size, radius: borderRadius);
  }

  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppTheme.bg,
      borderRadius: borderRadius,
      border: Border.all(color: const Color(0xFFD6DCE4), width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

Widget _productImagePlaceholder({
  required double size,
  required BorderRadius radius,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFF3F6FA),
      borderRadius: radius,
    ),
    child: const Icon(
      Icons.inventory_2_outlined,
      color: AppTheme.navy,
      size: 34,
    ),
  );
}

String _extractApiError(dynamic e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is List && msg.isNotEmpty) return msg.join(', ');
      if (msg != null) return msg.toString();
      if (data['error'] != null) return data['error'].toString();
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return e.message ?? 'Error de red';
  }
  return e.toString();
}

String _fmtMoney(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

String _fmtQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
    RegExp(r'\.$'),
    '',
  );
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.product});
  final Product product;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late double _targetQty;
  bool _updatingQty = false;

  @override
  void initState() {
    super.initState();
    _targetQty = widget.product.stock;
  }

  bool get _qtyChanged =>
      (_targetQty - widget.product.stock).abs() > 0.000001;

  bool get _isLowStock => _targetQty <= 1;

  void _increaseQty() {
    setState(() {
      _targetQty += 1;
    });
  }

  void _decreaseQty() {
    if (_targetQty <= 0) return;
    setState(() {
      _targetQty = (_targetQty - 1).clamp(0, double.infinity);
    });
  }

  Future<void> _updateUnits() async {
    final model = context.read<AppState>();
    final p = widget.product;

    if (!model.canEditarInventario) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para editar inventario'),
        ),
      );
      return;
    }

    if (!_qtyChanged) return;

    setState(() => _updatingQty = true);
    try {
      await model.editarProductoBasico(
        productId: p.id,
        barcode: p.barcode,
        description: p.name,
        line: p.line,
        subLine: p.subLine,
        category: p.category,
        subCategory: p.subCategory,
        costUsd: p.costUsd,
        priceRetailUsd: p.priceRetailUsd,
        priceWholesaleUsd: p.priceWholesaleUsd,
        targetQty: _targetQty,
        currentQty: p.stock,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unidades actualizadas correctamente')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final msg = _extractApiError(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $msg')));
    } finally {
      if (mounted) setState(() => _updatingQty = false);
    }
  }

  Future<void> _openFullEdit() async {
    final p = widget.product;
    Navigator.pop(context);
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await showEditProductSheet(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final canEdit = context.watch<AppState>().canEditarInventario;
    final bottom = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;

    final double qtyCardPaddingH =
        (screenWidth * 0.045).clamp(14.0, 18.0).toDouble();
    final double qtyCardPaddingV =
        (screenWidth * 0.038).clamp(12.0, 16.0).toDouble();
    final double qtyControlHeight =
        (screenWidth * 0.14).clamp(46.0, 58.0).toDouble();
    final double qtyButtonSize =
        (screenWidth * 0.10).clamp(34.0, 42.0).toDouble();
    final double qtyValueWidth =
        (screenWidth * 0.15).clamp(42.0, 62.0).toDouble();
    final double qtyValueFontSize =
        (screenWidth * 0.048).clamp(16.0, 19.0).toDouble();
    final double qtyLabelFontSize =
        (screenWidth * 0.043).clamp(14.0, 17.0).toDouble();
    final double qtyInfoWrapSize =
        (screenWidth * 0.082).clamp(28.0, 34.0).toDouble();
    final double qtyInfoIconSize =
        (screenWidth * 0.052).clamp(18.0, 21.0).toDouble();

    final qtyAccent = _isLowStock
        ? const Color(0xFFD14436)
        : const Color(0xFF18324A);

    final updateEnabled = canEdit && !_updatingQty && _qtyChanged;

    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFFF5F5F6),
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.05,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1B2E45),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${_fmtMoney(p.priceRetailUsd)}',
                            style: const TextStyle(
                              fontSize: 22,
                              height: 1,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF1B2E45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6E86A3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: qtyCardPaddingH,
                  vertical: qtyCardPaddingV,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFD3DAE3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: qtyInfoWrapSize,
                            height: qtyInfoWrapSize,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1EF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              Icons.info_outline,
                              size: qtyInfoIconSize,
                              color: qtyAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              'Cantidad disponible',
                              style: TextStyle(
                                fontSize: qtyLabelFontSize,
                                fontWeight: FontWeight.w700,
                                color: qtyAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: qtyControlHeight,
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            (screenWidth * 0.025).clamp(8.0, 10.0).toDouble(),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          (qtyControlHeight / 2).clamp(20.0, 24.0).toDouble(),
                        ),
                        border: Border.all(
                          color: const Color(0xFFD3DAE3),
                          width: 1.4,
                        ),
                      ),
                      child: Row(
                        children: [
                          _QtyCircleButton(
                            icon: Icons.remove,
                            size: qtyButtonSize,
                            iconSize: (qtyButtonSize * 0.62)
                                .clamp(20.0, 26.0)
                                .toDouble(),
                            onTap: (_updatingQty || !canEdit || _targetQty <= 0)
                                ? null
                                : _decreaseQty,
                          ),
                          SizedBox(
                            width: qtyValueWidth,
                            child: Center(
                              child: Text(
                                _fmtQty(_targetQty),
                                style: TextStyle(
                                  fontSize: qtyValueFontSize,
                                  fontWeight: FontWeight.w700,
                                  color: qtyAccent,
                                ),
                              ),
                            ),
                          ),
                          _QtyCircleButton(
                            icon: Icons.add,
                            size: qtyButtonSize,
                            iconSize: (qtyButtonSize * 0.62)
                                .clamp(20.0, 26.0)
                                .toDouble(),
                            onTap: (_updatingQty || !canEdit)
                                ? null
                                : _increaseQty,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 64,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFDCE1E7),
                    disabledBackgroundColor: const Color(0xFFDCE1E7),
                    foregroundColor: const Color(0xFF91A0B4),
                    disabledForegroundColor: const Color(0xFF91A0B4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: updateEnabled ? _updateUnits : null,
                  child: _updatingQty
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Color(0xFF91A0B4),
                          ),
                        )
                      : const Text(
                          'Actualizar unidades',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 64,
                child: OutlinedButton(
                  onPressed: canEdit && !_updatingQty ? _openFullEdit : null,
                  style: OutlinedButton.styleFrom(
                    elevation: 0,
                    foregroundColor: const Color(0xFF152B43),
                    backgroundColor: Colors.white,
                    side: const BorderSide(
                      color: Color(0xFF152B43),
                      width: 2.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'Editar producto',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyCircleButton extends StatelessWidget {
  const _QtyCircleButton({
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.iconSize = 26,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? const Color(0xFF18324A)
                : const Color(0xFFC4CDD8),
            width: 1.8,
          ),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: enabled
              ? const Color(0xFF18324A)
              : const Color(0xFFC4CDD8),
        ),
      ),
    );
  }
}

InputDecoration _dec(
  String label, {
  String? hint,
  bool enabled = true,
  String? helperText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helperText,
    isDense: true,
    filled: true,
    fillColor: enabled ? Colors.white : const Color(0xFFF4F6F8),
    enabled: enabled,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    labelStyle: const TextStyle(
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    ),
    hintStyle: const TextStyle(
      color: Color(0xFFB8C0CC),
      fontWeight: FontWeight.w600,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFD6DCE4), width: 1.4),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFD6DCE4), width: 1.4),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppTheme.navy, width: 1.6),
    ),
  );
}

Widget _sheetSectionCard({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE5EAF1), width: 1.1),
    ),
    child: child,
  );
}

Widget _miniBadge(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF18A957),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.onDelete,
    this.initial,
    this.allowEditStock = true,
  });

  final String title;
  final String submitLabel;
  final Future<void> Function(_ProductFormValue value) onSubmit;
  final Future<void> Function()? onDelete;
  final Product? initial;
  final bool allowEditStock;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final TextEditingController _codigo;
  late final TextEditingController _nombre;
  late final TextEditingController _linea;
  late final TextEditingController _subLinea;
  late final TextEditingController _categoria;
  late final TextEditingController _subCategoria;
  late final TextEditingController _cantidad;
  late final TextEditingController _costoCompra;
  late final TextEditingController _precioVenta;
  final ImagePicker _imagePicker = ImagePicker();

  String? _selectedImagePath;
  bool _removeExistingImage = false;
  bool _processing = false;

  bool _detailsExpanded = true;
  bool _variantsExpanded = false;
  bool _inventoryExpanded = true;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _codigo = TextEditingController(text: p?.barcode ?? '');
    _nombre = TextEditingController(text: p?.name ?? '');
    _linea = TextEditingController(text: p?.line ?? '');
    _subLinea = TextEditingController(text: p?.subLine ?? '');
    _categoria = TextEditingController(
      text: (p?.category ?? '').trim() == 'Sin categoría'
          ? ''
          : (p?.category ?? ''),
    );
    _subCategoria = TextEditingController(text: p?.subCategory ?? '');
    _cantidad = TextEditingController(
      text: ((p?.stock ?? 0)).toStringAsFixed(0),
    );
    _costoCompra = TextEditingController(
      text: p == null ? '' : _fmtMoney(p.costUsd),
    );
    _precioVenta = TextEditingController(
      text: p == null ? '' : _fmtMoney(p.priceRetailUsd),
    );
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _linea.dispose();
    _subLinea.dispose();
    _categoria.dispose();
    _subCategoria.dispose();
    _cantidad.dispose();
    _costoCompra.dispose();
    _precioVenta.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) {
    final txt = c.text.replaceAll(',', '.').trim();
    return double.tryParse(txt) ?? 0;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _selectedImagePath = picked.path;
        _removeExistingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo seleccionar la imagen: ${_extractApiError(e)}',
          ),
        ),
      );
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImagePath = null;
      _removeExistingImage = widget.initial?.imageUrl != null;
    });
  }

  Future<void> _submit() async {
    final codigo = _codigo.text.trim();
    final nombre = _nombre.text.trim();
    final linea = _linea.text.trim();
    final subLinea = _subLinea.text.trim();
    final categoria = _categoria.text.trim();
    final subCategoria = _subCategoria.text.trim();

    if (codigo.isEmpty || nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Código de producto y nombre del producto son obligatorios.',
          ),
        ),
      );
      return;
    }

    final cantidad = _num(_cantidad);
    final costoCompra = _num(_costoCompra);
    final precioVenta = _num(_precioVenta);

    if (cantidad < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cantidad disponible no puede ser negativa.'),
        ),
      );
      return;
    }

    if (precioVenta <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes indicar un precio de venta mayor a 0.'),
        ),
      );
      return;
    }

    if (costoCompra < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El costo de compra no puede ser negativo.'),
        ),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      await widget.onSubmit(
        _ProductFormValue(
          codigo: codigo,
          nombre: nombre,
          line: linea.isEmpty ? null : linea,
          subLine: subLinea.isEmpty ? null : subLinea,
          category: categoria.isEmpty ? null : categoria,
          subCategory: subCategoria.isEmpty ? null : subCategoria,
          imagePath: _selectedImagePath,
          removeImage: _removeExistingImage,
          cantidad: cantidad,
          costoCompra: costoCompra,
          precioVenta: precioVenta,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final msg = _extractApiError(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $msg')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _delete() async {
    if (widget.onDelete == null) return;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Eliminar producto'),
            content: const Text('¿Seguro que quieres eliminar este producto?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _processing = true);
    try {
      await widget.onDelete!.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final msg = _extractApiError(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $msg')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Widget _buildSectionHeader({
    required String title,
    required bool expanded,
    required VoidCallback onTap,
    Widget? badge,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _processing ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 10),
              badge,
            ],
            const Spacer(),
            AnimatedRotation(
              turns: expanded ? 0 : 0.5,
              duration: const Duration(milliseconds: 180),
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 28,
                color: AppTheme.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableSection({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    Widget? badge,
    required Widget child,
  }) {
    return _sheetSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: title,
            expanded: expanded,
            onTap: onToggle,
            badge: badge,
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: child,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final cantidad = _num(_cantidad);
    final costoCompra = _num(_costoCompra);
    final costoTotal = cantidad * costoCompra;
    final hasImage =
        _selectedImagePath != null ||
        (!_removeExistingImage &&
            (widget.initial?.imageUrl ?? '').trim().isNotEmpty);

    return Container(
      color: const Color(0xFFF4F5F7),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _processing
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildExpandableSection(
                  title: 'Detalles del producto',
                  expanded: _detailsExpanded,
                  onToggle: () {
                    setState(() => _detailsExpanded = !_detailsExpanded);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _processing
                                ? null
                                : () => _pickImage(ImageSource.gallery),
                            child: Container(
                              width: 116,
                              height: 116,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCEBFF),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF2C7BE5),
                                  width: 1.4,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: hasImage
                                  ? _productImagePreview(
                                      context: context,
                                      imageUrl: _removeExistingImage
                                          ? null
                                          : widget.initial?.imageUrl,
                                      localPath: _selectedImagePath,
                                      size: 116,
                                      radius: BorderRadius.circular(20),
                                    )
                                  : const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.upload_outlined,
                                          color: Color(0xFF2C7BE5),
                                          size: 34,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Cargar imagen',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Color(0xFF2C7BE5),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 44,
                                  child: OutlinedButton.icon(
                                    onPressed: _processing
                                        ? null
                                        : () => _pickImage(ImageSource.gallery),
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                    label: const Text('Galería'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 44,
                                  child: OutlinedButton.icon(
                                    onPressed: _processing
                                        ? null
                                        : () => _pickImage(ImageSource.camera),
                                    icon: const Icon(
                                      Icons.photo_camera_outlined,
                                    ),
                                    label: const Text('Cámara'),
                                  ),
                                ),
                                if (hasImage) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 44,
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          _processing ? null : _clearImage,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      label: const Text(
                                        'Quitar',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Color(0xFFFFD4D4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nombre,
                        decoration: _dec('Nombre del producto'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _precioVenta,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters:
                            AppInputFormatters.decimal(maxDecimals: 2),
                        onChanged: (_) => setState(() {}),
                        decoration: _dec(
                          '¿A cuánto lo vendes? (USD)',
                          hint: '0',
                          helperText:
                              'Este es el precio que se mostrará en inventario.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildExpandableSection(
                  title: 'Variantes',
                  expanded: _variantsExpanded,
                  onToggle: () {
                    setState(() => _variantsExpanded = !_variantsExpanded);
                  },
                  badge: _miniBadge('Nuevo'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _linea,
                              decoration: _dec(
                                'Línea',
                                hint: 'Ej: Dama, Caballero, Niña',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _subLinea,
                              decoration: _dec(
                                'Sub línea',
                                hint: 'Ej: Blusa, Jean, Vestido',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _categoria,
                              decoration: _dec(
                                'Categoría',
                                hint: 'Ej: Talla',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _subCategoria,
                              decoration: _dec(
                                'Sub categoría',
                                hint: 'Ej: Color',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Aquí defines la jerarquía que usará el inventario para filtrar productos.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildExpandableSection(
                  title: 'Inventario',
                  expanded: _inventoryExpanded,
                  onToggle: () {
                    setState(() => _inventoryExpanded = !_inventoryExpanded);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _codigo,
                        decoration: _dec(
                          'Código de producto',
                          hint: 'Escríbelo o escanéalo',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _cantidad,
                              enabled: widget.allowEditStock,
                              readOnly: !widget.allowEditStock,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters:
                                  AppInputFormatters.decimal(maxDecimals: 3),
                              onChanged: (_) => setState(() {}),
                              decoration: _dec(
                                'Cantidad disponible',
                                hint: '0',
                                enabled: widget.allowEditStock,
                                helperText: widget.allowEditStock
                                    ? null
                                    : 'Solo lectura por ahora.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _costoCompra,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters:
                                  AppInputFormatters.decimal(maxDecimals: 2),
                              onChanged: (_) => setState(() {}),
                              decoration: _dec(
                                '¿A cuánto lo compras? (USD)',
                                hint: 'Opcional',
                                helperText: 'No es el precio de venta.',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFD6DCE4),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Costo total',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                            Text(
                              '\$${costoTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.onDelete != null) ...[
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _processing ? null : _delete,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'Eliminar producto',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFFFD4D4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.navy,
                      disabledBackgroundColor: const Color(0xFFD4DBE4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _processing ? null : _submit,
                    child: _processing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.submitLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductFormValue {
  final String codigo;
  final String nombre;
  final String? line;
  final String? subLine;
  final String? category;
  final String? subCategory;
  final String? imagePath;
  final bool removeImage;
  final double cantidad;
  final double costoCompra;
  final double precioVenta;

  const _ProductFormValue({
    required this.codigo,
    required this.nombre,
    required this.line,
    required this.subLine,
    required this.category,
    required this.subCategory,
    required this.imagePath,
    required this.removeImage,
    required this.cantidad,
    required this.costoCompra,
    required this.precioVenta,
  });
}

class _CreateProductSheet extends StatelessWidget {
  const _CreateProductSheet();

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<AppState>().canCrearInventario;
    return _ProductForm(
      title: 'Crear producto',
      submitLabel: 'Crear producto',
      allowEditStock: true,
      onSubmit: (v) async {
        if (!canCreate) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No tienes permiso para crear inventario'),
            ),
          );
          return;
        }
        await context.read<AppState>().crearProductoBasico(
          barcode: v.codigo,
          description: v.nombre,
          line: v.line,
          subLine: v.subLine,
          category: (v.category ?? '').trim(),
          subCategory: v.subCategory,
          costUsd: v.costoCompra,
          priceRetailUsd: v.precioVenta,
          imagePath: v.imagePath,
          initialQty: v.cantidad,
        );
      },
    );
  }
}

class _EditProductSheet extends StatelessWidget {
  const _EditProductSheet({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppState>();
    final canEdit = model.canEditarInventario;
    final canDelete = model.canEliminarInventario;
    return _ProductForm(
      title: 'Editar producto',
      submitLabel: 'Guardar cambios',
      initial: product,
      allowEditStock: canEdit,
      onSubmit: (v) async {
        if (!canEdit) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No tienes permiso para editar inventario'),
            ),
          );
          return;
        }
        await context.read<AppState>().editarProductoBasico(
          productId: product.id,
          barcode: v.codigo,
          description: v.nombre,
          line: v.line,
          subLine: v.subLine,
          category: (v.category ?? '').trim(),
          subCategory: v.subCategory,
          costUsd: v.costoCompra,
          priceRetailUsd: v.precioVenta,
          imagePath: v.imagePath,
          removeImage: v.removeImage,
          targetQty: v.cantidad,
          currentQty: product.stock,
        );
      },
      onDelete: canDelete
          ? () =>
                context.read<AppState>().eliminarProducto(productId: product.id)
          : null,
    );
  }
}
