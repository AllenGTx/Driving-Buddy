import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/theme_service.dart';
import 'core/app_colors.dart';
import 'widgets/ui/db_ui.dart';
import 'supabase_service.dart';
import 'models/account_config.dart';
import 'screens/main_shell.dart';
import 'routes/app_routes.dart';

// ============================================================================
// AUTH SCREEN (Login & Registrasi — World-Class Organic Topo & Luxury GT)
// References: Apple, Uber, Nike, Airbnb, Linear, Arc, Revolut, Strava, Spotify, Headspace
// ============================================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;

  // Animations
  late final AnimationController _slideCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  final ScrollController _scrollController = ScrollController();

  // Login fields
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  bool _loginLoading = false;
  String? _loginError;
  bool _loginObscure = true;

  // Register fields
  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPassword = TextEditingController();
  final _regConfirm = TextEditingController();
  bool _regLoading = false;
  String? _regError;
  String? _regSuccess;
  bool _regObscure = true;

  // Google Login state
  bool _googleLoading = false;

  void _setError(String msg, {bool isRegister = false}) {
    if (!mounted) return;
    setState(() {
      if (isRegister) {
        _regError = msg;
      } else {
        _loginError = msg;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging) {
        setState(() {});
      }
    });

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    _slideAnim = Tween(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _tab.dispose();
    _slideCtrl.dispose();
    _scrollController.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPassword.dispose();
    _regConfirm.dispose();
    super.dispose();
  }

  // ── Lupa Kata Sandi Dialog ──────────────────
  Future<void> _showForgotPasswordDialog() async {
    final emailCtrl = TextEditingController(text: _loginEmail.text.trim());
    String? dialogError;
    String? dialogSuccess;
    bool dialogLoading = false;
    final isDark = ThemeService.instance.isDarkMode;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF131B2E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark ? const Color(0xFF22304C) : const Color(0xFFE2E8F0),
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF26B1D).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFF26B1D), size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'Reset Kata Sandi',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Masukkan email terdaftar Anda untuk menerima tautan pemulihan kata sandi.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 14),
              if (dialogError != null) ...[
                _buildAlertBox(dialogError!, isError: true),
                const SizedBox(height: 12),
              ],
              if (dialogSuccess != null) ...[
                _buildAlertBox(dialogSuccess!, isError: false),
                const SizedBox(height: 12),
              ],
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0A0F1D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF22304C) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'nama@email.com',
                    hintStyle: TextStyle(
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.alternate_email_rounded,
                      color: Color(0xFFF26B1D),
                      size: 18,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 16, left: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Tutup',
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF26B1D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: dialogLoading
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty) {
                        setDState(() => dialogError = 'Email tidak boleh kosong.');
                        return;
                      }
                      setDState(() {
                        dialogLoading = true;
                        dialogError = null;
                        dialogSuccess = null;
                      });
                      try {
                        await AuthService.resetPassword(email);
                        setDState(() {
                          dialogLoading = false;
                          dialogSuccess = 'Tautan reset telah dikirim ke email kamu! Silakan cek kotak masuk.';
                        });
                      } on FirebaseAuthException catch (e) {
                        setDState(() {
                          dialogLoading = false;
                          dialogError = _xlErr(e.message ?? 'user-not-found');
                        });
                      } catch (_) {
                        setDState(() {
                          dialogLoading = false;
                          dialogError = 'Gagal mengirim email reset. Pastikan email benar.';
                        });
                      }
                    },
              child: dialogLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Kirim Link',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Validasi Pendaftaran ────────────────────
  String? _validateEmailAddress(String email) {
    if (email.isEmpty) return 'Email tidak boleh kosong.';
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
    );
    if (!emailRegex.hasMatch(email)) {
      return 'Format email tidak valid (contoh: nama@domain.com).';
    }
    final parts = email.split('@');
    if (parts.length != 2) return 'Format email tidak valid.';
    final domain = parts[1].toLowerCase();
    if (!domain.contains('.')) return 'Domain email tidak lengkap.';
    final tld = domain.split('.').last;
    if (tld.length < 2) return 'Domain email tidak valid.';
    return null;
  }

  String? _validatePasswordFormat(String password) {
    if (password.length < 8) {
      return 'Kata sandi minimal 8 karakter.';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Kata sandi harus mengandung minimal 1 huruf besar (A-Z).';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Kata sandi harus mengandung minimal 1 huruf kecil (a-z).';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Kata sandi harus mengandung minimal 1 angka (0-9).';
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Kata sandi harus mengandung minimal 1 simbol unik (!@#\$%^&* dll).';
    }
    return null;
  }

  // ── Dialog Verifikasi Email ─────────────────
  void _showVerificationDialog(String email) {
    final isDark = ThemeService.instance.isDarkMode;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool resending = false;
        String? resendMsg;
        return StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF131B2E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: isDark ? const Color(0xFF22304C) : const Color(0xFFE2E8F0),
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF26B1D).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mark_email_read_rounded, color: Color(0xFFF26B1D), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Verifikasi Email Dikirim',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tautan verifikasi telah kami kirimkan ke:',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF1E8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFFFD8C2),
                    ),
                  ),
                  child: Text(
                    email,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFFF8A4C) : const Color(0xFFC2410C),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A2015) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF5B3C11) : const Color(0xFFFCD34D),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'PENTING: Jika tidak muncul di Kotak Masuk, silakan periksa Folder Spam / Promosi dan tandai "Bukan Spam".',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFFCD34D) : Colors.amber.shade900,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (resendMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    resendMsg!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
            actionsPadding: const EdgeInsets.only(right: 16, bottom: 16, left: 16),
            actions: [
              TextButton(
                onPressed: resending
                    ? null
                    : () async {
                        setDState(() => resending = true);
                        try {
                          final user = AuthService.currentUser;
                          if (user != null) {
                            await user.sendEmailVerification();
                          }
                          setDState(() {
                            resending = false;
                            resendMsg = 'Link verifikasi berhasil dikirim ulang!';
                          });
                        } catch (e) {
                          setDState(() {
                            resending = false;
                            resendMsg = 'Gagal kirim ulang. Tunggu 1 menit.';
                          });
                        }
                      },
                child: resending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        'Kirim Ulang Link',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF26B1D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _loginEmail.text = email;
                  _tab.animateTo(0);
                  setState(() {
                    _loginError = null;
                  });
                },
                child: const Text(
                  'Kembali ke Masuk',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Login Action ────────────────────────────
  Future<void> _doLogin() async {
    FocusScope.of(context).unfocus();
    final email = _loginEmail.text.trim();
    final password = _loginPassword.text;

    if (email.isEmpty) {
      _setError('Email tidak boleh kosong.');
      return;
    }
    if (password.isEmpty) {
      _setError('Kata sandi tidak boleh kosong.');
      return;
    }

    setState(() {
      _loginLoading = true;
      _loginError = null;
    });

    try {
      await AuthService.login(
        email: email,
        password: password,
      );
      await AccountConfig.getPhotoUrl(userEmail: email);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errMsg = 'Kata sandi salah. Silakan periksa kembali.';
      final code = e.code.toLowerCase();

      if (code == 'user-not-found') {
        errMsg = 'Email tidak terdaftar di Driving Buddy.';
      } else if (code == 'wrong-password') {
        errMsg = 'Kata sandi salah. Silakan periksa kembali.';
      } else if (code == 'invalid-email') {
        errMsg = 'Format email tidak valid.';
      } else if (code == 'user-disabled') {
        errMsg = 'Akun ini telah dinonaktifkan.';
      } else if (code == 'network-request-failed') {
        errMsg = 'Koneksi internet bermasalah. Periksa jaringan Anda.';
      } else if (code == 'too-many-requests') {
        errMsg = 'Terlalu banyak percobaan gagal. Silakan tunggu beberapa saat.';
      } else if (code == 'invalid-credential') {
        try {
          final snapshot = await firestore
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();
          if (snapshot.docs.isEmpty) {
            errMsg = 'Email tidak terdaftar di Driving Buddy.';
          } else {
            errMsg = 'Kata sandi salah. Silakan periksa kembali.';
          }
        } catch (_) {
          errMsg = 'Email tidak terdaftar atau kata sandi salah.';
        }
      } else {
        errMsg = _xlErr(e.code);
      }
      _setError(errMsg);
    } catch (_) {
      _setError('Terjadi kesalahan saat masuk. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  // ── Register Action ─────────────────────────
  Future<void> _doRegister() async {
    FocusScope.of(context).unfocus();
    final name = _regName.text.trim();
    final email = _regEmail.text.trim();
    final password = _regPassword.text;
    final confirm = _regConfirm.text;

    if (name.isEmpty) {
      return _setError('Nama lengkap tidak boleh kosong.', isRegister: true);
    }

    final emailErr = _validateEmailAddress(email);
    if (emailErr != null) {
      return _setError(emailErr, isRegister: true);
    }

    final passErr = _validatePasswordFormat(password);
    if (passErr != null) {
      return _setError(passErr, isRegister: true);
    }

    if (password != confirm) {
      return _setError('Konfirmasi kata sandi tidak cocok.', isRegister: true);
    }

    setState(() {
      _regLoading = true;
      _regError = null;
      _regSuccess = null;
    });

    try {
      await AuthService.register(
        email: email,
        password: password,
        fullName: name,
      );

      setState(() {
        _regSuccess = 'Pendaftaran berhasil! Silakan periksa email verifikasi Anda.';
      });

      if (mounted) {
        _showVerificationDialog(email);
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Terjadi kesalahan pendaftaran.';
      final code = e.code.toLowerCase();
      if (code == 'email-already-in-use') {
        msg = 'Email ini sudah terdaftar. Silakan masuk menggunakan kata sandi Anda.';
      } else if (code == 'invalid-email') {
        msg = 'Format email tidak valid atau domain tidak dikenali.';
      } else if (code == 'weak-password') {
        msg = 'Kata sandi terlalu lemah. Ikuti kriteria kombinasi karakter.';
      } else if (code == 'network-request-failed') {
        msg = 'Koneksi internet bermasalah. Periksa jaringan Anda.';
      } else {
        msg = _xlErr(e.code);
      }
      _setError(msg, isRegister: true);
    } catch (e) {
      _setError('Terjadi kesalahan pendaftaran. Coba lagi.', isRegister: true);
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  // ── Google Sign In Action ───────────────────
  Future<void> _doGoogleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _googleLoading = true;
      _loginError = null;
      _regError = null;
    });
    try {
      await AuthService.signInWithGoogle().timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          throw 'Waktu login Google habis atau dibatalkan.';
        },
      );
      final gEmail = AuthService.currentUser?.email;
      final profile = await AuthService.getUserProfile();
      final customPhoto = profile?['photoUrl'] as String?;
      if (customPhoto != null && customPhoto.isNotEmpty) {
        await AccountConfig.setPhotoUrl(customPhoto, userEmail: gEmail);
      } else {
        await AccountConfig.getPhotoUrl(userEmail: gEmail);
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final code = e.code.toLowerCase();
        final msg = (e.message ?? '').toLowerCase();

        if (code == 'popup-closed-by-user' || code == 'cancelled' || code == 'canceled') {
          setState(() => _loginError = null);
        } else if (code == 'account-exists-with-different-credential' ||
            msg.contains('account already exists') ||
            msg.contains('different-credential') ||
            msg.contains('different credential')) {
          final gEmail = AuthService.lastAttemptedGoogleEmail;
          if (gEmail != null && gEmail.isNotEmpty) {
            _loginEmail.text = gEmail;
          }
          _tab.animateTo(0);
          _setError('Akun ${AuthService.lastAttemptedGoogleEmail ?? 'ini'} sudah terdaftar dengan Kata Sandi. Silakan masukkan kata sandi di atas.');
        } else if (code == 'missing-id-token' || msg.contains('id token')) {
          final gEmail = AuthService.lastAttemptedGoogleEmail;
          if (gEmail != null && gEmail.isNotEmpty) {
            _loginEmail.text = gEmail;
          }
          _tab.animateTo(0);
          _setError('Google ID Token tidak ditemukan. Silakan masuk menggunakan kata sandi akun.');
        } else {
          _setError(e.message ?? _xlErr(e.code));
        }
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('popup-closed-by-user') ||
            errStr.contains('closed by user') ||
            errStr.contains('cancel') ||
            errStr.contains('12501')) {
          setState(() => _loginError = null);
        } else if (errStr.contains('account-exists-with-different-credential') ||
            errStr.contains('different-credential') ||
            errStr.contains('account already exists')) {
          final gEmail = AuthService.lastAttemptedGoogleEmail;
          if (gEmail != null && gEmail.isNotEmpty) {
            _loginEmail.text = gEmail;
          }
          _tab.animateTo(0);
          _setError('Akun ${AuthService.lastAttemptedGoogleEmail ?? 'ini'} sudah terdaftar dengan Kata Sandi. Silakan masukkan kata sandi di atas.');
        } else if (errStr.contains('10') || errStr.contains('developer_error')) {
          _setError('Konfigurasi SHA-1 Firebase belum sesuai untuk aplikasi ini. Silakan gunakan login Email.');
        } else {
          _setError('Terjadi kendala saat login Google: $e');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _googleLoading = false);
      }
    }
  }

  String _xlErr(String m) {
    final lower = m.toLowerCase();
    if (lower.contains('invalid-credential') || lower.contains('invalid login') || lower.contains('wrong-password')) {
      return 'Kata sandi salah. Silakan periksa kembali.';
    }
    if (lower.contains('user-not-found') || lower.contains('user not found')) {
      return 'Email tidak terdaftar di Driving Buddy.';
    }
    if (lower.contains('email-already-in-use') || lower.contains('already registered')) {
      return 'Email ini sudah terdaftar. Silakan langsung masuk.';
    }
    if (lower.contains('weak-password') || lower.contains('weak password')) {
      return 'Kata sandi terlalu lemah. Minimal 8 karakter dengan kombinasi lengkap.';
    }
    if (lower.contains('invalid-email') || lower.contains('badly formatted')) {
      return 'Format email tidak valid. Pastikan penulisan benar.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Koneksi internet bermasalah. Coba periksa koneksi kamu.';
    }
    return 'Terjadi kendala. Silakan coba beberapa saat lagi.';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        final screenHeight = MediaQuery.of(context).size.height;
        final topPadding = MediaQuery.of(context).padding.top;
        final headerHeight = math.max(200.0, math.min(235.0, screenHeight * 0.26));

        return Scaffold(
          backgroundColor: isDark ? AppColors.darkBackground : const Color(0xFFFFFFFF),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── TOP WAVE HEADER WITH ORGANIC TOPO LINES ────
                      _buildTopWaveHeader(isDark, headerHeight, topPadding),

                      // ── MAIN CONTENT CANVAS ────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),

                            // Welcoming Hero Header
                            _buildHeroHeader(isDark),

                            const SizedBox(height: 18),

                            // Modern Sliding Capsule Tab Selector
                            _buildCapsuleSegment(isDark),

                            const SizedBox(height: 22),

                            // Forms
                            AnimatedBuilder(
                              animation: _tab,
                              builder: (context, _) {
                                return _tab.index == 0
                                    ? _buildLoginForm(isDark)
                                    : _buildRegisterForm(isDark);
                              },
                            ),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Top Wave Header ─────────────────────────
  Widget _buildTopWaveHeader(bool isDark, double headerHeight, double topPadding) {
    return ClipPath(
      clipper: const _WaveHeaderClipper(),
      child: Container(
        height: headerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFFB84506),
                    Color(0xFF822F02),
                    Color(0xFF1E293B),
                  ]
                : const [
                    Color(0xFFFF7A29),
                    Color(0xFFF26B1D),
                    Color(0xFFEA580C),
                  ],
          ),
        ),
        child: Stack(
          children: [
            // Topographic Contour Lines
            Positioned.fill(
              child: CustomPaint(
                painter: _TopographicPainter(isDark: isDark),
              ),
            ),

            // Subtle Ambient Vignette / Radial Glow
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    ],
                  ),
                ),
              ),
            ),

            // Driving Buddy Logo at Top-Left (Clean, NO black box/badge)
            Positioned(
              top: topPadding + 14,
              left: 24,
              child: Image.asset(
                'assets/images/DrivingBuddyLogo_white_tight.png',
                height: 32,
                fit: BoxFit.contain,
              ),
            ),

            // Back to Welcome Screen Button at Top-Right
            Positioned(
              top: topPadding + 10,
              right: 18,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                tooltip: 'Kembali ke Welcome',
                onPressed: () {
                  Navigator.of(context).pushReplacementNamed(AppRoutes.welcome);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero Header ─────────────────────────────
  Widget _buildHeroHeader(bool isDark) {
    final isLoginTab = _tab.index == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isLoginTab ? 'Sign In' : 'Daftar Akun',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        // Modern brand accent underline
        Container(
          width: 38,
          height: 3.5,
          decoration: BoxDecoration(
            color: const Color(0xFFF26B1D),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  // ── Capsule Segment Tab ─────────────────────
  Widget _buildCapsuleSegment(bool isDark) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF22304C) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Animated Pill Slider
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: _tab.index == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF26B1D), Color(0xFFEA580C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF26B1D).withValues(alpha: 0.32),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Tab Tap Targets
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _tab.animateTo(0);
                    setState(() {});
                  },
                  child: Center(
                    child: Text(
                      'Masuk',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _tab.index == 0 ? FontWeight.w800 : FontWeight.w600,
                        color: _tab.index == 0
                            ? Colors.white
                            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _tab.animateTo(1);
                    setState(() {});
                  },
                  child: Center(
                    child: Text(
                      'Daftar Baru',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _tab.index == 1 ? FontWeight.w800 : FontWeight.w600,
                        color: _tab.index == 1
                            ? Colors.white
                            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Login Form ──────────────────────────────
  Widget _buildLoginForm(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loginError != null) ...[
          _buildAlertBox(_loginError!, isError: true),
          const SizedBox(height: 14),
        ],

        _buildLabel('Email Pengemudi', isDark),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _loginEmail,
          hint: 'nama@email.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          isDark: isDark,
        ),
        const SizedBox(height: 14),

        _buildLabel('Kata Sandi', isDark),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _loginPassword,
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _loginObscure,
          isDark: isDark,
          suffix: IconButton(
            icon: Icon(
              _loginObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              size: 20,
            ),
            onPressed: () => setState(() => _loginObscure = !_loginObscure),
          ),
        ),
        const SizedBox(height: 8),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordDialog,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(50, 26),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Lupa Kata Sandi?',
              style: TextStyle(
                color: Color(0xFFF26B1D),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Primary Submit Button
        DbPressable(
          onTap: _loginLoading ? null : _doLogin,
          child: Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF26B1D), Color(0xFFEA580C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF26B1D).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: _loginLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                    )
                  : const Text(
                      'Masuk ke Cockpit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Google Sign In
        _buildGoogleSignInButton(isDark),

        const SizedBox(height: 20),

        // Switch to Register
        Center(
          child: GestureDetector(
            onTap: () {
              _tab.animateTo(1);
              setState(() {});
            },
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Belum punya akun? ',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const TextSpan(
                    text: 'Daftar sekarang',
                    style: TextStyle(
                      color: Color(0xFFF26B1D),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Register Form ───────────────────────────
  Widget _buildRegisterForm(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_regSuccess != null) ...[
          _buildAlertBox(_regSuccess!, isError: false),
          const SizedBox(height: 14),
        ],
        if (_regError != null) ...[
          _buildAlertBox(_regError!, isError: true),
          const SizedBox(height: 14),
        ],

        _buildLabel('Nama Lengkap', isDark),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regName,
          hint: 'Contoh: Adrian Hartono',
          icon: Icons.person_outline_rounded,
          isDark: isDark,
        ),
        const SizedBox(height: 14),

        _buildLabel('Email Pengemudi', isDark),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regEmail,
          hint: 'nama@email.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          isDark: isDark,
        ),
        const SizedBox(height: 14),

        _buildLabel('Kata Sandi', isDark),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regPassword,
          hint: 'Min. 8 karakter (Besar, Kecil, Angka, Simbol)',
          icon: Icons.lock_outline_rounded,
          obscureText: _regObscure,
          isDark: isDark,
          suffix: IconButton(
            icon: Icon(
              _regObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              size: 20,
            ),
            onPressed: () => setState(() => _regObscure = !_regObscure),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '* Minimal 8 karakter, wajib kombinasi huruf besar, huruf kecil, angka, dan simbol unik',
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 14),

        _buildLabel('Konfirmasi Kata Sandi', isDark),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regConfirm,
          hint: 'Ulangi kata sandi',
          icon: Icons.lock_outline_rounded,
          obscureText: _regObscure,
          isDark: isDark,
          suffix: IconButton(
            icon: Icon(
              _regObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              size: 20,
            ),
            onPressed: () => setState(() => _regObscure = !_regObscure),
          ),
        ),
        const SizedBox(height: 18),

        // Primary Submit Button
        DbPressable(
          onTap: _regLoading ? null : _doRegister,
          child: Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF26B1D), Color(0xFFEA580C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF26B1D).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: _regLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                    )
                  : const Text(
                      'Buat Akun Pengemudi',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Google Sign In
        _buildGoogleSignInButton(isDark),

        const SizedBox(height: 20),

        // Switch to Login
        Center(
          child: GestureDetector(
            onTap: () {
              _tab.animateTo(0);
              setState(() {});
            },
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Sudah punya akun? ',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const TextSpan(
                    text: 'Masuk',
                    style: TextStyle(
                      color: Color(0xFFF26B1D),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Google Sign In Button ───────────────────
  Widget _buildGoogleSignInButton(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: isDark ? const Color(0xFF22304C) : const Color(0xFFE2E8F0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'atau masuk dengan',
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: isDark ? const Color(0xFF22304C) : const Color(0xFFE2E8F0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: _googleLoading ? null : _doGoogleLogin,
            style: OutlinedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF131B2E) : Colors.white,
              side: BorderSide(
                color: isDark ? const Color(0xFF22304C) : const Color(0xFFCBD5E1),
                width: 1.1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _googleLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Color(0xFFF26B1D), strokeWidth: 2.2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/google_logo.png',
                        height: 20,
                        width: 20,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Lanjutkan dengan Google',
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Label Helper ────────────────────────────
  Widget _buildLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
      ),
    );
  }

  // ── Input Field Helper ──────────────────────
  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
    required bool isDark,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF22304C) : const Color(0xFFE2E8F0),
          width: 1.1,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        cursorColor: const Color(0xFFF26B1D),
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            fontSize: 13,
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: Icon(
            icon,
            color: const Color(0xFFF26B1D),
            size: 18,
          ),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  // ── Alert Box Helper ────────────────────────
  Widget _buildAlertBox(String msg, {required bool isError}) {
    final isDark = ThemeService.instance.isDarkMode;
    final color = isError ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final bgColor = isError
        ? (isDark ? const Color(0xFF2B1214) : const Color(0xFFFEF2F2))
        : (isDark ? const Color(0xFF0E2A1E) : const Color(0xFFECFDF5));
    final borderColor = isError
        ? (isDark ? const Color(0xFF591C1F) : const Color(0xFFFECACA))
        : (isDark ? const Color(0xFF165239) : const Color(0xFFA7F3D0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ORGANIC WAVE CLIPPER (Smooth Bezier Curve inspired by world-class mobile UI)
// ============================================================================
class _WaveHeaderClipper extends CustomClipper<Path> {
  const _WaveHeaderClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 38);

    // First curve dipping down towards center
    final cp1 = Offset(size.width * 0.28, size.height + 8);
    final ep1 = Offset(size.width * 0.58, size.height - 24);
    path.quadraticBezierTo(cp1.dx, cp1.dy, ep1.dx, ep1.dy);

    // Second curve swooping up to right
    final cp2 = Offset(size.width * 0.84, size.height - 52);
    final ep2 = Offset(size.width, size.height - 18);
    path.quadraticBezierTo(cp2.dx, cp2.dy, ep2.dx, ep2.dy);

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ============================================================================
// TOPOGRAPHIC CONTOUR PAINTER (Artistic Elevation / Telemetry Isolines)
// ============================================================================
class _TopographicPainter extends CustomPainter {
  final bool isDark;

  const _TopographicPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paintSoft = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.08 : 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final paintAccent = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.15 : 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Organic loop 1 (top-left contour hill)
    for (int i = 0; i < 4; i++) {
      final radX = 35.0 + i * 28.0;
      final radY = 25.0 + i * 22.0;
      final rect = Rect.fromCenter(
        center: Offset(w * 0.12, h * 0.28),
        width: radX * 2,
        height: radY * 2,
      );
      canvas.drawOval(rect, i.isEven ? paintAccent : paintSoft);
    }

    // Organic loop 2 (right elevation contour ridge)
    for (int i = 0; i < 5; i++) {
      final radX = 42.0 + i * 32.0;
      final radY = 32.0 + i * 24.0;
      final rect = Rect.fromCenter(
        center: Offset(w * 0.88, h * 0.42),
        width: radX * 2,
        height: radY * 2,
      );
      canvas.drawOval(rect, i % 2 == 1 ? paintAccent : paintSoft);
    }

    // Flowing sweeping ridge paths traversing the header
    final path1 = Path();
    path1.moveTo(0, h * 0.15);
    path1.cubicTo(w * 0.25, h * 0.05, w * 0.55, h * 0.35, w, h * 0.12);
    canvas.drawPath(path1, paintSoft);

    final path2 = Path();
    path2.moveTo(0, h * 0.45);
    path2.cubicTo(w * 0.35, h * 0.65, w * 0.65, h * 0.18, w, h * 0.55);
    canvas.drawPath(path2, paintAccent);

    final path3 = Path();
    path3.moveTo(0, h * 0.72);
    path3.cubicTo(w * 0.30, h * 0.88, w * 0.70, h * 0.48, w, h * 0.78);
    canvas.drawPath(path3, paintSoft);
  }

  @override
  bool shouldRepaint(covariant _TopographicPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

// Keep RegisterScreen alias for routing compatibility
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen();
  }
}
