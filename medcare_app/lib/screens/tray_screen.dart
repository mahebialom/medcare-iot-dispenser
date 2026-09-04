import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/tray_painter.dart';

class TrayScreen extends StatefulWidget {
  const TrayScreen({super.key, required this.c});
  final AppColors c;

  @override
  State<TrayScreen> createState() => _TrayScreenState();
}

class _TrayScreenState extends State<TrayScreen> with TickerProviderStateMixin {
  static const _traySize = Size(220, 220);

  late final AnimationController _rotController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late Animation<double> _angleAnim = AlwaysStoppedAnimation(TrayPainter.slotCenterAngle(0));

  // Drives the three-bouncing-dots loading icon on the Refill
  // Initiating button — separate from _rotController above (which is
  // for the tray's slot-to-slot rotation and has its own one-shot
  // forward() calls), so this can loop continuously and independently
  // via repeat()/stop() without any risk of the two interfering.
  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  int _displaySlot = 0;
  int? _lastSyncedDeviceSlot;
  bool _initialized = false;

  // ── "Refill Initiating…" transitional state ──
  // Tapping Start Refill only WRITES a command to Firebase — the
  // firmware has to pick it up off its SSE stream and actually flip
  // status.mode to "refill" before the real "Exit Refill" UI can show
  // (same request/no-ack gap as Restart Device in device_settings_screen.dart).
  // Without this, tapping Start Refill visibly did nothing for however
  // long that round trip takes. This fills that gap locally: a
  // pending flag drives a green button with an animating "..." while
  // waiting, cleared the moment app.status.mode actually becomes
  // "refill" (see build()) — or by the timeout below if it never does.
  bool _refillPending = false;
  int _pendingDots = 0;
  Timer? _pendingDotsTimer;
  Timer? _pendingTimeoutTimer;

  void _beginRefillPending() {
    setState(() {
      _refillPending = true;
      _pendingDots = 0;
    });
    _bounceController.repeat();
    _pendingDotsTimer?.cancel();
    _pendingDotsTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() => _pendingDots = (_pendingDots + 1) % 4);
    });
    // Safety net: if the dispenser is offline or just slow, don't leave
    // this button stuck on "Refill Initiating…" forever with no way out.
    _pendingTimeoutTimer?.cancel();
    _pendingTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _endRefillPending();
      showAppToast(context, 'No response from dispenser. Please Check your dispenser', isError: true);
    });
  }

  void _endRefillPending() {
    _pendingDotsTimer?.cancel();
    _pendingTimeoutTimer?.cancel();
    _pendingDotsTimer = null;
    _pendingTimeoutTimer = null;
    _bounceController.stop();
    _bounceController.value = 0;
    if (mounted) setState(() => _refillPending = false);
  }

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
    _bounceController.dispose();
    _pendingDotsTimer?.cancel();
    _pendingTimeoutTimer?.cancel();
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

    // Firmware confirmed the refill command took effect — drop the
    // local "Initiating…" placeholder and let the real Exit Refill
    // button (driven straight off app.status.mode below) take over.
    if (_refillPending && app.status.mode == 'refill') {
      _pendingDotsTimer?.cancel();
      _pendingTimeoutTimer?.cancel();
      _pendingDotsTimer = null;
      _pendingTimeoutTimer = null;
      _refillPending = false;
    }

    final busy = app.status.mode != 'idle' || _refillPending;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'CIRCULAR TRAY · 5 COMPARTMENTS',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: c.muted),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: (() {
            if (_refillPending) {
              // No fixed-width box needed here — this button is alone
              // on its own row now (not fighting the title for space
              // like before), and its label's rendered width is already
              // constant regardless of _pendingDots (the three dots
              // below are always present, just toggled transparent), so
              // there's nothing left for a fixed box to protect against.
              // It can just size to its own content like the other
              // three states do.
              return ElevatedButton.icon(
                onPressed: null,
                icon: _BouncingDots(animation: _bounceController),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Refill Initiating',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                    ...List.generate(
                      3,
                      (i) => Text('.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: i < _pendingDots ? Colors.white : Colors.transparent,
                          )),
                    ),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.green,
                  disabledBackgroundColor: c.green,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            }
            if (app.status.mode == 'refill') {
              return ElevatedButton.icon(
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
              );
            }
            if (app.status.mode == 'active') {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: c.amberBg, borderRadius: BorderRadius.circular(8)),
                child: Text('Busy', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.amber)),
              );
            }
            return OutlinedButton.icon(
              onPressed: () {
                app.startRefill();
                _beginRefillPending();
              },
              icon: Icon(Icons.autorenew, size: 15, color: c.primary),
              label: Text('Start Refill',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.primary.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
          })(),
        ),
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
        const SizedBox(height: 14),
        Text(
          _refillPending
              ? 'Waiting for the dispenser to start refill mode'
              : busy
                  ? 'Device is ${app.status.mode == 'refill' ? 'in refill mode' : 'busy'}. Try again shortly'
                  : 'Tap a compartment or a slot to force dispense',
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
        const SizedBox(height: 8),
        GridView.count(
          padding: EdgeInsets.zero,
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

/// Three small dots that bounce up and down in sequence — the loading
/// icon for the Refill Initiating button, driven by the SAME repeating
/// [animation] the caller starts/stops (see _beginRefillPending /
/// _endRefillPending in _TrayScreenState), rather than owning its own
/// controller. Each dot reads a phase-shifted slice of the same 0→1
/// cycle (`+ index * 0.2`), so the three of them bounce in a staggered
/// wave instead of all moving in lockstep.
class _BouncingDots extends StatelessWidget {
  const _BouncingDots({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 13,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (i) => _dot(i)),
      ),
    );
  }

  Widget _dot(int index) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = (animation.value + index * 0.2) % 1.0;
        // 0 → 1 → 0 triangular bounce height per cycle, via a half
        // sine wave — smooth up-then-down motion with no linear snap
        // at the top or bottom of the bounce.
        final dy = -6 * math.sin(t * math.pi);
        return Transform.translate(offset: Offset(0, dy+3), child: child);
      },
      child: const _Dot(),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    );
  }
}