import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BalanceDateStrip extends StatefulWidget {
  const BalanceDateStrip({
    super.key,
    required this.selected,
    required this.format,
    required this.onPick,
    required this.onOpenCalendar,
    required this.selectedBackgroundColor,
    required this.selectedTextColor,
    required this.unselectedTextColor,
    required this.dividerColor,
    required this.calendarBorderColor,
    required this.calendarIconColor,
    this.isRefreshing = false,
    this.pastDays = 180,
    this.futureDays = 0,
  });

  final DateTime selected;
  final DateFormat format;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onOpenCalendar;
  final Color selectedBackgroundColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;
  final Color dividerColor;
  final Color calendarBorderColor;
  final Color calendarIconColor;
  final bool isRefreshing;
  final int pastDays;
  final int futureDays;

  @override
  State<BalanceDateStrip> createState() => _BalanceDateStripState();
}

class _BalanceDateStripState extends State<BalanceDateStrip> {
  static const double _chipWidth = 92;
  static const double _chipHeight = 40;
  static const double _gap = 8;
  static const double _outerHorizontalPadding = 20;
  static const double _calendarSectionWidth = 63;

  late ScrollController _scrollController;
  late DateTime _start;
  double? _lastViewportEstimate;

  DateTime _floor(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _today => _floor(DateTime.now());

  DateTime get _end {
    final extraDays = widget.futureDays < 0 ? 0 : widget.futureDays;
    return _today.add(Duration(days: extraDays));
  }

  DateTime get _selectedClamped {
    final selected = _floor(widget.selected);
    if (selected.isAfter(_end)) return _end;
    return selected;
  }

  int get _totalDays => _end.difference(_start).inDays + 1;

  @override
  void initState() {
    super.initState();
    _resetWindow();
    _scrollController = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureInitialController();
  }

  @override
  void didUpdateWidget(covariant BalanceDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);

    final selected = _selectedClamped;
    final end = _end;

    if (oldWidget.pastDays != widget.pastDays ||
        oldWidget.futureDays != widget.futureDays ||
        selected.isBefore(_start) ||
        selected.isAfter(end)) {
      _resetWindow();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected(animate: false);
      });
      return;
    }

    if (_floor(oldWidget.selected) != selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _resetWindow() {
    final baseStart = _end.subtract(Duration(days: widget.pastDays));
    final selected = _selectedClamped;
    _start = selected.isBefore(baseStart) ? selected : baseStart;
  }

  double _estimatedViewportWidth() {
    final width =
        MediaQuery.sizeOf(context).width -
        _outerHorizontalPadding -
        _calendarSectionWidth;
    return width < _chipWidth ? _chipWidth : width;
  }

  double _targetOffsetForViewport(double viewport) {
    final index = _selectedClamped
        .difference(_start)
        .inDays
        .clamp(0, _totalDays - 1);
    final estimatedContentWidth =
        (_totalDays * _chipWidth) + ((_totalDays - 1) * _gap);
    final estimatedMaxScroll = estimatedContentWidth > viewport
        ? estimatedContentWidth - viewport
        : 0.0;

    return (index * (_chipWidth + _gap) - ((viewport - _chipWidth) / 2)).clamp(
      0.0,
      estimatedMaxScroll,
    );
  }

  void _ensureInitialController() {
    final viewport = _estimatedViewportWidth();
    if (_lastViewportEstimate == viewport) return;

    final oldController = _scrollController;
    _lastViewportEstimate = viewport;
    _scrollController = ScrollController(
      initialScrollOffset: _targetOffsetForViewport(viewport),
    );

    if (oldController.hasClients) {
      oldController.dispose();
    } else {
      oldController.dispose();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToSelected(animate: false);
    });
  }

  void _scrollToSelected({bool animate = true}) {
    if (!_scrollController.hasClients) return;

    final index = _selectedClamped
        .difference(_start)
        .inDays
        .clamp(0, _totalDays - 1);
    final viewport = _scrollController.position.viewportDimension;
    final target = (index * (_chipWidth + _gap) - ((viewport - _chipWidth) / 2))
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedClamped;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: _chipHeight,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _totalDays,
                itemExtent: _chipWidth + _gap,
                itemBuilder: (context, index) {
                  final day = _start.add(Duration(days: index));
                  final isSelected =
                      day.year == selected.year &&
                      day.month == selected.month &&
                      day.day == selected.day;

                  return Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: _chipWidth,
                      child: InkWell(
                        onTap: () => widget.onPick(day),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: _chipHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? widget.selectedBackgroundColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.format.format(day),
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: isSelected
                                    ? widget.selectedTextColor
                                    : widget.unselectedTextColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 26, color: widget.dividerColor),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            height: 42,
            child: OutlinedButton(
              onPressed: widget.onOpenCalendar,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(color: widget.calendarBorderColor, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                foregroundColor: widget.calendarIconColor,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 20,
                    color: widget.calendarIconColor,
                  ),
                  if (widget.isRefreshing)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        width: 14,
                        height: 14,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.calendarBorderColor,
                            width: 0.8,
                          ),
                        ),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            widget.calendarIconColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
