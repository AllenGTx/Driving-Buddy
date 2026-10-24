import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'supabase_service.dart';
import 'models/account_config.dart';
import 'screens/main_shell.dart';

// ============================================================================
// AUTH SCREEN (Login & Registrasi — Luxury GT Obsidian Telemetry)
// ============================================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;

  // Slide animation
  late final AnimationController _slideCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    _slideAnim = Tween(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _tab.dispose();
    _slideCtrl.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPassword.dispose();
    _regConfirm.dispose();
    super.dispose();
  }

  // ── lupa password ────────────────────────
  Future<void> _showForgotPasswordDialog() async {
    final emailCtrl = TextEditingController(text: _loginEmail.text.trim());
    String? dialogError;
    String? dialogSuccess;
    bool dialogLoading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: Color(0xFFE57A38)),
              SizedBox(width: 10),
              Text('Reset Kata Sandi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Masukkan email kamu untuk menerima tautan pemulihan kata sandi.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
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
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'nama@email.com',
                  prefixIcon: const Icon(Icons.alternate_email_rounded, color: Color(0xFF64748B), size: 19),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE57A38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Kirim Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── validasi pendaftaran ──────────────────
  String? _validateEmailAddress(String email) {
    if (email.isEmpty) return 'Email tidak boleh kosong.';
    // Validasi format email standar RFC 5322 regex yang ketat untuk domain nyata
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
    );
    if (!emailRegex.hasMatch(email)) {
      return 'Format email tidak valid (contoh: nama@domain.com).';
    }
    // Cek domain memiliki ekstensi yang valid (minimal 2 huruf, misal .com, .id, .org)
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
      return 'Kata sandi harus mengandung minimal 1 simbol (!@#\$%^&* dll).';
    }
    return null;
  }

  // ── dialog verifikasi email ───────────────
  void _showVerificationDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool resending = false;
        String? resendMsg;
        return StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Row(
              children: [
                Icon(Icons.mark_email_read_rounded, color: Color(0xFFE57A38), size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Verifikasi Email Dikirim',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
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
                  style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Text(
                    email,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC2410C),
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'PENTING: Jika tidak muncul di Kotak Masuk, silakan periksa Folder Spam atau Promosi dan pilih "Bukan Spam".',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
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
                    style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
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
                    : const Text('Kirim Ulang Link', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE57A38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  // Pindahkan tab langsung ke Halaman Masuk & isi email
                  _loginEmail.text = email;
                  _tab.animateTo(0);
                  setState(() {
                    _loginError = null;
                  });
                },
                child: const Text(
                  'Kembali ke Masuk',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── login ───────────────────────────────
  Future<void> _doLogin() async {
    final email = _loginEmail.text.trim();
    final password = _loginPassword.text;

    if (email.isEmpty) {
      setState(() => _loginError = 'Email tidak boleh kosong.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _loginError = 'Kata sandi tidak boleh kosong.');
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
      // Reset & ambil foto spesifik akun yang baru masuk
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
        // Firebase Auth terbaru sering mengembalikan 'invalid-credential' untuk menyamarkan error.
        // Coba periksa apakah email terdaftar menggunakan query users di Firestore:
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
      setState(() => _loginError = errMsg);
    } catch (_) {
      setState(() => _loginError = 'Terjadi kesalahan saat masuk. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  // ── register ────────────────────────────
  Future<void> _doRegister() async {
    final name = _regName.text.trim();
    final email = _regEmail.text.trim();
    final password = _regPassword.text;
    final confirm = _regConfirm.text;

    if (name.isEmpty) {
      return setState(() => _regError = 'Nama lengkap tidak boleh kosong.');
    }

    final emailErr = _validateEmailAddress(email);
    if (emailErr != null) {
      return setState(() => _regError = emailErr);
    }

    final passErr = _validatePasswordFormat(password);
    if (passErr != null) {
      return setState(() => _regError = passErr);
    }

    if (password != confirm) {
      return setState(() => _regError = 'Konfirmasi kata sandi tidak cocok.');
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
      setState(() => _regError = msg);
    } catch (e) {
      setState(() => _regError = 'Terjadi kesalahan pendaftaran. Coba lagi.');
    } finally {
      if (mounted) setState(() => _regLoading = false);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildBrandHeader(),
                  const SizedBox(height: 24),
                  _buildTabSelector(),
                  const SizedBox(height: 20),
                  // Form Card
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0xFFFFFBF8)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE57A38).withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: AnimatedBuilder(
                      animation: _tab,
                      builder: (context, _) {
                        return _tab.index == 0 ? _buildLoginForm() : _buildRegisterForm();
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Image.asset(
          'assets/images/DrivingBuddyLogo_tight.png',
          height: 80,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 6),
        const Text(
          'GT Telemetri Kabin & Monitoring Kelelahan',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildTabSelector() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TabBar(
        controller: _tab,
        indicator: BoxDecoration(
          color: const Color(0xFFE57A38),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE57A38).withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        onTap: (index) => setState(() {}),
        tabs: const [
          Tab(text: 'Masuk'),
          Tab(text: 'Daftar Baru'),
        ],
      ),
    );
  }

  // ── google login ────────────────────────
  bool _googleLoading = false;

  Future<void> _doGoogleLogin() async {
    setState(() {
      _googleLoading = true;
      _loginError = null;
      _regError = null;
    });
    try {
      // Timeout guard agar jika popup ditutup di background tanpa trigger event, loading otomatis mati
      await AuthService.signInWithGoogle().timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          throw 'Popup login Google ditutup atau waktu habis.';
        },
      );
      final gEmail = AuthService.currentUser?.email;
      await AccountConfig.getPhotoUrl(userEmail: gEmail);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'popup-closed-by-user' || e.code == 'cancelled') {
          // User sengaja menutup popup, jangan tampilkan error merah menakutkan, cukup batalkan loading
          setState(() => _loginError = null);
        } else {
          setState(() => _loginError = _xlErr(e.message ?? 'Login Google dibatalkan'));
        }
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('popup-closed-by-user') || errStr.contains('closed by user') || errStr.contains('cancel')) {
          setState(() => _loginError = null);
        } else {
          setState(() => _loginError = 'Login Google dibatalkan atau waktu habis.');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _googleLoading = false);
      }
    }
  }

  Widget _buildGoogleSignInButton() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'atau',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _googleLoading ? null : _doGoogleLogin,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 1,
              shadowColor: Colors.black.withOpacity(0.04),
            ),
            child: _googleLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Color(0xFFE57A38), strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/google_logo.png',
                        height: 22,
                        width: 22,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Masuk dengan Google',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loginError != null) ...[
          _buildAlertBox(_loginError!, isError: true),
          const SizedBox(height: 16),
        ],

        _buildLabel('Email Pengemudi'),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _loginEmail,
          hint: 'nama@email.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),

        _buildLabel('Kata Sandi'),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _loginPassword,
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _loginObscure,
          suffix: IconButton(
            icon: Icon(
              _loginObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: const Color(0xFF64748B),
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
              minimumSize: const Size(50, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Lupa Kata Sandi?',
              style: TextStyle(
                color: Color(0xFFE57A38),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _loginLoading ? null : _doLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57A38),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
              shadowColor: const Color(0xFFE57A38).withOpacity(0.35),
            ),
            child: _loginLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'Masuk ke Cockpit',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
          ),
        ),
        const SizedBox(height: 18),

        _buildGoogleSignInButton(),
        const SizedBox(height: 18),
        Center(
          child: GestureDetector(
            onTap: () {
              _tab.animateTo(1);
              setState(() {});
            },
            child: Text.rich(
              TextSpan(
                children: const [
                  TextSpan(
                    text: 'Belum punya akun? ',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  TextSpan(
                    text: 'Daftar sekarang',
                    style: TextStyle(
                      color: Color(0xFFE57A38),
                      fontSize: 13,
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

  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_regSuccess != null) ...[
          _buildAlertBox(_regSuccess!, isError: false),
          const SizedBox(height: 16),
        ],
        if (_regError != null) ...[
          _buildAlertBox(_regError!, isError: true),
          const SizedBox(height: 16),
        ],

        _buildLabel('Nama Lengkap'),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regName,
          hint: 'Contoh: Adrian Hartono',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 14),

        _buildLabel('Email Pengemudi'),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regEmail,
          hint: 'nama@email.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        _buildLabel('Kata Sandi'),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regPassword,
          hint: 'Min. 8 karakter (Besar, Kecil, Angka, Simbol)',
          icon: Icons.lock_outline_rounded,
          obscureText: _regObscure,
          suffix: IconButton(
            icon: Icon(
              _regObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: const Color(0xFF64748B),
              size: 20,
            ),
            onPressed: () => setState(() => _regObscure = !_regObscure),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '* Minimal 8 karakter, wajib ada huruf besar, huruf kecil, angka, dan simbol unik (!@#\$%^&* dll)',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 14),

        _buildLabel('Konfirmasi Kata Sandi'),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _regConfirm,
          hint: 'Ulangi kata sandi',
          icon: Icons.lock_outline_rounded,
          obscureText: _regObscure,
          suffix: IconButton(
            icon: Icon(
              _regObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: const Color(0xFF64748B),
              size: 20,
            ),
            onPressed: () => setState(() => _regObscure = !_regObscure),
          ),
        ),
        const SizedBox(height: 22),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _regLoading ? null : _doRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57A38),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
              shadowColor: const Color(0xFFE57A38).withOpacity(0.35),
            ),
            child: _regLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'Buat Akun Pengemudi',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
          ),
        ),
        const SizedBox(height: 18),

        _buildGoogleSignInButton(),
        const SizedBox(height: 18),
        Center(
          child: GestureDetector(
            onTap: () {
              _tab.animateTo(0);
              setState(() {});
            },
            child: Text.rich(
              TextSpan(
                children: const [
                  TextSpan(
                    text: 'Sudah punya akun? ',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  TextSpan(
                    text: 'Masuk',
                    style: TextStyle(
                      color: Color(0xFFE57A38),
                      fontSize: 13,
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        cursorColor: const Color(0xFFE57A38),
        style: const TextStyle(
          color: Color(0xFF0F172A), // Font hitam pekat jelas
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, fontWeight: FontWeight.normal),
          prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 19),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildAlertBox(String msg, {required bool isError}) {
    final color = isError ? const Color(0xFFD94126) : const Color(0xFF059669);
    final bgColor = isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
    final borderColor = isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// Keep RegisterScreen alias
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen();
  }
}




