import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

// ─────────────────────────────────────────────
// FIREBASE OPTIONS
// ─────────────────────────────────────────────
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBDnGlxioQ9Go54K5Uyrkx8MWU6Ms3--XY',
    appId: '1:8625582392:android:89e415490f0077b07d51cd',
    messagingSenderId: '8625582392',
    projectId: 'agro-pass',
    storageBucket: 'agro-pass.firebasestorage.app',
  );
}

// ─────────────────────────────────────────────
// CLÉS D'ACCÈS SECRÈTES
// ─────────────────────────────────────────────
const Map<String, ({String? niveau, String? parcours})> _classKeys = {
  '73928465': (niveau: null,  parcours: null),
  '18472936': (niveau: 'L1', parcours: null),
  '56281947': (niveau: 'L2', parcours: 'PV'),
  '93746182': (niveau: 'L2', parcours: 'PA'),
  '28174659': (niveau: 'L2', parcours: 'IAAB'),
  '69482715': (niveau: 'L3', parcours: 'PV'),
  '37591826': (niveau: 'L3', parcours: 'IAAB'),
  '81625394': (niveau: 'L3', parcours: 'PA'),
  '49273618': (niveau: 'M1', parcours: null),
};

String? currentAccessKey;

({String? niveau, String? parcours})? getCurrentFilter() {
  if (currentAccessKey == null) return null;
  final entry = _classKeys[currentAccessKey];
  if (entry == null) return null;
  if (entry.niveau == null && entry.parcours == null) return null;
  return entry;
}

bool isFullAdminKey() {
  if (currentAccessKey == null) return false;
  final entry = _classKeys[currentAccessKey];
  return entry != null && entry.niveau == null && entry.parcours == null;
}

// ─────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AgroPassApp());
}

class AgroPassApp extends StatefulWidget {
  const AgroPassApp({super.key});
  @override
  State<AgroPassApp> createState() => _AgroPassAppState();
}

// ─────────────────────────────────────────────
// SÉCURITÉ : déconnexion automatique
//  • App mise en arrière-plan → timer 10 min
//  • Retour rapide (< 3 s)   → session conservée
//  • Retour après 3 s        → déconnexion + login requis
//  • App tuée (detached)     → déconnexion immédiate
//
// Pourquoi 3 s ?  Sur Android, un simple swipe vers
// une autre app passe par paused. On tolère 3 s pour
// ne pas déconnecter lors d'un changement d'app rapide.
// ─────────────────────────────────────────────
class _AgroPassAppState extends State<AgroPassApp> with WidgetsBindingObserver {
  // Délai de grâce : si l'utilisateur revient en moins de 3 s,
  // on considère que c'est un changement d'app accidentel.
  static const _kGrace   = Duration(seconds: 3);
  static const _kTimeout = Duration(minutes: 10);

  Timer?    _logoutTimer;
  DateTime? _bgSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _logoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _forceLogout() {
    FirebaseAuth.instance.signOut();
    currentAccessKey = null;
    _logoutTimer = null;
    _bgSince     = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {

      // App tuée (swipe dans le gestionnaire de tâches)
      case AppLifecycleState.detached:
        _logoutTimer?.cancel();
        _forceLogout();
        break;

      // App en arrière-plan / écran éteint → on démarre le timer
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _bgSince = DateTime.now();
        _logoutTimer?.cancel();
        _logoutTimer = Timer(_kTimeout, _forceLogout);
        break;

      // App revenue au premier plan
      case AppLifecycleState.resumed:
        final absent = _bgSince == null
            ? Duration.zero
            : DateTime.now().difference(_bgSince!);

        if (absent >= _kGrace) {
          // Absent plus de 3 s → déconnexion obligatoire
          _logoutTimer?.cancel();
          _forceLogout();
        } else {
          // Retour quasi-immédiat → on annule le timer, session conservée
          _logoutTimer?.cancel();
          _logoutTimer = null;
          _bgSince     = null;
        }
        break;

      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agro Pass 2026',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AuthWrapper(),
    );
  }
}

// ─────────────────────────────────────────────
// AUTH WRAPPER
// ─────────────────────────────────────────────
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.hasData ? const RoleRouter() : const LoginPage();
      },
    );
  }
}

// ─────────────────────────────────────────────
// ROLE ROUTER
// ─────────────────────────────────────────────
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});
  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  String? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('user').doc(uid).get();
    if (mounted) {
      setState(() {
        _role = doc.data()?['role'] as String?;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_role == 'admin') {
      final filter = getCurrentFilter();
      return AdminDashboard(
        initialNiveau: filter?.niveau,
        initialParcours: filter?.parcours,
        isFirebaseAdmin: true,
      );
    }
    return const ScannerPage();
  }
}

// ─────────────────────────────────────────────
// COLORS & CONSTANTS
// ─────────────────────────────────────────────
const kGreen      = Color(0xFF2E7D32);
const kGreenLight = Color(0xFF4CAF50);
const kOrange     = Color(0xFFF57C00);
const kGrey       = Color(0xFF9E9E9E);
const kBg         = Color(0xFFF1F8E9);
const List<String> kNiveaux  = ['L1', 'L2', 'L3', 'M1'];
const List<String> kParcours = ['3COM', 'IAAB', 'PA', 'PV'];

// ─────────────────────────────────────────────
// MESSAGE HELPER
// ─────────────────────────────────────────────
void showMsg(BuildContext ctx, String msg, {bool error = false}) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontSize: 15)),
    backgroundColor: error ? Colors.red.shade700 : kGreen,
    duration: Duration(seconds: error ? 4 : 3),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ));
}

// ─────────────────────────────────────────────
// STUDENT MODEL
// ─────────────────────────────────────────────
class Student {
  final String  matricule, nom, prenom, niveau, parcours;
  final bool    hasPaid, qrCodeGenerated, qrCodeScanned;
  final String? photo;

  Student({
    required this.matricule, required this.nom, required this.prenom,
    required this.niveau, required this.parcours,
    required this.hasPaid, required this.qrCodeGenerated, required this.qrCodeScanned,
    this.photo,
  });

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Student(
      matricule:       doc.id,
      nom:             d['nom']               ?? '',
      prenom:          d['prenom']            ?? '',
      niveau:          d['niveau']            ?? '',
      parcours:        d['parcours']          ?? '',
      hasPaid:         d['has_paid']          ?? false,
      qrCodeGenerated: d['qr_code_generated'] ?? false,
      qrCodeScanned:   d['qr_code_scanned']   ?? false,
      photo:           d['photo']             as String?,
    );
  }
}

// ─────────────────────────────────────────────
// LOGIN PAGE
// ─────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _keyCtrl   = TextEditingController();
  bool _loading = false, _obscure = true;
  String? _error;

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Veuillez entrer votre adresse email.');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = 'Veuillez entrer votre mot de passe.');
      return;
    }
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Veuillez entrer votre clé d\'accès à 8 chiffres.');
      return;
    }
    if (key.length != 8) {
      setState(() => _error = 'La clé d\'accès doit contenir exactement 8 chiffres.');
      return;
    }
    if (!_classKeys.containsKey(key)) {
      setState(() => _error = 'Clé d\'accès incorrecte. Vérifiez et réessayez.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(), password: _passCtrl.text);
      currentAccessKey = key;
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'Aucun compte trouvé avec cet email.';
          break;
        case 'wrong-password':
          msg = 'Mot de passe incorrect.';
          break;
        case 'invalid-email':
          msg = 'Adresse email invalide.';
          break;
        case 'user-disabled':
          msg = 'Ce compte a été désactivé.';
          break;
        case 'too-many-requests':
          msg = 'Trop de tentatives. Réessayez dans quelques minutes.';
          break;
        case 'network-request-failed':
          msg = 'Pas de connexion internet. Vérifiez votre réseau.';
          break;
        default:
          msg = 'Email ou mot de passe incorrect.';
      }
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'Impossible de se connecter. Vérifiez votre connexion internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 100, height: 100,
            decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: kGreen.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/icon/icon-agro.png', fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.agriculture, size: 60, color: Colors.white)),
            )),
          const SizedBox(height: 24),
          const Text("by M'ôskaik studio", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kGreen, letterSpacing: 2)),
          const Text('2026 — Fianarantsoa', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 40),
          Card(elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
              TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined, size: 24),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16))),
              const SizedBox(height: 16),
              TextField(controller: _passCtrl, obscureText: _obscure, style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock_outlined, size: 24),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16))),
              const SizedBox(height: 16),
              TextField(controller: _keyCtrl, keyboardType: TextInputType.number, maxLength: 8,
                style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Clé d\'accès (8 chiffres)',
                  prefixIcon: const Icon(Icons.key_outlined, size: 24),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  counterText: '')),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade300)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14))),
                  ])),
              ],
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 54,
                child: ElevatedButton(onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _loading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('SE CONNECTER', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
            ]))),
        ]))),
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN DASHBOARD
// ─────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  final String? initialNiveau, initialParcours;
  final bool    isFirebaseAdmin;
  const AdminDashboard({super.key, this.initialNiveau, this.initialParcours, this.isFirebaseAdmin = false});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  late String? _filterNiveau, _filterParcours;
  String _searchQuery = '';

  bool get _canAddStudent  => widget.isFirebaseAdmin;
  bool get _isFullAdminKey => isFullAdminKey();

  @override
  void initState() {
    super.initState();
    _filterNiveau   = widget.initialNiveau;
    _filterParcours = widget.initialParcours;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kGreen, foregroundColor: Colors.white,
        title: const Text('AGRO PASS — Admin', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_canAddStudent)
            IconButton(icon: const Icon(Icons.add), tooltip: 'Ajouter un étudiant',
              onPressed: () => showDialog(context: context, builder: (_) => const _AddStudentDialog())),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: _currentIndex == 0
          ? _buildDashboard()
          : _currentIndex == 1
              ? const ScannerPage(showAppBar: false)
              : SearchIdPage(showAppBar: false, filterNiveau: _filterNiveau, filterParcours: _filterParcours),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner_outlined), selectedIcon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: 'Recherche'),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(children: [
      _StatsHeader(filterNiveau: _filterNiveau, filterParcours: _filterParcours),
      _FiltersBar(
        selectedNiveau:    _filterNiveau,
        selectedParcours:  _filterParcours,
        searchQuery:       _searchQuery,
        isFullAdminKey:    _isFullAdminKey,
        onNiveauChanged:   _isFullAdminKey ? (v) => setState(() => _filterNiveau   = v) : null,
        onParcoursChanged: _isFullAdminKey ? (v) => setState(() => _filterParcours  = v) : null,
        onSearchChanged:   (v) => setState(() => _searchQuery = v),
      ),
      Expanded(child: _StudentsList(
        filterNiveau: _filterNiveau, filterParcours: _filterParcours, searchQuery: _searchQuery)),
    ]);
  }
}

// ─────────────────────────────────────────────
// STATS HEADER
// ─────────────────────────────────────────────
class _StatsHeader extends StatelessWidget {
  final String? filterNiveau, filterParcours;
  const _StatsHeader({this.filterNiveau, this.filterParcours});

  String _k(String s) {
    if (filterNiveau != null && filterParcours != null) return '${filterNiveau}_${filterParcours}_$s';
    if (filterNiveau  != null) return '${filterNiveau}_$s';
    if (filterParcours != null) return '${filterParcours}_$s';
    return 'total_$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('counters').doc('stats').snapshots(),
      builder: (_, snap) {
        final d = snap.data?.data() as Map<String, dynamic>? ?? {};
        return Container(color: kGreen, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            _StatChip(icon: Icons.people,   label: 'Total',  value: '${d[_k('total')]   ?? 0}', color: Colors.white),
            _StatChip(icon: Icons.payments, label: 'Payés',  value: '${d[_k('paid')]    ?? 0}', color: Colors.greenAccent),
            _StatChip(icon: Icons.login,    label: 'Entrés', value: '${d[_k('scanned')] ?? 0}', color: Colors.orangeAccent),
          ]));
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _StatChip({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Icon(icon, color: color, size: 22), const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ])));
}

// ─────────────────────────────────────────────
// FILTERS BAR
// ─────────────────────────────────────────────
class _FiltersBar extends StatelessWidget {
  final String? selectedNiveau, selectedParcours;
  final String  searchQuery;
  final bool    isFullAdminKey;
  final ValueChanged<String?>? onNiveauChanged, onParcoursChanged;
  final ValueChanged<String>   onSearchChanged;

  const _FiltersBar({
    required this.selectedNiveau, required this.selectedParcours,
    required this.searchQuery, required this.isFullAdminKey,
    required this.onNiveauChanged, required this.onParcoursChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.white, padding: const EdgeInsets.all(12), child: Column(children: [
      TextField(onChanged: onSearchChanged,
        decoration: InputDecoration(hintText: 'Rechercher nom ou matricule...',
          prefixIcon: const Icon(Icons.search), isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      const SizedBox(height: 8),
      if (isFullAdminKey)
        Row(children: [
          Expanded(child: _FilterDropdown(label: 'Niveau', value: selectedNiveau,
            items: [null, ...kNiveaux], getLabel: (v) => v ?? 'Tous', onChanged: onNiveauChanged!)),
          const SizedBox(width: 8),
          Expanded(child: _FilterDropdown(label: 'Parcours', value: selectedParcours,
            items: [null, ...kParcours], getLabel: (v) => v ?? 'Tous', onChanged: onParcoursChanged!)),
        ])
      else
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: kGreen.withOpacity(0.08), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kGreen.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.filter_alt, color: kGreen, size: 18), const SizedBox(width: 8),
            Text('Filtre : ${[selectedNiveau, selectedParcours].where((e) => e != null).join(' ')}'.trim(),
              style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
            const Spacer(), const Icon(Icons.lock, color: kGrey, size: 16),
          ])),
    ]));
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label; final String? value; final List<String?> items;
  final String Function(String?) getLabel; final ValueChanged<String?> onChanged;
  const _FilterDropdown({required this.label, required this.value, required this.items, required this.getLabel, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
    value: value,
    decoration: InputDecoration(labelText: label, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
    items: items.map((v) => DropdownMenuItem(value: v, child: Text(getLabel(v)))).toList(),
    onChanged: onChanged);
}

// ─────────────────────────────────────────────
// STUDENTS LIST
// ─────────────────────────────────────────────
class _StudentsList extends StatelessWidget {
  final String? filterNiveau, filterParcours;
  final String  searchQuery;
  const _StudentsList({this.filterNiveau, this.filterParcours, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('students');
    if (filterNiveau  != null) q = q.where('niveau',   isEqualTo: filterNiveau);
    if (filterParcours != null) q = q.where('parcours', isEqualTo: filterParcours);
    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        var list = snap.data!.docs.map((d) => Student.fromFirestore(d)).toList();
        if (searchQuery.isNotEmpty) {
          final s = searchQuery.toLowerCase();
          list = list.where((e) => e.matricule.toLowerCase().contains(s)
            || e.nom.toLowerCase().contains(s) || e.prenom.toLowerCase().contains(s)).toList();
        }
        if (list.isEmpty) return const Center(child: Text('Aucun étudiant trouvé', style: TextStyle(color: Colors.grey)));
        return ListView.builder(itemCount: list.length, padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (_, i) => _StudentTile(student: list[i]));
      },
    );
  }
}

// ─────────────────────────────────────────────
// STUDENT TILE
// ─────────────────────────────────────────────
class _StudentTile extends StatelessWidget {
  final Student student;
  const _StudentTile({required this.student});
  Color    get _color => student.qrCodeScanned ? kOrange : student.hasPaid ? kGreenLight : kGrey;
  IconData get _icon  => student.qrCodeScanned ? Icons.how_to_reg : student.hasPaid ? Icons.check_circle : Icons.radio_button_unchecked;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: ListTile(
      leading: CircleAvatar(backgroundColor: _color.withOpacity(0.15),
        backgroundImage: student.photo != null ? MemoryImage(base64Decode(student.photo!)) : null,
        child: student.photo == null ? Icon(Icons.person, color: _color) : null),
      title:    Text('${student.prenom} ${student.nom}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${student.matricule} · ${student.niveau} ${student.parcours}',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      trailing: Icon(_icon, color: _color),
      onTap: () => _openProfile(context, student)));
}

void _openProfile(BuildContext context, Student student) {
  showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _StudentModal(student: student));
}

// ─────────────────────────────────────────────
// STUDENT MODAL
// ─────────────────────────────────────────────
class _StudentModal extends StatefulWidget {
  final Student student;
  const _StudentModal({required this.student});
  @override
  State<_StudentModal> createState() => _StudentModalState();
}

class _StudentModalState extends State<_StudentModal> {
  late bool _hasPaid, _qrGenerated;
  bool _loading = false, _showCamera = false;
  CameraController? _cam;
  // Clé pour capturer le widget QrImageView pixel-perfect
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _hasPaid     = widget.student.hasPaid;
    _qrGenerated = widget.student.qrCodeGenerated;
  }

  @override
  void dispose() { _cam?.dispose(); super.dispose(); }

  Future<void> _togglePaid(bool value) async {
    setState(() => _loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final ref   = FirebaseFirestore.instance.collection('students').doc(widget.student.matricule);
      final stats = FirebaseFirestore.instance.collection('counters').doc('stats');
      final d = value ? 1 : -1;
      final niv = widget.student.niveau; final par = widget.student.parcours;
      batch.update(ref, {'has_paid': value});
      batch.update(stats, {
        'total_paid': FieldValue.increment(d), '${niv}_paid': FieldValue.increment(d),
        '${par}_paid': FieldValue.increment(d), '${niv}_${par}_paid': FieldValue.increment(d),
      });
      await batch.commit();
      if (mounted) setState(() { _hasPaid = value; });
    } catch (_) {
      if (mounted) showMsg(context, 'Impossible de mettre à jour le paiement. Vérifiez votre connexion.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ════════════════════════════════════════════
  // QR Code : capture pixel-perfect du widget
  // QrImageView via RepaintBoundary → PNG identique
  // à ce qui est affiché (anneaux + modules + marges).
  // ════════════════════════════════════════════
  Future<void> _generateQrCode() async {
    setState(() => _loading = true);
    try {
      final s     = widget.student;
      final fname = '${s.matricule}_${s.niveau}_${s.parcours}.png';

      // Attendre que le frame soit rendu avant de capturer
      await Future.delayed(const Duration(milliseconds: 150));

      // Trouver le RenderRepaintBoundary lié à _qrKey
      final boundary = _qrKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Widget QR introuvable');

      // pixelRatio * 2 → image haute résolution (ex: 6x sur Pixel)
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final uiImage   = await boundary.toImage(pixelRatio: pixelRatio * 2);
      final byteData  = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Génération échouée');
      final bytes = byteData.buffer.asUint8List();

      // Sauvegarder dans Pictures/AgroPass
      final dir = Directory('/storage/emulated/0/Pictures/AgroPass');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$fname');
      await file.writeAsBytes(bytes);

      // Notifier Android → galerie photos
      try {
        await Process.run('am', [
          'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
          '-d', 'file://${file.path}'
        ]);
      } catch (_) {}

      // Marquer comme généré dans Firestore
      await FirebaseFirestore.instance
          .collection('students').doc(s.matricule)
          .update({'qr_code_generated': true});

      if (mounted) {
        setState(() => _qrGenerated = true);
        showMsg(context, '✅ QR Code enregistré dans\nGalerie → AgroPass → $fname');
      }
    } catch (e) {
      if (mounted) showMsg(context,
        "Impossible d'enregistrer le QR Code. Vérifiez que l'espace de stockage est disponible.",
        error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) showMsg(context, 'Permission caméra refusée. Activez-la dans les paramètres du téléphone.', error: true);
      return;
    }
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) { if (mounted) showMsg(context, 'Aucune caméra disponible sur cet appareil.', error: true); return; }
      final rear = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      _cam = CameraController(rear, ResolutionPreset.high, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() => _showCamera = true);
    } catch (_) {
      if (mounted) showMsg(context, 'Impossible d\'ouvrir la caméra.', error: true);
    }
  }

  Future<void> _takePicture() async {
    if (_cam == null) return;
    setState(() => _loading = true);
    try {
      final xf  = await _cam!.takePicture();
      final dec = img.decodeImage(await File(xf.path).readAsBytes());
      if (dec == null) throw Exception('Photo illisible');
      final b64 = base64Encode(img.encodeJpg(img.copyResize(dec, width: 400), quality: 80));
      await FirebaseFirestore.instance.collection('students').doc(widget.student.matricule).update({'photo': b64});
      if (mounted) {
        setState(() => _showCamera = false);
        showMsg(context, 'Photo enregistrée avec succès.');
      }
    } catch (_) {
      if (mounted) showMsg(context, 'Échec de la capture photo. Réessayez.', error: true);
    } finally {
      await _cam?.dispose(); _cam = null;
      if (mounted) setState(() { _loading = false; _showCamera = false; });
    }
  }

  Future<void> _pickGallery() async {
    setState(() => _loading = true);
    try {
      final xf = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 400);
      if (xf == null) { setState(() => _loading = false); return; }
      final dec = img.decodeImage(await File(xf.path).readAsBytes());
      if (dec == null) throw Exception('Image illisible');
      final b64 = base64Encode(img.encodeJpg(img.copyResize(dec, width: 400), quality: 80));
      await FirebaseFirestore.instance.collection('students').doc(widget.student.matricule).update({'photo': b64});
      if (mounted) showMsg(context, 'Photo importée avec succès.');
    } catch (_) {
      if (mounted) showMsg(context, 'Impossible d\'importer la photo. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPhotoMenu() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Photo de profil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.camera_alt, color: kGreen, size: 28)),
            title: const Text('Prendre une photo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            subtitle: const Text('Caméra arrière — plein écran'),
            onTap: () { Navigator.pop(context); _openCamera(); }),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.photo_library, color: kOrange, size: 28)),
            title: const Text('Choisir depuis la galerie', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            subtitle: const Text('Importer depuis votre galerie'),
            onTap: () { Navigator.pop(context); _pickGallery(); }),
          const SizedBox(height: 16),
        ])));
  }

  String get _qrData => '${widget.student.matricule}_${widget.student.niveau}_${widget.student.parcours}';

  @override
  Widget build(BuildContext context) {
    if (_showCamera && _cam != null && _cam!.value.isInitialized) {
      return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
        Positioned.fill(child: CameraPreview(_cam!)),
        Positioned(top: 0, left: 0, right: 0, child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 12, left: 12, right: 12),
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent])),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () { _cam?.dispose(); _cam = null; setState(() => _showCamera = false); }),
            const Spacer(),
            const Text('Prendre une photo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(), const SizedBox(width: 48),
          ]))),
        Center(child: Container(width: 260, height: 260,
          decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 3)))),
        Positioned(bottom: 50, left: 0, right: 0, child: Center(child: GestureDetector(
          onTap: _loading ? null : _takePicture,
          child: Container(width: 80, height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
              border: Border.all(color: kGreen, width: 4),
              boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)]),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: kGreen, strokeWidth: 3))
                : const Icon(Icons.camera_alt, color: kGreen, size: 36))))),
      ]));
    }

    final s = widget.student;
    return DraggableScrollableSheet(
      initialChildSize: 0.92, maxChildSize: 0.97, minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Expanded(child: ListView(controller: ctrl, padding: const EdgeInsets.all(20), children: [
            Center(child: Column(children: [
              GestureDetector(onTap: _showPhotoMenu, child: Stack(children: [
                Container(width: 130, height: 130,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: kGreen, width: 3), color: kGreen.withOpacity(0.1)),
                  child: ClipOval(child: s.photo != null
                    ? Image.memory(base64Decode(s.photo!), fit: BoxFit.cover)
                    : const Icon(Icons.person, size: 70, color: kGreen))),
                Positioned(bottom: 4, right: 4, child: Container(padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 18))),
              ])),
              const SizedBox(height: 12),
              Text('${s.prenom} ${s.nom}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Matricule : ${s.matricule}', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _Badge(label: s.niveau, color: kGreen), const SizedBox(width: 6), _Badge(label: s.parcours, color: kOrange)]),
            ])),
            const SizedBox(height: 20), const Divider(),
            SwitchListTile(
              title: const Text('Paiement reçu', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              subtitle: Text(_hasPaid ? 'Paiement validé ✓' : 'En attente de paiement'),
              value: _hasPaid, activeColor: kGreen,
              onChanged: _loading ? null : _togglePaid),
            const Divider(),
            if (_hasPaid) ...[
              const SizedBox(height: 16),
              // RepaintBoundary : permet de capturer ce widget
              // exactement tel qu'il est affiché → PNG pixel-perfect
              Center(child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: const Offset(0, 4))]),
                  child: QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: kGreen),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: kGreen))))),
              const SizedBox(height: 8),
              Center(child: Text(_qrData, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
              const SizedBox(height: 4),
              Center(child: Text('Galerie → AgroPass → $_qrData.png',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11), textAlign: TextAlign.center)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                icon: Icon(_qrGenerated ? Icons.check_circle : Icons.download),
                label: Text(_qrGenerated ? 'QR Code enregistré ✓' : 'Enregistrer dans la galerie'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _qrGenerated ? Colors.grey.shade400 : kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: (_loading || _qrGenerated) ? null : _generateQrCode)),
            ] else ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300)),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.amber), SizedBox(width: 10),
                  Expanded(child: Text(
                    'Le QR Code sera disponible une fois le paiement validé.',
                    style: TextStyle(color: Colors.black87, fontSize: 14))),
                ])),
            ],
            const SizedBox(height: 20),
          ])),
        ])));
  }
}

// ─────────────────────────────────────────────
// BADGE
// ─────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label; final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.4))),
    child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)));
}

// ─────────────────────────────────────────────
// ADD STUDENT DIALOG
// ─────────────────────────────────────────────
class _AddStudentDialog extends StatefulWidget {
  const _AddStudentDialog();
  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
  final _mCtrl = TextEditingController();
  final _nCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  String _niveau = 'L1', _parcours = 'PA';
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (_mCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le numéro de matricule est obligatoire.'); return;
    }
    if (_nCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le nom de l\'étudiant est obligatoire.'); return;
    }

    final mat = _mCtrl.text.trim();
    setState(() { _loading = true; _error = null; });
    try {
      final ref = FirebaseFirestore.instance.collection('students').doc(mat);
      if ((await ref.get()).exists) {
        setState(() => _error = 'Ce matricule ($mat) existe déjà dans la base de données.');
        return;
      }
      final batch = FirebaseFirestore.instance.batch();
      final stats = FirebaseFirestore.instance.collection('counters').doc('stats');
      batch.set(ref, {
        'nom': _nCtrl.text.trim(), 'prenom': _pCtrl.text.trim(),
        'niveau': _niveau, 'parcours': _parcours,
        'has_paid': false, 'qr_code_generated': false, 'qr_code_scanned': false,
      });
      batch.update(stats, {
        'total_students': FieldValue.increment(1),
        '${_niveau}_total': FieldValue.increment(1),
        '${_parcours}_total': FieldValue.increment(1),
        '${_niveau}_${_parcours}_total': FieldValue.increment(1),
      });
      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _error = 'Impossible d\'ajouter l\'étudiant. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter un étudiant'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _mCtrl, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Matricule *', hintText: 'Ex: 1234')),
      const SizedBox(height: 8),
      TextField(controller: _nCtrl, textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Nom *', hintText: 'Ex: RAKOTO')),
      const SizedBox(height: 8),
      TextField(controller: _pCtrl, textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Prénom', hintText: 'Ex: Jean Marie')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: _niveau, decoration: const InputDecoration(labelText: 'Niveau *'),
        items: kNiveaux.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
        onChanged: (v) => setState(() => _niveau = v!)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: _parcours, decoration: const InputDecoration(labelText: 'Parcours *'),
        items: kParcours.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
        onChanged: (v) => setState(() => _parcours = v!)),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade300)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
          ])),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      ElevatedButton(onPressed: _loading ? null : _save,
        style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white),
        child: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Ajouter')),
    ]);
}

// ─────────────────────────────────────────────
// SCANNER PAGE
// ─────────────────────────────────────────────
class ScannerPage extends StatefulWidget {
  final bool showAppBar;
  const ScannerPage({super.key, this.showAppBar = true});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final b = capture.barcodes.firstOrNull;
    if (b?.rawValue == null) return;
    setState(() => _processing = true);
    await _ctrl.stop();
    final parts = b!.rawValue!.split('_');
    if (parts.length < 3) { _err('QR Code non reconnu. Ce code ne correspond pas à un étudiant.'); return; }
    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(parts[0]).get();
      if (!doc.exists) { if (mounted) _err('Étudiant introuvable dans la base de données.'); return; }
      final student = Student.fromFirestore(doc);
      final filter  = getCurrentFilter();
      if (filter != null && filter.niveau != null) {
        if (student.niveau != filter.niveau ||
            (filter.parcours != null && student.parcours != filter.parcours)) {
          if (mounted) _err('Accès refusé : cet étudiant n\'appartient pas à votre classe.'); return;
        }
      }
      if (mounted) showDialog(context: context, barrierDismissible: false,
        builder: (_) => _ScanConfirmDialog(student: student,
          onDone: () { setState(() => _processing = false); _ctrl.start(); }));
    } catch (_) {
      if (mounted) _err('Erreur de connexion. Vérifiez votre accès internet et réessayez.');
    }
  }

  void _err(String msg) {
    setState(() => _processing = false);
    showMsg(context, msg, error: true);
    _ctrl.start();
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(children: [
      MobileScanner(controller: _ctrl, onDetect: _onDetect),
      Center(child: Container(width: 260, height: 260,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kGreenLight, width: 4)))),
      Positioned(bottom: 40, left: 0, right: 0, child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: const Text('Placez le QR Code dans le cadre', style: TextStyle(color: Colors.white))))),
      if (_processing) const ColoredBox(color: Colors.black45,
        child: Center(child: CircularProgressIndicator(color: Colors.white))),
    ]);
    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(backgroundColor: kGreen, foregroundColor: Colors.white, title: const Text('Scanner QR Code'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())]),
      body: Column(children: [
        Expanded(child: body),
        Container(color: Colors.white, padding: const EdgeInsets.all(16),
          child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
            icon: const Icon(Icons.search), label: const Text('Saisie manuelle du matricule'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchIdPage()))))),
      ]));
  }
}

// ─────────────────────────────────────────────
// SCAN CONFIRM DIALOG
// ─────────────────────────────────────────────
class _ScanConfirmDialog extends StatefulWidget {
  final Student student; final VoidCallback onDone;
  const _ScanConfirmDialog({required this.student, required this.onDone});
  @override
  State<_ScanConfirmDialog> createState() => _ScanConfirmDialogState();
}

class _ScanConfirmDialogState extends State<_ScanConfirmDialog> {
  bool _loading = false;

  Future<void> _validate() async {
    setState(() => _loading = true);
    if (widget.student.qrCodeScanned) {
      Navigator.pop(context); widget.onDone();
      showMsg(context, '⛔ Accès refusé : cet étudiant est déjà entré.', error: true);
      return;
    }
    try {
      final batch = FirebaseFirestore.instance.batch();
      final ref   = FirebaseFirestore.instance.collection('students').doc(widget.student.matricule);
      final stats = FirebaseFirestore.instance.collection('counters').doc('stats');
      final niv = widget.student.niveau; final par = widget.student.parcours;
      batch.update(ref, {'qr_code_scanned': true});
      batch.update(stats, {
        'total_scanned': FieldValue.increment(1), '${niv}_scanned': FieldValue.increment(1),
        '${par}_scanned': FieldValue.increment(1), '${niv}_${par}_scanned': FieldValue.increment(1),
      });
      await batch.commit();
      if (mounted) {
        Navigator.pop(context); widget.onDone();
        _openProfile(context, widget.student);
        showMsg(context, '✅ Entrée validée : ${widget.student.prenom} ${widget.student.nom}');
      }
    } catch (_) {
      if (mounted) {
        showMsg(context, 'Erreur de connexion. Impossible de valider l\'entrée.', error: true);
        Navigator.pop(context); widget.onDone();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student; final already = s.qrCodeScanned;
    return Dialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(already ? Icons.warning_amber_rounded : Icons.how_to_reg,
            color: already ? Colors.red : kGreen, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(already ? 'Accès déjà validé' : 'Confirmation d\'entrée',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 20),
        if (already) Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red)),
          child: const Text('⛔ CET ÉTUDIANT EST DÉJÀ ENTRÉ', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16))),
        Container(width: 120, height: 120,
          decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: already ? Colors.red : kGreen, width: 3),
            color: kGreen.withOpacity(0.1)),
          child: ClipOval(child: s.photo != null
            ? Image.memory(base64Decode(s.photo!), fit: BoxFit.cover)
            : const Icon(Icons.person, size: 60, color: kGreen))),
        const SizedBox(height: 16),
        Text('${s.prenom} ${s.nom}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Matricule : ${s.matricule}', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Badge(label: s.niveau, color: kGreen), const SizedBox(width: 8), _Badge(label: s.parcours, color: kOrange)]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () { Navigator.pop(context); widget.onDone(); },
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Annuler', style: TextStyle(fontSize: 15)))),
          if (!already) ...[const SizedBox(width: 12),
            Expanded(child: ElevatedButton(onPressed: _loading ? null : _validate,
              style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Valider l\'entrée', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))))],
        ]),
      ])));
  }
}

// ─────────────────────────────────────────────
// SEARCH ID PAGE
// ─────────────────────────────────────────────
class SearchIdPage extends StatefulWidget {
  final bool showAppBar; final String? filterNiveau, filterParcours;
  const SearchIdPage({super.key, this.showAppBar = true, this.filterNiveau, this.filterParcours});
  @override
  State<SearchIdPage> createState() => _SearchIdPageState();
}

class _SearchIdPageState extends State<SearchIdPage> {
  final _ctrl = TextEditingController();
  Student? _found; String? _error; bool _loading = false;

  Future<void> _search() async {
    final mat = _ctrl.text.trim();
    if (mat.isEmpty) {
      setState(() => _error = 'Veuillez entrer un numéro de matricule.');
      return;
    }
    setState(() { _loading = true; _found = null; _error = null; });
    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(mat).get();
      if (!doc.exists) {
        setState(() => _error = 'Aucun étudiant trouvé avec le matricule "$mat".');
        return;
      }
      final student = Student.fromFirestore(doc);
      if (widget.filterNiveau  != null && student.niveau   != widget.filterNiveau) {
        setState(() => _error = 'Cet étudiant appartient au niveau ${student.niveau}, pas à ${widget.filterNiveau}.');
        return;
      }
      if (widget.filterParcours != null && student.parcours != widget.filterParcours) {
        setState(() => _error = 'Cet étudiant est en parcours ${student.parcours}, pas ${widget.filterParcours}.');
        return;
      }
      setState(() => _found = student);
    } catch (_) {
      setState(() => _error = 'Erreur de connexion. Vérifiez votre accès internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _validateEntry() async {
    if (_found == null || _found!.qrCodeScanned) return;
    setState(() => _loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final ref   = FirebaseFirestore.instance.collection('students').doc(_found!.matricule);
      final stats = FirebaseFirestore.instance.collection('counters').doc('stats');
      final niv = _found!.niveau; final par = _found!.parcours;
      batch.update(ref, {'qr_code_scanned': true});
      batch.update(stats, {
        'total_scanned': FieldValue.increment(1), '${niv}_scanned': FieldValue.increment(1),
        '${par}_scanned': FieldValue.increment(1), '${niv}_${par}_scanned': FieldValue.increment(1),
      });
      await batch.commit();
      if (mounted) {
        showMsg(context, '✅ Entrée validée : ${_found!.prenom} ${_found!.nom}');
        setState(() => _found = _found!.copyWith(qrCodeScanned: true));
      }
    } catch (_) {
      if (mounted) showMsg(context, 'Erreur de connexion. Impossible de valider l\'entrée.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
      const Text('Saisie manuelle du matricule',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kGreen)),
      const SizedBox(height: 6),
      const Text('Utilisez cette option si le QR Code ne peut pas être scanné.',
        style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: TextField(controller: _ctrl, keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            labelText: 'Numéro de matricule',
            hintText: 'Ex: 1234',
            prefixIcon: const Icon(Icons.badge, size: 26),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16)),
          onSubmitted: (_) => _search())),
        const SizedBox(width: 12),
        SizedBox(height: 56, width: 56, child: ElevatedButton(onPressed: _loading ? null : _search,
          style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white,
            padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.search, size: 28))),
      ]),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Container(width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14))),
          ])),
      ],
      if (_found != null) ...[
        const SizedBox(height: 24),
        Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4,
          child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            if (_found!.qrCodeScanned) Container(width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red)),
              child: const Text('⛔ CET ÉTUDIANT EST DÉJÀ ENTRÉ', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15))),
            Container(width: 110, height: 110,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: _found!.qrCodeScanned ? Colors.red : kGreen, width: 3),
                color: kGreen.withOpacity(0.08)),
              child: ClipOval(child: _found!.photo != null
                ? Image.memory(base64Decode(_found!.photo!), fit: BoxFit.cover)
                : const Icon(Icons.person, size: 55, color: kGreen))),
            const SizedBox(height: 14),
            Text('${_found!.prenom} ${_found!.nom}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Matricule : ${_found!.matricule}', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Badge(label: _found!.niveau, color: kGreen),
              const SizedBox(width: 8),
              _Badge(label: _found!.parcours, color: kOrange)]),
            if (!_found!.qrCodeScanned) ...[
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                icon: const Icon(Icons.how_to_reg),
                label: const Text('Valider l\'entrée', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _loading ? null : _validateEntry)),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                icon: const Icon(Icons.person),
                label: const Text('Voir le profil complet', style: TextStyle(fontSize: 15)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => _openProfile(context, _found!))),
            ],
          ]))),
      ],
    ]));

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(backgroundColor: kGreen, foregroundColor: Colors.white, title: const Text('Recherche par ID'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())]),
      body: body);
  }
}

// ─────────────────────────────────────────────
// EXTENSION COPYWITH
// ─────────────────────────────────────────────
extension StudentCopyWith on Student {
  Student copyWith({String? matricule, String? nom, String? prenom, String? niveau,
      String? parcours, bool? hasPaid, bool? qrCodeGenerated, bool? qrCodeScanned, String? photo}) {
    return Student(
      matricule: matricule ?? this.matricule, nom: nom ?? this.nom, prenom: prenom ?? this.prenom,
      niveau: niveau ?? this.niveau, parcours: parcours ?? this.parcours,
      hasPaid: hasPaid ?? this.hasPaid, qrCodeGenerated: qrCodeGenerated ?? this.qrCodeGenerated,
      qrCodeScanned: qrCodeScanned ?? this.qrCodeScanned, photo: photo ?? this.photo);
  }
}