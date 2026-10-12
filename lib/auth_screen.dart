import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'main.dart';

// ─────────────────────────────────────────────────────
//  DESIGN TOKENS — Auth Screen
// ─────────────────────────────────────────────────────
class _A {
  static const bg       = Color(0xFF080C14);
  static const surface  = Color(0xFF111827);
  static const card     = Color(0xFF1A2235);
  static const orange   = Color(0xFFFF5722);
  static const orangeL  = Color(0xFFFF8A65);
  static const white    = Colors.white;
  static const grey     = Color(0xFF6B7280);
  static const greyL    = Color(0xFF9CA3AF);
  static const border   = Color(0xFF1F2D45);
  static const danger   = Color(0xFFEF4444);
  static const success  = Color(0xFF10B981);
}

// ─────────────────────────────────────────────────────
//  ANIMATED BACKGROUND PAINTER
// ─────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  final double t; // animation 0–1
  _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Floating glow orbs
    final orb1 = Paint()
      ..color = _A.orange.withOpacity(0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    final orb2 = Paint()
      ..color = const Color(0xFF3B82F6).withOpacity(0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final ox1 = size.width * 0.8 + math.sin(t * 2 * math.pi) * 20;
    final oy1 = size.height * 0.15 + math.cos(t * 2 * math.pi) * 15;
    canvas.drawCircle(Offset(ox1, oy1), 160, orb1);

    final ox2 = size.width * 0.1 + math.cos(t * 2 * math.pi) * 15;
    final oy2 = size.height * 0.75 + math.sin(t * 2 * math.pi) * 20;
    canvas.drawCircle(Offset(ox2, oy2), 140, orb2);
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────
//  AUTH SCREEN — Single screen with Login / Register tabs
// ─────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // Tab controller
  late final TabController _tab;

  // Bg animation
  late final AnimationController _bgCtrl;
  late final Animation<double> _bgAnim;

  // Slide-in animation
  late final AnimationController _slideCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // Login fields
  final _loginEmail    = TextEditingController();
  final _loginPassword = TextEditingController();
  bool _loginLoading = false;
  String? _loginError;
  bool _loginObscure = true;

  // Register fields
  final _regName     = TextEditingController();
  final _regEmail    = TextEditingController();
  final _regPassword = TextEditingController();
  final _regConfirm  = TextEditingController();
  bool _regLoading = false;
  String? _regError;
  String? _regSuccess;
  bool _regObscure = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);

    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _bgAnim = Tween(begin: 0.0, end: 1.0).animate(_bgCtrl);

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    _slideAnim = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _tab.dispose();
    _bgCtrl.dispose();
    _slideCtrl.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPassword.dispose();
    _regConfirm.dispose();
    super.dispose();
  }

  // ── login ───────────────────────────────
  Future<void> _doLogin() async {
    setState(() { _loginLoading = true; _loginError = null; });
    try {
      await AuthService.login(
          email: _loginEmail.text.trim(), password: _loginPassword.text);
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainShell()));
      }
    } on AuthException catch (e) {
      setState(() => _loginError = _xlErr(e.message));
    } catch (_) {
      setState(() => _loginError = 'Terjadi kesalahan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  // ── register ────────────────────────────
  Future<void> _doRegister() async {
    if (_regName.text.trim().isEmpty)
      return setState(() => _regError = 'Nama tidak boleh kosong.');
    if (_regPassword.text != _regConfirm.text)
      return setState(() => _regError = 'Password tidak cocok.');
    setState(() { _regLoading = true; _regError = null; _regSuccess = null; });
    try {
      await AuthService.register(
          email: _regEmail.text.trim(),
          password: _regPassword.text,
          fullName: _regName.text.trim());
      setState(() => _regSuccess =
          'Akun berhasil! Cek email kamu untuk konfirmasi, lalu login.');
    } on AuthException catch (e) {
      setState(() => _regError = _xlErr(e.message));
    } catch (_) {
      setState(() => _regError = 'Terjadi kesalahan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  String _xlErr(String m) {
    if (m.contains('Invalid login'))      return 'Email atau password salah.';
    if (m.contains('Email not confirmed')) return 'Email belum dikonfirmasi. Cek inbox-mu.';
    if (m.contains('User not found'))     return 'Akun tidak ditemukan.';
    if (m.contains('already registered')) return 'Email sudah terdaftar.';
    if (m.contains('weak password'))      return 'Password terlalu lemah (min. 6 karakter).';
    return m;
  }

  // ── build ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _A.bg,
      body: Stack(children: [
        // Animated background
        AnimatedBuilder(
          animation: _bgAnim,
          builder: (_, __) => CustomPaint(
            painter: _BgPainter(_bgAnim.value),
            size: MediaQuery.of(context).size,
          ),
        ),

        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(children: [
                const SizedBox(height: 32),
                _buildLogo(),
                const SizedBox(height: 36),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildLoginTab(),
                      _buildRegisterTab(),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── logo ────────────────────────────────
  Widget _buildLogo() {
    return Column(children: [
      // App icon with gradient ring
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [_A.orange, _A.orangeL],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: _A.orange.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
        ),
        child: const Icon(Icons.directions_car_rounded,
            color: Colors.white, size: 38),
      ),
      const SizedBox(height: 16),
      const Text.rich(TextSpan(children: [
        TextSpan(
          text: 'DRIVING',
          style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 3),
        ),
        TextSpan(
          text: ' BUDDY',
          style: TextStyle(
              color: _A.orange,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 3),
        ),
      ])),
      const SizedBox(height: 6),
      Text(
        'Berkendara Lebih Aman, Setiap Hari',
        style: TextStyle(
            color: _A.grey, fontSize: 13, letterSpacing: 0.3),
      ),
    ]);
  }

  // ── tab bar ─────────────────────────────
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: _A.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _A.border),
        ),
        child: TabBar(
          controller: _tab,
          indicator: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_A.orange, _A.orangeL]),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: _A.grey,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: 'Masuk'),
            Tab(text: 'Daftar'),
          ],
        ),
      ),
    );
  }

  // ── login tab ───────────────────────────
  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_loginError != null) ...[
          _Alert(msg: _loginError!, isError: true),
          const SizedBox(height: 16),
        ],

        _FieldLabel('Email'),
        const SizedBox(height: 8),
        _Field(
          ctrl: _loginEmail,
          hint: 'nama@email.com',
          icon: Icons.alternate_email_rounded,
          type: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),

        _FieldLabel('Password'),
        const SizedBox(height: 8),
        _Field(
          ctrl: _loginPassword,
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscure: _loginObscure,
          suffix: IconButton(
            icon: Icon(
              _loginObscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _A.grey, size: 20,
            ),
            onPressed: () => setState(() => _loginObscure = !_loginObscure),
          ),
        ),
        const SizedBox(height: 8),

        Align(
          alignment: Alignment.centerRight,
          child: Text('Lupa password?',
              style: TextStyle(
                  color: _A.orange, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 28),

        _PrimaryBtn(
          label: 'Masuk',
          loading: _loginLoading,
          onTap: _doLogin,
        ),
        const SizedBox(height: 24),

        Center(
          child: GestureDetector(
            onTap: () => _tab.animateTo(1),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: 'Belum punya akun? ',
                  style: TextStyle(color: _A.grey, fontSize: 13)),
              TextSpan(
                text: 'Daftar sekarang',
                style: TextStyle(
                    color: _A.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ])),
          ),
        ),
      ]),
    );
  }

  // ── register tab ────────────────────────
  Widget _buildRegisterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_regSuccess != null) ...[
          _Alert(msg: _regSuccess!, isError: false),
          const SizedBox(height: 16),
        ],
        if (_regError != null) ...[
          _Alert(msg: _regError!, isError: true),
          const SizedBox(height: 16),
        ],

        _FieldLabel('Nama Lengkap'),
        const SizedBox(height: 8),
        _Field(
            ctrl: _regName,
            hint: 'Nama kamu',
            icon: Icons.person_outline_rounded),
        const SizedBox(height: 16),

        _FieldLabel('Email'),
        const SizedBox(height: 8),
        _Field(
            ctrl: _regEmail,
            hint: 'nama@email.com',
            icon: Icons.alternate_email_rounded,
            type: TextInputType.emailAddress),
        const SizedBox(height: 16),

        _FieldLabel('Password'),
        const SizedBox(height: 8),
        _Field(
          ctrl: _regPassword,
          hint: 'Min. 6 karakter',
          icon: Icons.lock_outline_rounded,
          obscure: _regObscure,
          suffix: IconButton(
            icon: Icon(
              _regObscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _A.grey, size: 20,
            ),
            onPressed: () => setState(() => _regObscure = !_regObscure),
          ),
        ),
        const SizedBox(height: 16),

        _FieldLabel('Konfirmasi Password'),
        const SizedBox(height: 8),
        _Field(
            ctrl: _regConfirm,
            hint: 'Ulangi password',
            icon: Icons.lock_outline_rounded,
            obscure: true),
        const SizedBox(height: 28),

        _PrimaryBtn(
          label: 'Buat Akun',
          loading: _regLoading,
          onTap: _doRegister,
        ),
        const SizedBox(height: 24),

        Center(
          child: GestureDetector(
            onTap: () => _tab.animateTo(0),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: 'Sudah punya akun? ',
                  style: TextStyle(color: _A.grey, fontSize: 13)),
              TextSpan(
                text: 'Masuk',
                style: TextStyle(
                    color: _A.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ])),
          ),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────
//  HELPER WIDGETS
// ─────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3));
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final TextInputType? type;
  final bool obscure;
  final Widget? suffix;
  const _Field({
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.type,
    this.obscure = false,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _A.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _A.border, width: 1.5),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: type,
        style: const TextStyle(
            color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _A.grey, fontSize: 14),
          prefixIcon: Icon(icon, color: _A.grey, size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _PrimaryBtn(
      {required this.label, required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: loading
              ? const LinearGradient(colors: [Color(0xFF4B5563), Color(0xFF4B5563)])
              : const LinearGradient(
                  colors: [_A.orange, _A.orangeL],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: loading
              ? []
              : [
                  BoxShadow(
                      color: _A.orange.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8))
                ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
        ),
      ),
    );
  }
}

class _Alert extends StatelessWidget {
  final String msg;
  final bool isError;
  const _Alert({required this.msg, required this.isError});
  @override
  Widget build(BuildContext context) {
    final c = isError ? _A.danger : _A.success;
    final icon = isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.3), width: 1.5),
      ),
      child: Row(children: [
        Icon(icon, color: c, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(msg,
                style: TextStyle(color: c, fontSize: 13, height: 1.4))),
      ]),
    );
  }
}

// Keep RegisterScreen as alias for nav compatibility
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const LoginScreen();
  }
}
