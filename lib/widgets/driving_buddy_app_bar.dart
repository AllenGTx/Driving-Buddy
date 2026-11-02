import 'dart:io';
import 'package:flutter/material.dart';
import '../models/account_config.dart';
import '../services/firebase_service.dart';
import '../routes/app_routes.dart';
import '../services/language_service.dart';

// ============================================================================
// LUXURY GT APP BAR WIDGET — Perfectly Centered Title, Edge-to-Edge Gradient
// ============================================================================

class DrivingBuddyAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final bool showProfileButton;
  final VoidCallback? onBack;
  final List<Widget>? trailing;

  const DrivingBuddyAppBar({
    super.key,
    this.title = 'Beranda',
    this.showBackButton = false,
    this.showProfileButton = true,
    this.onBack,
    this.trailing,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  State<DrivingBuddyAppBar> createState() => _DrivingBuddyAppBarState();
}

class _DrivingBuddyAppBarState extends State<DrivingBuddyAppBar> {
  @override
  void initState() {
    super.initState();
    _syncAvatarPhoto();
  }

  Future<void> _syncAvatarPhoto() async {
    final curUser = AuthService.currentUser;
    final curEmail = curUser?.email;
    final curUid = curUser?.uid;
    if (curUser != null) {
      // 1. Cek cache lokal SharedPreferences terlebih dahulu (instan tanpa lag jaringan)
      final cached = await AccountConfig.getCustomPhoto(userEmail: curEmail, uid: curUid);
      if (cached != null && cached.trim().isNotEmpty) {
        AccountConfig.photoNotifier.value = cached.trim();
        return;
      }
      // 2. Jika belum ada di cache, ambil dari Firestore profil atau Firebase Auth
      try {
        final profile = await AuthService.getUserProfile();
        final p = (profile?['customPhotoUrl'] ?? profile?['photoUrl']) as String?;
        final photoToUse = (p != null && p.trim().isNotEmpty)
            ? p.trim()
            : (curUser.photoURL != null && curUser.photoURL!.trim().isNotEmpty
                ? curUser.photoURL!.trim()
                : null);

        if (photoToUse != null && photoToUse.isNotEmpty) {
          await AccountConfig.setCustomPhoto(photoToUse, userEmail: curEmail, uid: curUid);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final shouldShowBack = widget.showBackButton || (canPop && widget.onBack != null);

    // Use native AppBar so gradient stretches edge-to-edge automatically
    return AppBar(
      toolbarHeight: kToolbarHeight + 8,
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF26B1D), Color(0xFFD9560F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x55C25E21),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
      ),
      title: Text(
        (widget.title == 'Beranda' && LanguageService.instance.isEnglish) ? 'Home' : widget.title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      centerTitle: true,
      leading: shouldShowBack
          ? GestureDetector(
              onTap: widget.onBack ?? () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.only(left: 10),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(left: 14),
              child: SizedBox(
                height: 40,
                width: 40,
                child: Image.asset(
                  'assets/images/DrivingBuddyLogo_white_tight.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
      actions: [
        if (widget.trailing != null) ...widget.trailing!,
        if (widget.showProfileButton)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Builder(
              builder: (ctx) => GestureDetector(
                onTap: () async {
                  await Navigator.pushNamed(ctx, AppRoutes.settings);
                  if (mounted) setState(() {});
                },
                child: ValueListenableBuilder<String?>(
                  valueListenable: AccountConfig.photoNotifier,
                  builder: (context, photoUrl, _) {
                    final customPhoto = AccountConfig.photoNotifier.value;
                    final authPhoto = AuthService.currentUser?.photoURL;
                    final effectivePhoto = (customPhoto != null && customPhoto.trim().isNotEmpty)
                        ? customPhoto.trim()
                        : (photoUrl != null && photoUrl.trim().isNotEmpty
                            ? photoUrl.trim()
                            : (authPhoto != null && authPhoto.trim().isNotEmpty
                                ? authPhoto.trim()
                                : null));

                    Widget imageWidget = const Icon(Icons.person_rounded, color: Colors.white, size: 20);

                    if (effectivePhoto != null && effectivePhoto.isNotEmpty) {
                      if (effectivePhoto.startsWith('http')) {
                        imageWidget = Image.network(
                          effectivePhoto,
                          fit: BoxFit.cover,
                          width: 38,
                          height: 38,
                          errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                        );
                      } else {
                        final file = File(effectivePhoto);
                        if (file.existsSync()) {
                          imageWidget = Image.file(
                            file,
                            fit: BoxFit.cover,
                            width: 38,
                            height: 38,
                            errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                          );
                        }
                      }
                    }

                    return Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                      ),
                      child: ClipOval(child: imageWidget),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
