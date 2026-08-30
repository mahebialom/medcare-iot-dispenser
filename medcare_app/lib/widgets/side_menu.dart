import 'dart:ui';
import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';
import 'status_bar_style.dart';
import '../screens/account_management_screen.dart';
import '../screens/device_settings_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/about_screen.dart';
import '../main.dart';

/// Right-side sliding menu — opened from the header's hamburger icon
/// (replaces the old single settings-gear button). Slides in from the
/// right over the current screen, with the left portion of the screen
/// blurred/dimmed underneath rather than fully hidden.
///
/// IMPORTANT: menu destinations (Settings, Device Settings, etc.) are
/// pushed onto the app's MAIN (root) Navigator — not the nested one
/// this menu used to use for them — so they render truly full-screen
/// instead of being confined to the side panel's fixed width. See
/// _SideMenuContent._openFullScreen() for the full explanation of why,
/// and how that's done without reintroducing the blur-flash bug this
/// nested Navigator was originally built to avoid.
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

  // Swipe-to-close tuning. Dragging the panel RIGHTWARD (toward where
  // it slides out to) by more than this FRACTION of the panel's own
  // width closes it, even on a slow drag. A fast rightward flick
  // closes it regardless of distance travelled if it clears the
  // velocity threshold — matches how native side-menus feel (a quick
  // flick dismisses even with barely any travel).
  static const _closeDistanceFraction = 0.30;
  static const _closeFlingVelocity = 400.0; // logical px/sec, rightward

  // Cumulative rightward drag distance for the CURRENT gesture only —
  // reset to 0 at the end of every drag (successful or not). Leftward
  // movement still accumulates (as a negative number) and simply never
  // clears the positive threshold, so dragging left does nothing,
  // exactly like today.
  double _dragExtent = 0;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _dragExtent += details.delta.dx;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final panelWidth = MediaQuery.of(context).size.width * _panelWidthFraction;
    final velocity = details.primaryVelocity ?? 0;
    final draggedFarEnough = _dragExtent > panelWidth * _closeDistanceFraction;
    final flungRight = velocity > _closeFlingVelocity;
    _dragExtent = 0;
    if (draggedFarEnough || flungRight) {
      _closeMenu();
    }
  }

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
            // Swipe-right-to-close: wraps the whole panel so a drag
            // starting anywhere on it (including over the menu list)
            // is recognized. GestureDetector's horizontal drag axis
            // doesn't conflict with the ListView inside — that scrolls
            // vertically, so Flutter's gesture arena resolves them
            // independently rather than competing for the same
            // gesture.
            child: GestureDetector(
              onHorizontalDragUpdate: _handleHorizontalDragUpdate,
              onHorizontalDragEnd: _handleHorizontalDragEnd,
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
                    // Material ancestor required by ListTile (used
                    // inside _MenuTile) — transparency type so it
                    // doesn't paint its own opaque background over the
                    // blur/tint set above on the Container.
                    child: Material(
                      type: MaterialType.transparency,
                      child: SafeArea(
                        // NESTED Navigator — still used for the menu
                        // list itself (its single initial route).
                        // Destination screens (Settings, Account
                        // Management, etc.) no longer push onto this
                        // one — see _SideMenuContent._openFullScreen()
                        // below.
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

  /// Pushes [page] as a full-screen destination (Settings, Account
  /// Management, Device Settings, etc.) on top of the whole app —
  /// NOT confined to the side panel's fixed width, and WITHOUT closing
  /// the side-menu overlay underneath.
  ///
  /// Two things had to both be true to get this right:
  ///
  /// 1. `Navigator.of(context, rootNavigator: true)` — pushes onto the
  ///    app's MAIN Navigator instead of the nested one this content
  ///    lives in. The nested Navigator is confined to the panel's
  ///    fixed `panelWidth` Container, so anything pushed on it (the
  ///    old behavior) was stuck at ~70% screen width. Pushing on the
  ///    root Navigator instead makes the destination render truly
  ///    full-screen.
  ///
  /// 2. `opaque: false` on the pushed route — this is what avoids the
  ///    ORIGINAL blur-flash bug (see showSideMenu's doc comment for
  ///    the full history), NOT which Navigator it's pushed on. An
  ///    opaque route (MaterialPageRoute's default) makes Flutter stop
  ///    painting whatever's underneath once it's fully obscured — so
  ///    the side-menu overlay (backdrop blur + panel) would stop
  ///    rendering while this page is open. Popping back would then
  ///    show one stale, unblurred frame before the backdrop "caught
  ///    up." With `opaque: false`, the side-menu overlay keeps
  ///    painting underneath the whole time this page is open, so
  ///    there's nothing to catch up on: popping back reveals the
  ///    still-open, correctly-blurred side menu instantly.
  ///
  /// Deliberately does NOT call onCloseMenu() — the side-menu overlay
  /// route is left on the root Navigator's stack, right below this
  /// page, so the destination's back button naturally lands back on
  /// the open side menu instead of the bare dashboard.
  void _openFullScreen(BuildContext context, Widget page) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: c.cardBg.withOpacity(0), // slightly different tint than the panel behind it
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
                      body: AppSettingsScreen(c: c)),
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
                      body: PrivacyPolicyScreen(c: c)),
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
                      body: AboutScreen(c: c)),
                ),
              ),
            ],
          ),
        ),
        //Divider(color: c.border, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text('App Version ${appPackageInfo.version}',
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
/// the rest for now). The AppBar's default back button pops whichever
/// Navigator this page was pushed on — since _openFullScreen() above
/// pushes on the ROOT Navigator, that pop reveals the side-menu
/// overlay still sitting underneath (see that method's doc comment).
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