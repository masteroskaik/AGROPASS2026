import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
// CLÉS D'ACCÈS 8 CHIFFRES (Clés secrètes)
// ─────────────────────────────────────────────
const Map<String, ({String? niveau, String? parcours})> _classKeys = {
  '73928465': (niveau: null, parcours: null),   // Accès complet - Admin secret
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
  // Admin (73928465) = null niveau => no filter
  if (entry.niveau == null && entry.parcours == null) return null;
  return entry;
}

bool isAdmin() {
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

class AgroPassApp extends StatelessWidget {
  const AgroPassApp({super.key});
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
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_role == 'admin') {
      final filter = getCurrentFilter();
      // isFirebaseAdmin = true pour tous les utilisateurs avec role=='admin' dans Firestore
      // Le bouton + s'affiche pour TOUS les admins Firestore (clé admin ET clé M1, L1, etc.)
      return AdminDashboard(
        initialNiveau: filter?.niveau,
        initialParcours: filter?.parcours,
        isFirebaseAdmin: true,   // rôle vient de Firestore → toujours admin
      );
    }
    return const ScannerPage();
  }
}

// ─────────────────────────────────────────────
// COLORS & CONSTANTS
// ─────────────────────────────────────────────
const kGreen = Color(0xFF2E7D32);
const kGreenLight = Color(0xFF4CAF50);
const kOrange = Color(0xFFF57C00);
const kGrey = Color(0xFF9E9E9E);
const kBg = Color(0xFFF1F8E9);

const List<String> kNiveaux = ['L1', 'L2', 'L3', 'M1'];
const List<String> kParcours = ['3COM', 'IAAB', 'PA', 'PV'];

// ─────────────────────────────────────────────
// STUDENT MODEL
// ─────────────────────────────────────────────
class Student {
  final String matricule;
  final String nom;
  final String prenom;
  final String niveau;
  final String parcours;
  final bool hasPaid;
  final bool qrCodeGenerated;
  final bool qrCodeScanned;
  final String? photo;

  Student({
    required this.matricule,
    required this.nom,
    required this.prenom,
    required this.niveau,
    required this.parcours,
    required this.hasPaid,
    required this.qrCodeGenerated,
    required this.qrCodeScanned,
    this.photo,
  });

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Student(
      matricule: doc.id,
      nom: d['nom'] ?? '',
      prenom: d['prenom'] ?? '',
      niveau: d['niveau'] ?? '',
      parcours: d['parcours'] ?? '',
      hasPaid: d['has_paid'] ?? false,
      qrCodeGenerated: d['qr_code_generated'] ?? false,
      qrCodeScanned: d['qr_code_scanned'] ?? false,
      photo: d['photo'] as String?,
    );
  }
}

// ─────────────────────────────────────────────
// LOGIN PAGE — Champs élargis
// ─────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    // Validate key
    final key = _keyCtrl.text.trim();
    if (key.isNotEmpty && !_classKeys.containsKey(key)) {
      setState(() => _error = 'Clé d\'accès invalide.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      currentAccessKey = key.isEmpty ? '73928465' : key;
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.code == 'user-not-found' || e.code == 'wrong-password'
            ? 'Email ou mot de passe incorrect.'
            : 'Erreur : ${e.message}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: kGreen,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: kGreen.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon/icon-agro.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text("by M'ôskaik studio", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kGreen, letterSpacing: 3)),
              const Text('2026 — Fianarantsoa', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 40),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Email — champ large
                      SizedBox(
                        height: 64,
                        child: TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: const TextStyle(fontSize: 15),
                            prefixIcon: const Icon(Icons.email_outlined, size: 24),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Mot de passe — champ large
                      SizedBox(
                        height: 64,
                        child: TextField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            labelStyle: const TextStyle(fontSize: 15),
                            prefixIcon: const Icon(Icons.lock_outlined, size: 24),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Clé d'accès — champ large
                      SizedBox(
                        height: 64,
                        child: TextField(
                          controller: _keyCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 8,
                          style: const TextStyle(fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: 'Clé d\'accès (8 chiffres)',
                            labelStyle: const TextStyle(fontSize: 15),
                            prefixIcon: const Icon(Icons.key_outlined, size: 24),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                            counterText: '',
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                          child: Row(children: [const Icon(Icons.error_outline, color: Colors.red, size: 18), const SizedBox(width: 8), Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red)))]),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: _loading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('SE CONNECTER', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN DASHBOARD
// ─────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  final String? initialNiveau;
  final String? initialParcours;
  const AdminDashboard({super.key, this.initialNiveau, this.initialParcours});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  late String? _filterNiveau;
  late String? _filterParcours;
  String _searchQuery = '';

  // Determine if current user has full admin rights
  bool get _isFullAdmin => isAdmin();

  @override
  void initState() {
    super.initState();
    _filterNiveau = widget.initialNiveau;
    _filterParcours = widget.initialParcours;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('AGRO PASS — Admin', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_isFullAdmin)
            IconButton(icon: const Icon(Icons.add), tooltip: 'Ajouter étudiant', onPressed: () => _showAddStudentDialog(context)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: _currentIndex == 0
          ? _buildDashboardBody()
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

  Widget _buildDashboardBody() {
    return Column(
      children: [
        _StatsHeader(filterNiveau: _filterNiveau, filterParcours: _filterParcours),
        _FiltersBar(
          selectedNiveau: _filterNiveau,
          selectedParcours: _filterParcours,
          searchQuery: _searchQuery,
          isFullAdmin: _isFullAdmin,
          onNiveauChanged: _isFullAdmin ? (v) => setState(() => _filterNiveau = v) : null,
          onParcoursChanged: _isFullAdmin ? (v) => setState(() => _filterParcours = v) : null,
          onSearchChanged: (v) => setState(() => _searchQuery = v),
        ),
        Expanded(
          child: _StudentsList(
            filterNiveau: _filterNiveau,
            filterParcours: _filterParcours,
            searchQuery: _searchQuery,
          ),
        ),
      ],
    );
  }

  void _showAddStudentDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _AddStudentDialog());
  }
}

// ─────────────────────────────────────────────
// STATS HEADER
// ─────────────────────────────────────────────
class _StatsHeader extends StatelessWidget {
  final String? filterNiveau;
  final String? filterParcours;
  const _StatsHeader({this.filterNiveau, this.filterParcours});

  String _statsKey(String suffix) {
    if (filterNiveau != null && filterParcours != null) return '${filterNiveau}_${filterParcours}_$suffix';
    if (filterNiveau != null) return '${filterNiveau}_$suffix';
    if (filterParcours != null) return '${filterParcours}_$suffix';
    return 'total_$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('counters').doc('stats').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final total = data[_statsKey('total')] ?? 0;
        final paid = data[_statsKey('paid')] ?? 0;
        final scanned = data[_statsKey('scanned')] ?? 0;

        return Container(
          color: kGreen,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              _StatChip(icon: Icons.people, label: 'Total', value: total.toString(), color: Colors.white),
              _StatChip(icon: Icons.payments, label: 'Payés', value: paid.toString(), color: Colors.greenAccent),
              _StatChip(icon: Icons.login, label: 'Entrés', value: scanned.toString(), color: Colors.orangeAccent),
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// FILTERS BAR — Respecte la clé de filtre
// ─────────────────────────────────────────────
class _FiltersBar extends StatelessWidget {
  final String? selectedNiveau;
  final String? selectedParcours;
  final String searchQuery;
  final bool isFullAdmin;
  final ValueChanged<String?>? onNiveauChanged;
  final ValueChanged<String?>? onParcoursChanged;
  final ValueChanged<String> onSearchChanged;

  const _FiltersBar({
    required this.selectedNiveau,
    required this.selectedParcours,
    required this.searchQuery,
    required this.isFullAdmin,
    required this.onNiveauChanged,
    required this.onParcoursChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Rechercher nom ou matricule...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          if (isFullAdmin)
            Row(
              children: [
                Expanded(child: _FilterDropdown(label: 'Niveau', value: selectedNiveau, items: [null, ...kNiveaux], getLabel: (v) => v ?? 'Tous', onChanged: onNiveauChanged!)),
                const SizedBox(width: 8),
                Expanded(child: _FilterDropdown(label: 'Parcours', value: selectedParcours, items: [null, ...kParcours], getLabel: (v) => v ?? 'Tous', onChanged: onParcoursChanged!)),
              ],
            )
          else
            // Non-admin: show locked filter info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: kGreen.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: kGreen.withOpacity(0.3))),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, color: kGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Filtre : ${selectedNiveau ?? ''} ${selectedParcours ?? ''}'.trim(),
                    style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  const Icon(Icons.lock, color: kGrey, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String?> items;
  final String Function(String?) getLabel;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({required this.label, required this.value, required this.items, required this.getLabel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: value,
      decoration: InputDecoration(labelText: label, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
      items: items.map((v) => DropdownMenuItem(value: v, child: Text(getLabel(v)))).toList(),
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────
// STUDENTS LIST
// ─────────────────────────────────────────────
class _StudentsList extends StatelessWidget {
  final String? filterNiveau;
  final String? filterParcours;
  final String searchQuery;

  const _StudentsList({this.filterNiveau, this.filterParcours, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('students');

    if (filterNiveau != null) query = query.where('niveau', isEqualTo: filterNiveau);
    if (filterParcours != null) query = query.where('parcours', isEqualTo: filterParcours);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var students = snapshot.data!.docs.map((d) => Student.fromFirestore(d)).toList();

        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          students = students.where((s) => s.matricule.toLowerCase().contains(q) || s.nom.toLowerCase().contains(q) || s.prenom.toLowerCase().contains(q)).toList();
        }

        if (students.isEmpty) return const Center(child: Text('Aucun étudiant trouvé', style: TextStyle(color: Colors.grey)));

        return ListView.builder(
          itemCount: students.length,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (context, i) => _StudentTile(student: students[i]),
        );
      },
    );
  }
}

class _StudentTile extends StatelessWidget {
  final Student student;
  const _StudentTile({required this.student});

  Color get _statusColor => student.qrCodeScanned ? kOrange : student.hasPaid ? kGreenLight : kGrey;
  IconData get _statusIcon => student.qrCodeScanned ? Icons.how_to_reg : student.hasPaid ? Icons.check_circle : Icons.radio_button_unchecked;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor.withOpacity(0.15),
          backgroundImage: student.photo != null ? MemoryImage(base64Decode(student.photo!)) : null,
          child: student.photo == null ? Icon(Icons.person, color: _statusColor) : null,
        ),
        title: Text('${student.prenom} ${student.nom}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${student.matricule} · ${student.niveau} ${student.parcours}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        trailing: Icon(_statusIcon, color: _statusColor),
        onTap: () => _openStudentProfile(context, student),
      ),
    );
  }
}

void _openStudentProfile(BuildContext context, Student student) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StudentModal(student: student),
  );
}

// ─────────────────────────────────────────────
// STUDENT MODAL — Photo plein écran + QR ronds
// ─────────────────────────────────────────────
class _StudentModal extends StatefulWidget {
  final Student student;
  const _StudentModal({required this.student});
  @override
  State<_StudentModal> createState() => _StudentModalState();
}

class _StudentModalState extends State<_StudentModal> {
  late bool _hasPaid;
  late bool _qrGenerated;
  bool _loading = false;
  bool _showFullCamera = false;
  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    _hasPaid = widget.student.hasPaid;
    _qrGenerated = widget.student.qrCodeGenerated;
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _togglePaid(bool value) async {
    setState(() => _loading = true);
    final batch = FirebaseFirestore.instance.batch();
    final ref = FirebaseFirestore.instance.collection('students').doc(widget.student.matricule);
    final statsRef = FirebaseFirestore.instance.collection('counters').doc('stats');
    final increment = value ? 1 : -1;
    final niv = widget.student.niveau;
    final par = widget.student.parcours;

    batch.update(ref, {'has_paid': value});
    batch.update(statsRef, {
      'total_paid': FieldValue.increment(increment),
      '${niv}_paid': FieldValue.increment(increment),
      '${par}_paid': FieldValue.increment(increment),
      '${niv}_${par}_paid': FieldValue.increment(increment),
    });

    await batch.commit();
    if (mounted) setState(() { _hasPaid = value; _loading = false; });
  }

  Future<void> _generateQrCode() async {
    setState(() => _loading = true);
    try {
      final qrData = '${widget.student.matricule}_${widget.student.niveau}_${widget.student.parcours}';
      final qrPainter = QrPainter(
        data: qrData,
        version: QrVersions.auto,
        gapless: true,
        color: kGreen,
        emptyColor: Colors.white,
      );

      final imageData = await qrPainter.toImageData(512);
      if (imageData == null) throw Exception('Erreur génération QR');

      final dir = await _getQrDirectory();
      final file = File('${dir.path}/${widget.student.matricule}_${widget.student.niveau}.png');
      await file.writeAsBytes(imageData.buffer.asUint8List());

      await FirebaseFirestore.instance.collection('students').doc(widget.student.matricule).update({'qr_code_generated': true});

      if (mounted) {
        setState(() => _qrGenerated = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('QR Code sauvegardé : ${file.path}'), backgroundColor: kGreen));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Directory> _getQrDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory('${appDir.path}/qr_agro');
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    return baseDir;
  }

  // ── Ouvre la caméra ARRIÈRE en plein écran ──
  Future<void> _openFullScreenCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    final cameras = await availableCameras();
    final rear = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(rear, ResolutionPreset.high, enableAudio: false);
    await _cameraController!.initialize();

    if (mounted) {
      setState(() => _showFullCamera = true);
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null) return;
    setState(() => _loading = true);
    try {
      final xfile = await _cameraController!.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Impossible de lire la photo');
      final resized = img.copyResize(decoded, width: 400);
      final jpeg = img.encodeJpg(resized, quality: 80);
      final base64Photo = base64Encode(jpeg);

      await FirebaseFirestore.instance.collection('students').doc(widget.student.matricule).update({'photo': base64Photo});

      if (mounted) {
        setState(() => _showFullCamera = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo enregistrée'), backgroundColor: kGreen));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur photo : $e'), backgroundColor: Colors.red));
    } finally {
      await _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() { _loading = false; _showFullCamera = false; });
    }
  }

  // ── Galerie (ImagePicker natif — même comportement qu'autres apps) ──
  Future<void> _pickFromGallery() async {
    setState(() => _loading = true);
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 400,
      );
      if (xfile == null) { setState(() => _loading = false); return; }

      final bytes = await File(xfile.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Impossible de lire la photo');
      final resized = img.copyResize(decoded, width: 400);
      final jpeg = img.encodeJpg(resized, quality: 80);
      final base64Photo = base64Encode(jpeg);

      await FirebaseFirestore.instance.collection('students').doc(widget.student.matricule).update({'photo': base64Photo});

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo importée avec succès'), backgroundColor: kGreen));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur importation : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Popup de choix photo (comme Facebook/Instagram) ──
  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Photo de profil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.camera_alt, color: kGreen, size: 28),
              ),
              title: const Text('Prendre une photo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              subtitle: const Text('Caméra arrière — plein écran'),
              onTap: () { Navigator.pop(context); _openFullScreenCamera(); },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.photo_library, color: kOrange, size: 28),
              ),
              title: const Text('Choisir depuis la galerie', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              subtitle: const Text('Importer depuis votre galerie'),
              onTap: () { Navigator.pop(context); _pickFromGallery(); },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String get _qrData => '${widget.student.matricule}_${widget.student.niveau}_${widget.student.parcours}';

  @override
  Widget build(BuildContext context) {
    // ── Caméra plein écran ──
    if (_showFullCamera && _cameraController != null && _cameraController!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Plein écran
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            ),
            // Overlay haut
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 12, left: 12, right: 12),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 30),
                      onPressed: () { _cameraController?.dispose(); _cameraController = null; setState(() => _showFullCamera = false); },
                    ),
                    const Spacer(),
                    const Text('Prendre une photo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            // Cercle guide
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 3),
                ),
              ),
            ),
            const Center(child: SizedBox()),
            // Bouton capture
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _loading ? null : _takePicture,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: kGreen, width: 4),
                      boxShadow: [BoxShadow(color: kGreen.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)],
                    ),
                    child: _loading
                        ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: kGreen, strokeWidth: 3))
                        : const Icon(Icons.camera_alt, color: kGreen, size: 36),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final s = widget.student;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.all(20),
                children: [
                  // ── PHOTO GRANDE + INFO ──
                  Center(
                    child: Column(
                      children: [
                        // Grande photo ronde cliquable
                        GestureDetector(
                          onTap: _showPhotoOptions,
                          child: Stack(
                            children: [
                              Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kGreen, width: 3),
                                  color: kGreen.withOpacity(0.1),
                                ),
                                child: ClipOval(
                                  child: s.photo != null
                                      ? Image.memory(base64Decode(s.photo!), fit: BoxFit.cover)
                                      : const Icon(Icons.person, size: 70, color: kGreen),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('${s.prenom} ${s.nom}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Text('Matricule : ${s.matricule}', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [_Badge(label: s.niveau, color: kGreen), const SizedBox(width: 6), _Badge(label: s.parcours, color: kOrange)]),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(),

                  SwitchListTile(
                    title: const Text('Paiement reçu', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    subtitle: Text(_hasPaid ? 'Paiement validé ✓' : 'En attente de paiement'),
                    value: _hasPaid,
                    activeColor: kGreen,
                    onChanged: _loading ? null : _togglePaid,
                  ),

                  const Divider(),

                  if (_hasPaid) ...[
                    const SizedBox(height: 16),
                    // ── QR CODE avec coins ronds (style image 3) ──
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: QrImageView(
                          data: _qrData,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                          foregroundColor: kGreen,
                          // Style arrondi (eye style)
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.circle,
                            color: kGreen,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle,
                            color: kGreen,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(child: Text(_qrData, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(_qrGenerated ? Icons.check_circle : Icons.download),
                        label: Text(_qrGenerated ? 'QR Code enregistré' : 'Enregistrer le QR Code'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _qrGenerated ? Colors.grey : kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (_loading || _qrGenerated) ? null : _generateQrCode,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                      child: const Row(children: [Icon(Icons.info_outline, color: Colors.grey), SizedBox(width: 8), Expanded(child: Text('Le QR Code sera disponible après validation du paiement.', style: TextStyle(color: Colors.grey)))]),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.4))),
      child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }
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
  final _matriculeCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  String _niveau = 'M1';
  String _parcours = '3COM';
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    final matricule = _matriculeCtrl.text.trim();
    if (matricule.isEmpty || _nomCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Matricule et nom sont obligatoires.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final ref = FirebaseFirestore.instance.collection('students').doc(matricule);
      if ((await ref.get()).exists) {
        setState(() => _error = 'Ce matricule existe déjà.');
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      batch.set(ref, {
        'nom': _nomCtrl.text.trim(),
        'prenom': _prenomCtrl.text.trim(),
        'niveau': _niveau,
        'parcours': _parcours,
        'has_paid': false,
        'qr_code_generated': false,
        'qr_code_scanned': false,
      });

      final statsRef = FirebaseFirestore.instance.collection('counters').doc('stats');
      batch.update(statsRef, {
        'total_students': FieldValue.increment(1),
        '${_niveau}_total': FieldValue.increment(1),
        '${_parcours}_total': FieldValue.increment(1),
        '${_niveau}_${_parcours}_total': FieldValue.increment(1),
      });

      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un étudiant'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _matriculeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Matricule *')),
            TextField(controller: _nomCtrl, decoration: const InputDecoration(labelText: 'Nom *')),
            TextField(controller: _prenomCtrl, decoration: const InputDecoration(labelText: 'Prénom')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(value: _niveau, decoration: const InputDecoration(labelText: 'Niveau'), items: kNiveaux.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(), onChanged: (v) => setState(() => _niveau = v!)),
            DropdownButtonFormField<String>(value: _parcours, decoration: const InputDecoration(labelText: 'Parcours'), items: kParcours.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(), onChanged: (v) => setState(() => _parcours = v!)),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: Colors.red))],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(onPressed: _loading ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white), child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Ajouter')),
      ],
    );
  }
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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _processing = true);
    await _ctrl.stop();

    final raw = barcode!.rawValue!;
    final parts = raw.split('_');
    if (parts.length < 3) {
      _showError('QR Code invalide');
      return;
    }
    final matricule = parts[0];

    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(matricule).get();
      if (!doc.exists) {
        if (mounted) _showError('Étudiant introuvable');
        return;
      }

      final student = Student.fromFirestore(doc);

      final filter = getCurrentFilter();
      if (filter != null && filter.niveau != null) {
        if (student.niveau != filter.niveau || (filter.parcours != null && student.parcours != filter.parcours)) {
          if (mounted) _showError('Accès refusé : étudiant non assigné à votre classe');
          return;
        }
      }

      if (mounted) _showConfirmation(student);
    } catch (e) {
      if (mounted) _showError('Erreur : $e');
    }
  }

  void _showError(String msg) {
    setState(() => _processing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    _ctrl.start();
  }

  void _showConfirmation(Student student) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScanConfirmDialog(
        student: student,
        onDone: () {
          setState(() => _processing = false);
          _ctrl.start();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),
        // Cadre ROND au lieu de carré
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kGreenLight, width: 4),
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: const Text('Placez le QR Code dans le cadre', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
        if (_processing) const ColoredBox(color: Colors.black45, child: Center(child: CircularProgressIndicator(color: Colors.white))),
      ],
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('Scanner QR Code'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())],
      ),
      body: Column(
        children: [
          Expanded(child: body),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Saisie manuelle'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchIdPage())),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SCAN CONFIRM DIALOG — Profil large et lisible
// ─────────────────────────────────────────────
class _ScanConfirmDialog extends StatefulWidget {
  final Student student;
  final VoidCallback onDone;
  const _ScanConfirmDialog({required this.student, required this.onDone});
  @override
  State<_ScanConfirmDialog> createState() => _ScanConfirmDialogState();
}

class _ScanConfirmDialogState extends State<_ScanConfirmDialog> {
  bool _loading = false;

  Future<void> _validate() async {
    setState(() => _loading = true);
    if (widget.student.qrCodeScanned) {
      Navigator.pop(context);
      widget.onDone();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⛔ ACCÈS DÉJÀ VALIDÉ'), backgroundColor: Colors.red));
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      final ref = FirebaseFirestore.instance.collection('students').doc(widget.student.matricule);
      final statsRef = FirebaseFirestore.instance.collection('counters').doc('stats');
      final niv = widget.student.niveau;
      final par = widget.student.parcours;

      batch.update(ref, {'qr_code_scanned': true});
      batch.update(statsRef, {
        'total_scanned': FieldValue.increment(1),
        '${niv}_scanned': FieldValue.increment(1),
        '${par}_scanned': FieldValue.increment(1),
        '${niv}_${par}_scanned': FieldValue.increment(1),
      });

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        // Ouvre le profil complet en grand après validation
        _openStudentProfile(context, widget.student);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Entrée validée : ${widget.student.prenom} ${widget.student.nom}'),
          backgroundColor: kGreen,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
        Navigator.pop(context);
        widget.onDone();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final alreadyScanned = s.qrCodeScanned;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(alreadyScanned ? Icons.warning_amber_rounded : Icons.how_to_reg, color: alreadyScanned ? Colors.red : kGreen, size: 28),
                const SizedBox(width: 10),
                Text(alreadyScanned ? 'Accès déjà validé' : 'Confirmation d\'entrée', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),

            if (alreadyScanned)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red)),
                child: const Text('⛔ ACCÈS DÉJÀ VALIDÉ', textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
              ),

            // Grande photo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: alreadyScanned ? Colors.red : kGreen, width: 3),
                color: kGreen.withOpacity(0.1),
              ),
              child: ClipOval(
                child: s.photo != null
                    ? Image.memory(base64Decode(s.photo!), fit: BoxFit.cover)
                    : const Icon(Icons.person, size: 60, color: kGreen),
              ),
            ),
            const SizedBox(height: 16),

            Text('${s.prenom} ${s.nom}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('Matricule : ${s.matricule}', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [_Badge(label: s.niveau, color: kGreen), const SizedBox(width: 8), _Badge(label: s.parcours, color: kOrange)]),

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () { Navigator.pop(context); widget.onDone(); },
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Annuler', style: TextStyle(fontSize: 15)),
                  ),
                ),
                if (!alreadyScanned) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _validate,
                      style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _loading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Valider', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SEARCH ID PAGE — Filtre respecté + profil large
// ─────────────────────────────────────────────
class SearchIdPage extends StatefulWidget {
  final bool showAppBar;
  final String? filterNiveau;
  final String? filterParcours;
  const SearchIdPage({super.key, this.showAppBar = true, this.filterNiveau, this.filterParcours});
  @override
  State<SearchIdPage> createState() => _SearchIdPageState();
}

class _SearchIdPageState extends State<SearchIdPage> {
  final _ctrl = TextEditingController();
  Student? _found;
  String? _error;
  bool _loading = false;

  Future<void> _search() async {
    final matricule = _ctrl.text.trim();
    if (matricule.isEmpty) return;

    setState(() { _loading = true; _found = null; _error = null; });

    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(matricule).get();
      if (!doc.exists) {
        setState(() => _error = 'Aucun étudiant avec ce matricule.');
      } else {
        final student = Student.fromFirestore(doc);

        // Vérifier restriction de filtre
        if (widget.filterNiveau != null && student.niveau != widget.filterNiveau) {
          setState(() => _error = 'Accès refusé : cet étudiant n\'est pas dans votre classe (${widget.filterNiveau}).');
          return;
        }
        if (widget.filterParcours != null && student.parcours != widget.filterParcours) {
          setState(() => _error = 'Accès refusé : cet étudiant n\'est pas dans votre parcours (${widget.filterParcours}).');
          return;
        }

        setState(() => _found = student);
      }
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _validateEntry() async {
    if (_found == null) return;
    if (_found!.qrCodeScanned) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⛔ ACCÈS DÉJÀ VALIDÉ'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final ref = FirebaseFirestore.instance.collection('students').doc(_found!.matricule);
      final statsRef = FirebaseFirestore.instance.collection('counters').doc('stats');
      final niv = _found!.niveau;
      final par = _found!.parcours;

      batch.update(ref, {'qr_code_scanned': true});
      batch.update(statsRef, {
        'total_scanned': FieldValue.increment(1),
        '${niv}_scanned': FieldValue.increment(1),
        '${par}_scanned': FieldValue.increment(1),
        '${niv}_${par}_scanned': FieldValue.increment(1),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Entrée validée : ${_found!.prenom} ${_found!.nom}'), backgroundColor: kGreen));
        setState(() => _found = _found!.copyWith(qrCodeScanned: true));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text('Saisie manuelle du matricule', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kGreen)),
          const SizedBox(height: 6),
          const Text('Solution de secours si le QR Code est illisible.', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Matricule',
                    prefixIcon: const Icon(Icons.badge, size: 26),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                width: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, size: 28),
                ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [const Icon(Icons.error_outline, color: Colors.red), const SizedBox(width: 10), Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 15)))]),
            ),
          ],

          if (_found != null) ...[
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (_found!.qrCodeScanned)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red)),
                        child: const Text('⛔ ACCÈS DÉJÀ VALIDÉ', textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 17)),
                      ),

                    // Grande photo
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _found!.qrCodeScanned ? Colors.red : kGreen, width: 3),
                        color: kGreen.withOpacity(0.08),
                      ),
                      child: ClipOval(
                        child: _found!.photo != null
                            ? Image.memory(base64Decode(_found!.photo!), fit: BoxFit.cover)
                            : const Icon(Icons.person, size: 55, color: kGreen),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text('${_found!.prenom} ${_found!.nom}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text('Matricule : ${_found!.matricule}', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [_Badge(label: _found!.niveau, color: kGreen), const SizedBox(width: 8), _Badge(label: _found!.parcours, color: kOrange)]),

                    if (!_found!.qrCodeScanned) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.how_to_reg),
                          label: const Text('Valider l\'entrée manuellement', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _loading ? null : _validateEntry,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      // Voir le profil complet
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.person),
                          label: const Text('Voir le profil complet', style: TextStyle(fontSize: 15)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _openStudentProfile(context, _found!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('Recherche par ID'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())],
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────
// EXTENSION COPYWITH
// ─────────────────────────────────────────────
extension StudentCopyWith on Student {
  Student copyWith({String? matricule, String? nom, String? prenom, String? niveau, String? parcours, bool? hasPaid, bool? qrCodeGenerated, bool? qrCodeScanned, String? photo}) {
    return Student(
      matricule: matricule ?? this.matricule,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      niveau: niveau ?? this.niveau,
      parcours: parcours ?? this.parcours,
      hasPaid: hasPaid ?? this.hasPaid,
      qrCodeGenerated: qrCodeGenerated ?? this.qrCodeGenerated,
      qrCodeScanned: qrCodeScanned ?? this.qrCodeScanned,
      photo: photo ?? this.photo,
    );
  }
}