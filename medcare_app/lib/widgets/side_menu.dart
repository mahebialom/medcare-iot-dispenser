import 'dart:ui';
import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';
import 'status_bar_style.dart';

/// Right-side sliding menu — opened from the header's hamburger icon
/// (replaces the old single settings-gear button). Slides in from the
/// right over the current screen, with the left portion of the screen
/// blurred/dimmed underneath rather than fully hidden.
///
/// Every menu item opens a FULL-SCREEN page (its own Scaffold, AppBar,
/// and back button) pushed on top of everything — including the
/// header/tab bar — rather than being embedded inside the existing tab
/// shell. "Device Settings" wraps the existing SettingsScreen widget
/// (the actual Wi-Fi/low-stock config) full-screen. "Settings" and the
/// rest (Account Management, About, Privacy Policy) are placeholder
/// full-screen pages, ready for you to build out content into
/// individually later.
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

class _SideMenuOverlay extends StatelessWidget {
  const _SideMenuOverlay({required this.animation, required this.c, required this.isDark});
  final Animation<double> animation;
  final AppColors c;
  final bool isDark;

  // Panel occupies roughly the right half of the screen, so the
  // blurred backdrop covers the left portion up to about the middle —
  // adjust this fraction if you want the panel wider/narrower.
  static const _panelWidthFraction = 0.70;

  @override
  Widget build(BuildContext context) {
    final panelWidth = MediaQuery.of(context).size.width * _panelWidthFraction;

    return Stack(
      children: [
        // Blurred, dimmed backdrop over the current screen — tapping
        // it dismisses the menu, same as tapping outside a modal sheet.
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final value = animation.value;
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
                  parent: animation,
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
                    child: SafeArea(child: _SideMenuContent(c: c, isDark: isDark)),
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
  const _SideMenuContent({required this.c, required this.isDark});
  final AppColors c;
  final bool isDark;

  /// Pushes [page] as a full-screen route ON TOP of the side menu —
  /// deliberately does NOT pop the menu first, so it stays in the
  /// navigation stack underneath. This means the system/app back
  /// button from within a section returns to the side menu (not all
  /// the way past it to the main screen) — matching what someone would
  /// expect from "go back" while inside a submenu.
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
                onPressed: () => Navigator.of(context).pop(),
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
                      body: _ComingSoonBody(
                          c: c, icon: Icons.manage_accounts_outlined)),
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
/// the rest for now).
class _FullScreenPage extends StatelessWidget {
  const _FullScreenPage(
      {required this.title, required this.c, required this.isDark, required this.body});
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