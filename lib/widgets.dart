import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// 偵測雙指張開／捏合，但不影響一般的捲動
class PinchDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPinchIn;
  final VoidCallback? onPinchOut;
  const PinchDetector({super.key, required this.child, this.onPinchIn, this.onPinchOut});

  @override
  State<PinchDetector> createState() => _PinchDetectorState();
}

class _PinchDetectorState extends State<PinchDetector> {
  final Map<int, Offset> _pts = <int, Offset>{};
  double? _startDist;
  bool _fired = false;

  double _dist() {
    final v = _pts.values.toList();
    return (v[0] - v[1]).distance;
  }

  void _remove(PointerEvent e) {
    _pts.remove(e.pointer);
    if (_pts.length < 2) _startDist = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _pts[e.pointer] = e.position;
        if (_pts.length == 2) {
          _startDist = math.max(_dist(), 1);
          _fired = false;
        }
      },
      onPointerMove: (e) {
        if (!_pts.containsKey(e.pointer)) return;
        _pts[e.pointer] = e.position;
        if (_pts.length == 2 && _startDist != null && !_fired) {
          final r = _dist() / _startDist!;
          if (r > 1.35) {
            _fired = true;
            HapticFeedback.selectionClick();
            widget.onPinchOut?.call();
          } else if (r < 0.72) {
            _fired = true;
            HapticFeedback.selectionClick();
            widget.onPinchIn?.call();
          }
        }
      },
      onPointerUp: _remove,
      onPointerCancel: _remove,
      child: widget.child,
    );
  }
}

TextStyle yearStyle(BuildContext context, double size) => TextStyle(
      fontFamily: 'serif',
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.05,
      color: Theme.of(context).colorScheme.onSurface,
    );

class Dot extends StatelessWidget {
  final Color color;
  final double size;
  final bool ring;
  const Dot(this.color, {super.key, this.size = 8, this.ring = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: ring ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.2) : null,
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  final String text;
  const InfoChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}

/// 一筆事件在列表中的樣子（統計頁也用）
class EventListTile extends StatelessWidget {
  final LifeEvent e;
  final VoidCallback? onTap;
  final String? trailing;
  const EventListTile(this.e, {super.key, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cat = categoryOf(e.category);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(padding: const EdgeInsets.only(top: 6), child: Dot(cat.color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(e.dateText(), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(trailing!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const SectionCard({super.key, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
