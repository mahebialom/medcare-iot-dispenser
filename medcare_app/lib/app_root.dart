import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/app_notification.dart';
import 'state/app_state.dart';
import 'theme/app_colors.dart';
import 'widgets/theme_reveal.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tray_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/history_screen.dart';
import 'screens/caregiver_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/side_menu.dart';
import 'widgets/status_bar_style.dart';
import 'widgets/app_toast.dart';
import 'auth_gate.dart';

const _tabLabels = ['Dashboard', 'Tray', 'Schedule', 'History', 'Caregiver'];
const _tabIcons = ['⬡', '⟳', '⏰', '📋', '👥'];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

/// "Tue 4 Aug" — no `intl` package needed for just this.
String _formatToday() {
  final now = DateTime.now();
  return '${_weekdayShort[now.weekday - 1]} ${now.day} ${_monthShort[now.month - 1]}';
}

/// Time-aware instead of a hardcoded "Good morning" — reads correctly
/// no matter when someone actually opens the app.
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Prefers the signed-in user's real name over a hardcoded placeholder
/// — falls back to the part of their email before '@' if no display
/// name is set, then to a generic label if neither is available.
String _greetingName() {
  final user = FirebaseAuth.instance.currentUser;
  final displayName = user?.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  final email = user?.email ?? '';
  if (email.isNotEmpty) return email.split('@').first;
  return 'there';
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeReveal(
      isDark: false,
      builder: (context, isDark) {
        final c = isDark ? AppColors.dark : AppColors.light;
        return Theme(
          data: c.themeData(isDark ? Brightness.dark : Brightness.light),
          child: _Shell(c: c, isDark: isDark),
        );
      },
    );
  }
}

/// A header icon button styled to match the JSX prototype: a small
/// translucent white "pill" behind the icon, not a bare IconButton
/// (which has no background of its own). Fixed square size so every
/// pill matches, regardless of how wide each icon/emoji glyph is.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  static const _size = 36.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.c, required this.isDark});
  final AppColors c;
  final bool isDark;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  // Owned here (not created inline in build()) so it survives Provider
  // rebuilds — a fresh PageController every build would break swipe
  // animation and reset scroll position on every notifyListeners().
  late final PageController _pageController =
      PageController(initialPage: context.read<AppState>().activeTab);

  @override
  void initState() {
    super.initState();
    // A one-shot message left for us by whatever screen just got the
    // user HERE — sign-in (either method), signup, or username
    // creation all set this right before AuthGate swaps to AppRoot.
    // Consumed and cleared immediately so it can never show twice. See
    // the doc comment on pendingDashboardMessage in auth_gate.dart for
    // how a first-time Google sign-in's message gets correctly
    // overwritten by the username-creation message instead of both
    // showing.
    final pending = AuthGate.authGateKey.currentState?.pendingDashboardMessage;
    if (pending != null) {
      AuthGate.authGateKey.currentState?.pendingDashboardMessage = null;
      // Deferred to after the first frame — a live Overlay/context for
      // the toast isn't guaranteed to be ready mid-initState().
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAppToast(context, pending);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Tapping a tab button drives the PageView programmatically.
  void _goToTab(int i) {
    context.read<AppState>().setTab(i);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleThemeTap(BuildContext buttonContext) {
    // Find the enclosing ThemeRevealState so the moon/sun button can
    // trigger the circular wipe from its own on-screen position.
    final revealState =
        buttonContext.findAncestorStateOfType<ThemeRevealState>();
    final box = buttonContext.findRenderObject() as RenderBox;
    final globalCenter = box.localToGlobal(box.size.center(Offset.zero));
    revealState?.reveal(globalCenter);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isDark = widget.isDark;
    final app = context.watch<AppState>();
    final pending = app.totalToday - app.takenToday;
    // Real status bar height for this device — used to push the
    // header's content down below it while letting the gradient
    // itself paint all the way to the true top of the screen (see
    // SafeArea(top: false) below).
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return StatusBarStyle(
        brightness: Brightness.dark,
        child: Scaffold(
          backgroundColor: c.cardBg,
          body: SafeArea(
            // top: false — the header gradient bleeds under the status
            // bar instead of leaving a plain Scaffold-background gap
            // above it (was showing as a stark white strip in light
            // mode). Header content is pushed down by statusBarHeight
            // via its own padding below, so nothing sits under the
            // status bar icons.
            top: false,
            child: Column(children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20, statusBarHeight + 16, 20, 14),
                decoration: BoxDecoration(gradient: c.headerGrad),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Text('MEDCARE IOT',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white70,
                                            letterSpacing: 1)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: app.status.online
                                            ? Colors.white24
                                            : Colors.white10,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                          app.status.online
                                              ? '● MQTT'
                                              : '○ Offline',
                                          style: const TextStyle(
                                              fontSize: 9,
                                              color: Colors.white)),
                                    ),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text('${_greeting()}\n${_greetingName()}',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                ]),
                          ),
                          Row(children: [
                            Builder(
                              builder: (btnContext) => _HeaderIcon(
                                onTap: () => _handleThemeTap(btnContext),
                                child: Text(isDark ? '☀️' : '🌙',
                                    style: const TextStyle(fontSize: 16)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (btnContext) =>
                                  Stack(clipBehavior: Clip.none, children: [
                                _HeaderIcon(
                                  onTap: () =>
                                      _showNotifications(btnContext, app, c),
                                  child: const Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.white,
                                      size: 16),
                                ),
                                if (app.notifications.unreadCount > 0)
                                  Positioned(
                                    right: -3,
                                    top: -3,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      constraints: const BoxConstraints(
                                          minWidth: 16, minHeight: 16),
                                      decoration: BoxDecoration(
                                        color: c.red,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.9),
                                            width: 1.5),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        app.notifications.unreadCount > 9
                                            ? '9+'
                                            : '${app.notifications.unreadCount}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (btnContext) => _HeaderIcon(
                                onTap: () =>
                                    showSideMenu(btnContext, c, isDark),
                                child: const Icon(Icons.menu,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ── Today summary strip ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('📅 ${_formatToday()}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white)),
                              Text(
                                  '✅ ${app.takenToday} of ${app.totalToday} taken',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white)),
                              Text('⚠ $pending pending',
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFFFFCC44))),
                            ]),
                      ),
                    ]),
              ),

              if (!app.isOnline)
                Container(
                  width: double.infinity,
                  color: c.amberBg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.cloud_off, size: 14, color: c.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No connection — showing last synced data',
                        style: TextStyle(
                            fontSize: 11,
                            color: c.amber,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),

              // ── Tab bar ──
              Container(
                decoration: BoxDecoration(
                    color: c.panel,
                    border: Border(bottom: BorderSide(color: c.borderSoft))),
                child: Row(
                    children: List.generate(_tabLabels.length, (i) {
                  final active = app.activeTab == i;
                  return Expanded(
                    child: InkWell(
                      onTap: () => _goToTab(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: active ? c.primary : Colors.transparent,
                                width: 2.5),
                          ),
                        ),
                        child: Column(children: [
                          Text(_tabIcons[i],
                              style: TextStyle(
                                  fontSize: 16,
                                  color: active ? c.primary : c.muted)),
                          const SizedBox(height: 2),
                          Text(
                            _tabLabels[i],
                            style: TextStyle(
                              fontSize: 9.5,
                              color: active ? c.primary : c.muted,
                              fontWeight:
                                  active ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                })),
              ),

              // ── Content ──
              Expanded(
                child: app.settingsOpen
                    ? SettingsScreen(c: c)
                    : PageView(
                        controller: _pageController,
                        onPageChanged: (i) =>
                            context.read<AppState>().setTab(i),
                        children: [
                          DashboardScreen(c: c),
                          TrayScreen(c: c),
                          ScheduleScreen(c: c),
                          HistoryScreen(c: c),
                          CaregiverScreen(c: c),
                        ],
                      ),
              ),
            ]),
          ),
        ));
  }
}

void _showNotifications(BuildContext context, AppState app, AppColors c) {
  app.notifications.markAllRead();
  showModalBottomSheet(
    context: context,
    backgroundColor:
        Colors.transparent, // painted below via BackdropFilter instead
    barrierColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: c.cardBg.withOpacity(0.45),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (ctx, scrollController) {
              final items = app.notifications.notifications;
              return Column(children: [
                // Centered drag handle, ~2.5x the old icon's visual size.
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 0),
                  child: Container(
                    width: 70,
                    height: 6,
                    decoration: BoxDecoration(
                      color: c.muted.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -7),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 0, 4),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Notifications',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: c.ink)),
                          Transform.translate(
                            offset: const Offset(-10, -1),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.of(ctx).pop(),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: c.muted.withOpacity(0.1),
                                    shape: BoxShape.rectangle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: c.muted,
                                    size: 23,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                  ),
                ),

                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text('No notifications yet',
                              style: TextStyle(color: c.muted, fontSize: 13)),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: items.length,
                          itemBuilder: (ctx, i) {
                            final n = items[i];
                            final IconData icon;
                            final Color color;
                            switch (n.type) {
                              case AppNotificationType.missed:
                                icon = Icons.event_busy;
                                color = c.red;
                              case AppNotificationType.stockLow:
                                icon = Icons.inventory_2_outlined;
                                color = c.amber;
                              case AppNotificationType.stockCritical:
                                icon = Icons.warning_amber_rounded;
                                color = c.red;
                              case AppNotificationType.upcomingReminder:
                                icon = Icons.access_time;
                                color = c.primary;
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: c.panel,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: c.border),
                              ),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                          color: color.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      alignment: Alignment.center,
                                      child: Icon(icon, color: color, size: 17),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(n.title,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: c.ink)),
                                            const SizedBox(height: 2),
                                            Text(n.body,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.text2)),
                                            const SizedBox(height: 4),
                                            Text(_relativeTime(n.timestamp),
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: c.muted)),
                                          ]),
                                    ),
                                  ]),
                            );
                          },
                        ),
                ),
              ]);
            },
          ),
        ),
      ),
    ),
  );
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
