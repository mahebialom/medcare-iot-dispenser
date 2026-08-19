import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/tray_painter.dart';

class TrayScreen extends StatefulWidget {
  const TrayScreen({super.key, required this.c});
  final AppColors c;

  @override
  State<TrayScreen> createState() => _TrayScreenState();
}

class _TrayScreenState extends State<TrayScreen> with SingleTickerProviderStateMixin {
  static const _traySize = Size(220, 220);

  late final AnimationController _rotController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late Animation<double> _angleAnim = AlwaysStoppedAnimation(TrayPainter.slotCenterAngle(0));

  int _displaySlot = 0;
  int? _lastSyncedDeviceSlot;
  bool _initialized = false;

  /// Animates the pointer from wherever it currently is to `target`,
  /// always going forward/clockwise — a real stepper motor never
  /// reverses direction, so neither does this.
  void _animateToSlot(int target) {
    if (_rotController.isAnimating || target == _displaySlot) return;
    final diff = ((target - _displaySlot) % 5 + 5) % 5;
    if (diff == 0) return;

    final fromAngle = TrayPainter.slotCenterAngle(_displaySlot);
    final toAngle = fromAngle + diff * (72 * math.pi / 180);

    setState(() {
      _angleAnim = Tween<double>(begin: fromAngle, end: toAngle)
          .animate(CurvedAnimation(parent: _rotController, curve: Curves.easeInOutCubic));
    });
    _rotController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _displaySlot = target);
    });
  }

  void _handleTap(int slot, AppState app) {
    if (_rotController.isAnimating) return;
    if (!app.slots[slot].enabled) return;
    if (app.status.mode != 'idle') return; // mirrors firmware's STATE_IDLE guard
    _animateToSlot(slot);
    app.dispenseSlot(slot);
  }

  @override
  void dispose() {
    _rotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = context.watch<AppState>();

    if (!_initialized) {
      // First build — snap straight to whatever the device already
      // reports, no animation for the initial position.
      _initialized = true;
      _displaySlot = app.status.currentSlot;
      _lastSyncedDeviceSlot = app.status.currentSlot;
      _angleAnim = AlwaysStoppedAnimation(TrayPainter.slotCenterAngle(_displaySlot));
    } else if (_lastSyncedDeviceSlot != app.status.currentSlot && !_rotController.isAnimating) {
      // The device's real position changed and it didn't come from our
      // own tap (e.g. another caregiver's phone dispensed, or a
      // schedule fired automatically) — animate to match reality.
      _lastSyncedDeviceSlot = app.status.currentSlot;
      if (app.status.currentSlot != _displaySlot) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _animateToSlot(app.status.currentSlot);
        });
      }
    }

    final busy = app.status.mode != 'idle';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -16.5), // <-- Move text slightly UP
              child: Text(
                'CIRCULAR TRAY · 5 COMPARTMENTS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted),
              ),
          ),
          ),
          if (app.status.mode == 'refill')
            ElevatedButton.icon(
              onPressed: () => app.exitRefill(),
              icon: const Icon(Icons.check_circle_outline, size: 15, color: Colors.white),
              label: const Text('Exit Refill',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.amber,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )
          else if (app.status.mode == 'active')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.amberBg, borderRadius: BorderRadius.circular(8)),
              child: Text('Busy', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.amber)),
            )
          else
            OutlinedButton.icon(
              onPressed: () => app.startRefill(),
              icon: Icon(Icons.autorenew, size: 15, color: c.primary),
              label: Text('Start Refill',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.primary.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTapUp: (details) {
              final tapped = slotAtPosition(details.localPosition, _traySize);
              if (tapped != null) _handleTap(tapped, app);
            },
            child: SizedBox(
              width: _traySize.width,
              height: _traySize.height,
              child: AnimatedBuilder(
                animation: _angleAnim,
                builder: (context, _) => CustomPaint(
                  painter: TrayPainter(
                    slots: app.slots,
                    activeSlot: _displaySlot,
                    pointerAngle: _rotController.isAnimating
                        ? _angleAnim.value
                        : TrayPainter.slotCenterAngle(_displaySlot),
                    isRotating: _rotController.isAnimating,
                    borderColor: c.border,
                    primaryColor: c.primary,
                    textColor: c.ink,
                    mutedColor: c.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          busy
              ? 'Device is ${app.status.mode == 'refill' ? 'in refill mode' : 'busy'}. Try again shortly'
              : 'Tap a compartment or a slot to force dispense',
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: app.slots.map((s) {
            final active = _displaySlot == s.index;
            final canTap = s.enabled && !busy && !_rotController.isAnimating;
            final slotColor = TrayPainter.colorFor(s.index);
            return InkWell(
              onTap: canTap ? () => _handleTap(s.index, app) : null,
              borderRadius: BorderRadius.circular(14),
              child: Opacity(
                opacity: s.enabled ? 1 : 0.5,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: slotColor.withOpacity(active ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: slotColor.withOpacity(active ? 1 : 0.55), width: active ? 1.8 : 1.3),
                    boxShadow: [
                      BoxShadow(
                        color: active ? slotColor.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                        blurRadius: active ? 14 : 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: slotColor,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text('${s.index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(s.medicineName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c.ink)),
                          ),
                          if (active)
                            Icon(Icons.radio_button_checked, size: 13, color: slotColor),
                        ]),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.cardBg.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${s.quantity} tabs',
                              style: TextStyle(fontSize: 10, color: c.muted, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}