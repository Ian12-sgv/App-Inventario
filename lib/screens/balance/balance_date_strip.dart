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
  final int pastDays;
  final int futureDays;

  @override
  State<BalanceDateStrip> createState() => _BalanceDateStripState();
}

class _BalanceDateStripState extends State<BalanceDateStrip> {
  static const double _chipWidth = 92;
  static const double _chipHeight = 40;
  static const double _gap = 8;

  late final ScrollController _scrollController;
  late DateTime _start;

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
    _scrollController = ScrollController();
    _resetWindow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected(animate: false);
    });
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
    final days = List.generate(
      _totalDays,
      (index) => _start.add(Duration(days: index)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: _chipHeight,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: days.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: _gap),
                itemBuilder: (context, index) {
                  final day = days[index];
                  final isSelected =
                      day.year == selected.year &&
                      day.month == selected.month &&
                      day.day == selected.day;

                  return InkWell(
                    onTap: () => widget.onPick(day),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: _chipWidth,
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
              child: Icon(
                Icons.calendar_month_outlined,
                size: 20,
                color: widget.calendarIconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
