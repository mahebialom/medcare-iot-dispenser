import 'dart:ui';
import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';
import 'status_bar_style.dart';
import '../screens/account_management_screen.dart';

/// Right-side sliding menu — opened from the header's hamburger icon
/// (replaces the old single settings-gear button). Slides in from the
/// right over the current screen, with the left portion of the screen
/// blurred/dimmed underneath rather than fully hidden.
///
/// IMPORTANT: menu destinations (Settings, Device Settings, etc.) are
/// NOT pushed onto the app's main Navigator. They live in a NESTED
/// Navigator scoped to this menu instead. Reason: pushing an opaque
/// full-screen page onto the SAME Navigator that owns this blurred,
/// non-opaque route caused Flutter to stop painting this route while
/// obscured (a normal optimization) — so popping back caused one
/// visible frame where the blur hadn't caught up yet (a flash of the
/// unblurred dashboard). With a nested Navigator, opening/closing a
/// section never touches the outer route at all, so it's never
/// obscured and never needs to "catch up" — no flash.
///
/// The system/app back button still does the right thing without any
/// extra code: Flutter's Navigator automatically bubbles a pop to the
/// parent Navigator once the nested one has nothing left to pop — so
/// back-from-a-section returns to the menu list, and back-from-the-
/// menu-list closes the whole overlay.
///
/// [isDark] is threaded through to every _FullScreenPage so its status
/// bar icon color matches the CURRENT theme's card background, rather
/// than assuming a fixed light surface — see StatusBarStyle usage below.
Future<void> showSideMenu(BuildContext context, AppColors c, bool isDark) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor:
          Colors.transparent, // we draw our own blurred/dimmed backdrop below
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _SideMenuOverlay(animation: animation, c: c, isDark: isDark);
      },
    ),
  );
}

class _SideMenuOverlay extends StatefulWidget {
  const _SideMenuOverlay(
      {required this.animation, required this.c, required this.isDark});
  final Animation<double> animation;
  final AppColors c;
  final bool isDark;

  @override
  State<_SideMenuOverlay> createState() => _SideMenuOverlayState();
}

class _SideMenuOverlayState extends State<_SideMenuOverlay> {
  final _innerNavKey = GlobalKey<NavigatorState>();

  // Panel occupies roughly the right half of the screen, so the
  // blurred backdrop covers the left portion up to about the middle —
  // adjust this fraction if you want the panel wider/narrower.
  static const _panelWidthFraction = 0.70;

  /// Closes the WHOLE overlay — the outer route this widget belongs
  /// to. `context` here is this State's own context, whose nearest
  /// Navigator ancestor is the app's main Navigator (the inner one is
  /// built further down the tree, inside the Navigator widget below,
  /// so it's never in the ancestor chain for this method).
  void _closeMenu() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isDark = widget.isDark;
    final panelWidth = MediaQuery.of(context).size.width * _panelWidthFraction;

    return Stack(
      children: [
        // Blurred, dimmed backdrop over the current screen — tapping
        // it dismisses the menu, same as tapping outside a modal sheet.
        GestureDetector(
          onTap: _closeMenu,
          child: AnimatedBuilder(
            animation: widget.animation,
            builder: (context, _) {
              final value = widget.animation.value;
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6 * value, sigmaY: 6 * value),
                child: Container(color: Colors.black.withOpacity(0.25 * value)),
              );
            },
          ),
        ),
        // The panel itself, sliding in from the right — frosted glass:
        // blurred + semi-transparent, so it hints at what's behind it
        // rather than sitting on solid white.
        Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
              CurvedAnimation(
                  parent: widget.animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic),
            ),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: panelWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: c.cardBg.withOpacity(0.45),
                    border: Border(
                        left: BorderSide(color: c.border.withOpacity(0.4))),
                  ),
                  // Material ancestor required by ListTile (used inside
                  // _MenuTile) — transparency type so it doesn't paint
                  // its own opaque background over the blur/tint set
                  // above on the Container.
                  child: Material(
                    type: MaterialType.transparency,
                    child: SafeArea(
                      // NESTED Navigator — see class doc comment above
                      // for why. Its single initial route is the menu
                      // list; _MenuTile.onTap pushes further routes
                      // (Settings, About, etc.) onto THIS Navigator,
                      // not the app's main one.
                      child: Navigator(
                        key: _innerNavKey,
                        onGenerateRoute: (settings) => MaterialPageRoute(
                          builder: (_) => _SideMenuContent(
                            c: c,
                            isDark: isDark,
                            onCloseMenu: _closeMenu,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SideMenuContent extends StatelessWidget {
  const _SideMenuContent(
      {required this.c, required this.isDark, required this.onCloseMenu});
  final AppColors c;
  final bool isDark;
  final VoidCallback onCloseMenu;

  /// Pushes [page] as a full-screen route ON TOP of the NESTED
  /// Navigator this content lives in (Navigator.of(context) resolves
  /// to the nearest ancestor Navigator, which is the inner one — see
  /// _SideMenuOverlayState.build()). This never touches the outer
  /// blurred route at all, which is exactly what avoids the
  /// obscured-route repaint flash.
  void _openFullScreen(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: c.cardBg.withOpacity(
              0.2), // slightly different tint than the panel behind it
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    gradient: c.headerGrad,
                    borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Text('💊', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('MedCare IoT',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: c.ink)),
              ),
              IconButton(
                icon: Icon(Icons.close, color: c.muted),
                onPressed:
                    onCloseMenu, // closes the WHOLE overlay, not just this inner route
              ),
            ],
          ),
        ),
        // Divider(color: c.border, height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 0),
            children: [
              _MenuTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                c: c,
                onTap: () => _openFullScreen(
                  context,
                  _FullScreenPage(
                      title: 'Settings',
                      c: c,
                      isDark: isDark,
                      body: _ComingSoonBody(c: c, icon: Icons.tune_outlined)),
                ),
              ),
              _MenuTile(
                icon: Icons.manage_accounts_outlined,
                label: 'Account Management',
                c: c,
                onTap: () => _openFullScreen(
                  context,
                  _FullScreenPage(
                      title: 'Account Management',
                      c: c,
                      isDark: isDark,
                      body: AccountManagementScreen(c: c)),
                ),
              ),
              _MenuTile(
                icon: Icons.tune_outlined,
                label: 'Device Settings',
                c: c,
                onTap: () => _openFullScreen(
                  context,
                  _FullScreenPage(
                      title: 'Device Settings',
                      c: c,
                      isDark: isDark,
                      body: SettingsScreen(c: c)),
                ),
              ),
              _MenuTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                c: c,
                onTap: () => _openFullScreen(
                  context,
                  _FullScreenPage(
                      title: 'Privacy Policy',
                      c: c,
                      isDark: isDark,
                      body: _ComingSoonBody(
                          c: c, icon: Icons.privacy_tip_outlined)),
                ),
              ),
              _MenuTile(
                icon: Icons.info_outline,
                label: 'About',
                c: c,
                onTap: () => _openFullScreen(
                  context,
                  _FullScreenPage(
                      title: 'About',
                      c: c,
                      isDark: isDark,
                      body: _ComingSoonBody(c: c, icon: Icons.info_outline)),
                ),
              ),
            ],
          ),
        ),
        //Divider(color: c.border, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text('App Version 1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.muted)),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(
      {required this.icon,
      required this.label,
      required this.c,
      required this.onTap});
  final IconData icon;
  final String label;
  final AppColors c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: c.primary, size: 20),
      title: Text(label,
          style: TextStyle(
              fontSize: 14, color: c.ink, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}

/// Shared full-screen wrapper for every menu destination — its own
/// Scaffold, AppBar with a back button, themed to match the app's
/// current color scheme. [body] is whatever that destination's actual
/// content is (SettingsScreen for "Device Settings", placeholders for
/// the rest for now). The AppBar's default back button automatically
/// pops the nested Navigator this page lives in (see _SideMenuContent
/// doc comment) — no extra wiring needed for "back returns to menu".
class _FullScreenPage extends StatelessWidget {
  const _FullScreenPage(
      {required this.title,
      required this.c,
      required this.isDark,
      required this.body});
  final String title;
  final AppColors c;
  final bool isDark;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle(
      // Dark theme's cardBg is a dark surface → white icons.
      // Light theme's cardBg is a light surface → dark icons.
      brightness: isDark ? Brightness.dark : Brightness.light,
      child: Scaffold(
        backgroundColor: c.cardBg,
        appBar: AppBar(
          backgroundColor: c.cardBg,
          elevation: 0,
          foregroundColor: c.ink,
          title: Text(title,
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.bold, fontSize: 16)),
          iconTheme: IconThemeData(color: c.ink),
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}

/// Placeholder body for menu destinations not built out yet.
class _ComingSoonBody extends StatelessWidget {
  const _ComingSoonBody({required this.c, required this.icon});
  final AppColors c;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: c.muted),
          const SizedBox(height: 12),
          Text('Coming soon', style: TextStyle(fontSize: 14, color: c.muted)),
        ],
      ),
    );
  }
}
