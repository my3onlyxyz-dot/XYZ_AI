// ============================================================================
//  XYZ_AI — COMMAND CENTER · v2.2 "MATURE"
//  main.dart — arsitektur single-file · Flutter murni (tanpa plugin native)
// ============================================================================
//
//  PRINSIP OPTIMASI VERSI INI (kenapa scroll & sentuhan jadi responsif):
//
//  1. REBUILD TERKECIL MUNGKIN
//     Data live (CPU, RAM, baterai) tidak lagi memicu setState() satu halaman.
//     Semua data polling mengalir lewat ValueNotifier<DashStats> dan hanya
//     kartu statistik yang rebuild — header, banner, dan scroll view TIDAK
//     ikut dibangun ulang tiap 3 detik. Ini penyebab utama jank saat scroll
//     di versi lama.
//
//  2. POLLING SADAR-VISIBILITAS (TabGate)
//     Timer Dashboard / Refresh Rate / Band Lock / animasi Avatar hanya
//     berjalan ketika tab-nya benar-benar terlihat DAN aplikasi di foreground.
//     Pindah tab atau minimize app = semua polling & ticker berhenti otomatis.
//     Hemat baterai, bebas frame-drop dari pekerjaan latar.
//
//  3. IndexedStack SHELL
//     Keempat tab tetap hidup — posisi scroll & state tersimpan saat
//     berpindah tab, tanpa deteksi ulang / rebuild penuh setiap kali kembali.
//
//  4. I/O PARALEL & PATH TER-CACHE
//     Deteksi device dan polling dashboard memakai Future.wait (paralel),
//     bukan puluhan await berurutan. Thermal zone & path baterai dicari
//     SEKALI lalu di-cache — bukan scan 15 zona setiap 3 detik.
//
//  5. SADAR MULTI-CLUSTER (pelajaran penting perangkat ini)
//     CPU modern punya beberapa cluster (policy0 LITTLE / policy4 BIG /
//     policy7 PRIME) dengan tabel frekuensi BERBEDA. Membaca cpu0 saja
//     menyesatkan (selalu menampilkan clock cluster kecil), dan menulis satu
//     angka kHz ke semua core bisa ditolak kernel. Versi ini mendeteksi tiap
//     policy dan menerapkan frekuensi PROPORSIONAL per-cluster.
//
//  6. URUTAN TULIS FREKUENSI YANG AMAN
//     Aturan kernel: scaling_min_freq tidak boleh melewati scaling_max_freq
//     walau sesaat. Semua perintah frekuensi di sini menurunkan min lebih
//     dulu bila perlu, dan saat reset menulis MAX dulu baru MIN.
//
//  7. DT2W VIA SETTINGS, BUKAN NODE HARDWARE
//     Menulis langsung ke node touchscreen (mis. goodix gesture) terbukti
//     bisa me-reboot perangkat. Kontrol double-tap-to-wake kini memakai kunci
//     sistem `settings put system os_action_tapping_wake` yang aman.
//
//  8. UMPAN BALIK SENTUH INSTAN (widget Tap)
//     Semua elemen interaktif memberi respon visual (scale-down) begitu jari
//     menyentuh — sebelum tap selesai — sehingga UI terasa cepat bahkan di
//     dalam daftar yang sedang di-scroll. Fisik scroll memakai
//     BouncingScrollPhysics agar gerakan terasa halus dan natural.
//
//  9. LAPIS PENGAMAN BERGANDA (v2.2)
//     runZonedGuarded + FlutterError.onError menangkap error framework dan
//     async yang tak terduga — satu widget gagal tidak merobohkan app.
//     Setiap proses shell dibatasi timeout (aksi panjang seperti force-stop
//     massal diberi batas khusus s/d 60 dtk). Setiap aksi destruktif
//     (thermal off, reboot, deep clean) wajib lewat dialog konfirmasi, dan
//     setiap perintah tulis dijaga guard anti-double-tap.
//
//  10. RAM CLEANER BERTINGKAT & TERUKUR (v2.2)
//     Ringan (drop cache) / Sedang (+ am kill-all) / Menyeluruh (+ force-stop
//     seluruh app pihak ketiga & kill proses cached adj>=900). App foreground
//     otomatis dikecualikan — bila deteksinya gagal, tahap force-stop di-skip
//     total demi keselamatan. Hasil dihitung dari MemAvailable asli (bukan
//     estimasi), dan sheet terkunci (tap-luar, drag, tombol back) selama
//     pipeline berjalan supaya tidak terputus di tengah.
//
//  11. POLL BERJENJANG TAB COMMAND (v2.2)
//     Status live tiap grup setelan (governor, DNS, TCP, dll.) dibaca dengan
//     jadwal berjenjang ~120 ms antar grup — membuka tab Command tidak
//     memicu ledakan 10 proses shell sekaligus.
//
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BOOTSTRAP
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Jaring pengaman ganda: error framework (build/layout/paint) dicatat
    // tanpa mematikan app; error async tak tertangkap jatuh ke handler zona
    // di bawah. Satu widget yang gagal tidak boleh merobohkan seluruh app.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FLUTTER ERROR: ${details.exceptionAsString()}');
    };
    // Edge-to-edge modern: konten menggambar di belakang status & nav bar,
    // SafeArea yang mengatur jaraknya. Tampilan lebih premium di layar penuh.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    runApp(const XyzAiApp());
  }, (e, s) => debugPrint('UNCAUGHT: $e'));
}

// ─────────────────────────────────────────────────────────────────────────────
// STATE GLOBAL
// ─────────────────────────────────────────────────────────────────────────────

/// Tema malam/terang — didengarkan tiap tab lewat ValueListenableBuilder.
final ValueNotifier<bool> isNightNotifier = ValueNotifier<bool>(true);

/// Status akses root — diverifikasi saat splash, bisa dicek ulang manual.
final ValueNotifier<bool> isRootNotifier = ValueNotifier<bool>(false);

/// Indeks tab yang sedang terlihat. Sumber kebenaran untuk [TabGate]:
/// semua polling & animasi berat menyalakan/mematikan diri berdasar nilai ini.
final ValueNotifier<int> activeTabIndex = ValueNotifier<int>(0);

bool get _night => isNightNotifier.value;

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS — warna, gerak, fisika scroll
// ─────────────────────────────────────────────────────────────────────────────

const kCyan   = Color(0xFF00E5FF);
const kGreen  = Color(0xFF34C759);
const kYellow = Color(0xFFE6A700);
const kRed    = Color(0xFFFF4747);
const kOrange = Color(0xFFFF6B47);
const kPurple = Color(0xFFB47FFF);
const kTeal   = Color(0xFF13B5A6);
const kBlue   = Color(0xFF3D8EFF);
const kPink   = Color(0xFFFF2D78);

Color get kBg     => _night ? const Color(0xFF060612) : const Color(0xFFF0F2F8);
Color get kPanel  => _night ? const Color(0xFF0D0D20) : const Color(0xFFFFFFFF);
Color get kPanel2 => _night ? const Color(0xFF12122A) : const Color(0xFFE8EAF2);
Color get kBorder => _night ? const Color(0xFF1A1A38) : const Color(0xFFDDE0EC);
Color get kWhite  => _night ? Colors.white : const Color(0xFF080818);

/// Warna teks "muted" adaptif tema. [o] = kekuatan (0..1).
Color mut(double o) => _night
    ? Colors.white.withOpacity(o)
    : const Color(0xFF080818).withOpacity(o.clamp(0.05, 0.9));

/// Token durasi & kurva animasi — satu sumber, konsisten di seluruh app.
class Motion {
  Motion._();
  static const Duration tap   = Duration(milliseconds: 90);
  static const Duration fast  = Duration(milliseconds: 160);
  static const Duration med   = Duration(milliseconds: 220);
  static const Curve    curve = Curves.easeOutCubic;
}

/// Fisika scroll seragam: bouncing terasa lebih hidup & responsif terhadap
/// jari, dan `AlwaysScrollable` menjaga pull-to-refresh tetap bisa dipicu
/// walau konten pendek.
const ScrollPhysics kScroll =
    BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE LAYER — akses shell & filesystem, terbungkus rapi + timeout ketat
// ─────────────────────────────────────────────────────────────────────────────

/// Eksekusi perintah dengan hak root (`su -c`).
///
/// Catatan implementasi: perintah dikirim sebagai SATU argumen argv ke `su`,
/// jadi tidak perlu shell-quoting manual — aman untuk skrip multi-baris
/// sekalipun. Setiap panggilan dilindungi timeout supaya UI tidak pernah
/// menggantung menunggu proses yang macet.
class Root {
  Root._();

  /// Verifikasi akses root (uid=0). Timeout menjaga app tetap jalan bila
  /// popup izin superuser dibiarkan tanpa respons.
  static Future<bool> check() async {
    try {
      final r = await Process.run('su', ['-c', 'id']).timeout(
          const Duration(seconds: 5),
          onTimeout: () => ProcessResult(0, 1, '', 'timeout'));
      return r.stdout.toString().contains('uid=0');
    } catch (_) {
      return false;
    }
  }

  /// Jalankan [cmd] sebagai root. Mengembalikan:
  ///  * stdout (trim) bila ada,
  ///  * 'ERR: ...' bila hanya stderr,
  ///  * 'OK' bila sukses tanpa output,
  ///  * 'NO_ROOT' bila root belum aktif.
  static Future<String> exec(String cmd,
      {Duration timeout = const Duration(seconds: 8)}) async {
    if (!isRootNotifier.value) return 'NO_ROOT';
    try {
      final r = await Process.run('su', ['-c', cmd]).timeout(timeout,
          onTimeout: () => ProcessResult(0, 1, '',
              'Timeout — perintah menggantung atau device sedang berat.'));
      final out = r.stdout.toString().trim();
      final err = r.stderr.toString().trim();
      if (out.isNotEmpty) return out;
      if (err.isNotEmpty) return 'ERR: $err';
      return 'OK';
    } catch (e) {
      return 'ERROR: $e';
    }
  }
}

/// Akses baca sistem TANPA root (dengan fallback root hanya bila benar-benar
/// perlu — lihat catatan di [read]).
class Sys {
  Sys._();

  /// Baca file sysfs/procfs.
  ///
  /// Jalur cepat: baca langsung via dart:io (mikrodetik, tanpa spawn proses).
  /// Fallback `su cat` HANYA dipakai saat error-nya EACCES (ditolak izin) —
  /// file yang memang tidak ada TIDAK memicu spawn `su`, supaya polling
  /// berkala tidak menghambur-hamburkan proses root.
  static Future<String> read(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } on FileSystemException catch (e) {
      final denied = (e.osError?.errorCode ?? 0) == 13; // EACCES
      if (!denied || !isRootNotifier.value) return '';
    } catch (_) {
      return '';
    }
    try {
      final r = await Process.run('su', ['-c', 'cat "$path"']).timeout(
          const Duration(seconds: 4),
          onTimeout: () => ProcessResult(0, 1, '', 'timeout'));
      final out = r.stdout.toString().trim();
      if (out.isNotEmpty &&
          !out.contains('Permission denied') &&
          !out.contains('No such file')) {
        return out;
      }
    } catch (_) {}
    return '';
  }

  /// Baca properti Android (`getprop`) — selalu tersedia tanpa root.
  static Future<String> prop(String key) async {
    try {
      final r = await Process.run('getprop', [key]).timeout(
          const Duration(seconds: 4),
          onTimeout: () => ProcessResult(0, 1, '', 'timeout'));
      return r.stdout.toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Jalankan perintah shell BIASA (non-root) — dipakai leaf read-only &
  /// Tools saat root tidak tersedia. Semantik keluaran sama dengan
  /// [Root.exec] supaya pemanggil cukup satu jalur penanganan.
  static Future<String> sh(String cmd,
      {Duration timeout = const Duration(seconds: 6)}) async {
    try {
      final r = await Process.run('sh', ['-c', cmd]).timeout(timeout,
          onTimeout: () => ProcessResult(0, 1, '', 'timeout'));
      final out = r.stdout.toString().trim();
      final err = r.stderr.toString().trim();
      if (out.isNotEmpty) return out;
      if (err.isNotEmpty) return 'ERR: $err';
      return 'OK';
    } catch (e) {
      return 'ERROR: $e';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB GATE — inti dari "hemat daya & bebas jank"
// ─────────────────────────────────────────────────────────────────────────────

/// Menyalakan/mematikan pekerjaan berkala berdasarkan dua syarat sekaligus:
/// (1) tab pemiliknya sedang terlihat, dan (2) aplikasi berada di foreground.
///
/// Dipakai oleh: poller Dashboard, poller Refresh Rate, poller Band Lock,
/// dan ticker animasi Avatar. Berkat gate ini, IndexedStack bisa menjaga
/// state semua tab TANPA membayar biaya timer/animasi tab yang tak terlihat.
class TabGate with WidgetsBindingObserver {
  TabGate({required this.tab, required this.onChanged});

  /// Indeks tab pemilik (0=Dashboard, 1=Command, 2=Tools, 3=Tentang).
  final int tab;

  /// Dipanggil dengan `true` saat gate terbuka (mulai bekerja) dan `false`
  /// saat tertutup (hentikan semua pekerjaan).
  final void Function(bool active) onChanged;

  bool _resumed = true;
  bool _last = false;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    activeTabIndex.addListener(_eval);
    _eval();
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    activeTabIndex.removeListener(_eval);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _eval();
  }

  void _eval() {
    final active = _resumed && activeTabIndex.value == tab;
    if (active != _last) {
      _last = active;
      onChanged(active);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAP — umpan balik sentuh instan untuk SEMUA elemen interaktif
// ─────────────────────────────────────────────────────────────────────────────

/// Pengganti GestureDetector polos: begitu jari menyentuh, child langsung
/// mengecil halus (scale 0.97) — bahkan sebelum gesture tap diputuskan.
/// Efek psikologisnya besar: aplikasi terasa "mengikuti jari" walau sedang
/// berada di dalam daftar yang di-scroll. `HitTestBehavior.opaque` menjamin
/// seluruh area kartu bisa ditekan, bukan hanya teks/ikonnya.
class Tap extends StatefulWidget {
  const Tap({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.pressedScale = .97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double pressedScale;

  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => _set(true) : null,
      onTapCancel: on ? () => _set(false) : null,
      onTapUp: on ? (_) => _set(false) : null,
      onTap: on ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: Motion.tap,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER UI GLOBAL — snackbar, sheet output, dialog konfirmasi
// ─────────────────────────────────────────────────────────────────────────────

/// Snackbar seragam. Selalu menutup snackbar sebelumnya dulu supaya aksi
/// beruntun tidak menumpuk antrean (penyebab UI terasa "telat").
void showSnack(BuildContext context, String msg, {Color? bg}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: bg ?? kPanel2,
      duration: const Duration(milliseconds: 1600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}

/// Bottom-sheet hasil perintah (monospace, bisa diseleksi/salin).
void showOutputSheet(
  BuildContext context, {
  required String title,
  required String body,
  IconData icon = Icons.terminal_rounded,
  Color color = kCyan,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: kPanel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetCtx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .5,
      maxChildSize: .92,
      builder: (_, sc) => Column(children: [
        Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: mut(.2), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
          child: Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: kWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w700))),
            Tap(
                onTap: () => Navigator.pop(sheetCtx),
                child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, color: mut(.4), size: 20))),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: sc,
            physics: kScroll,
            padding: const EdgeInsets.all(20),
            child: SelectableText(body,
                style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.6)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: Tap(
              onTap: () => Navigator.pop(sheetCtx),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: color.withOpacity(.14),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('Tutup',
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    ),
  );
}

/// Dialog konfirmasi untuk perintah berdampak besar (reboot, matikan
/// throttle, dsb). Mengembalikan `true` hanya bila pengguna menekan Lanjut.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  Color accent = kRed,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(.6),
    builder: (dctx) => Dialog(
      backgroundColor: kPanel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: accent.withOpacity(.35))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: accent.withOpacity(.12), shape: BoxShape.circle),
              child:
                  Icon(Icons.warning_amber_rounded, color: accent, size: 26)),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: kWhite, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: mut(.45), fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: Tap(
                onTap: () => Navigator.pop(dctx, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: mut(.06),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('Batal',
                      style: TextStyle(
                          color: mut(.6), fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Tap(
                onTap: () => Navigator.pop(dctx, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: accent.withOpacity(.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withOpacity(.4))),
                  child: Text('Lanjut',
                      style: TextStyle(
                          color: accent, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
  return ok ?? false;
}

// ─────────────────────────────────────────────────────────────────────────────
// DEVICE INFO — deteksi kemampuan perangkat, paralel & multi-cluster
// ─────────────────────────────────────────────────────────────────────────────

/// Satu cluster CPU (satu entri /sys/devices/system/cpu/cpufreq/policyN).
/// Tiap cluster punya tabel frekuensi sendiri — inilah alasan semua fitur
/// frekuensi di app ini bekerja per-policy, bukan per-cpu0.
class CpuPolicy {
  CpuPolicy({required this.index});

  final int index;
  int hwMinKhz = 0;
  int hwMaxKhz = 0;

  /// LITTLE / BIG / PRIME (diberi berdasarkan urutan hwMax antar cluster).
  String label = 'CL';

  String get path => '/sys/devices/system/cpu/cpufreq/policy$index';
  String get curFreqPath => '$path/scaling_cur_freq';
}

class DeviceInfo {
  DeviceInfo._();
  static final DeviceInfo i = DeviceInfo._();

  /// Sinyal "hasil deteksi berubah" — UI (Command, About, banner) cukup
  /// mendengarkan notifier ini untuk auto-rebuild, tanpa setState tersebar.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String model = '---';
  String brand = '---';
  String platform = '---';
  String androidVer = '---';
  String cpuArch = '---';
  int cpuCores = 0;

  /// Nama tampilan setelah validasi silang brand vs chipset asli.
  String displayName = '---';
  bool spoofSuspected = false;

  final List<CpuPolicy> policies = [];
  List<String> governors = [];
  String? thermalPath;      // di-cache: dashboard tak perlu scan 15 zona/3dtk
  String? batteryTempPath;  // di-cache dengan alasan yang sama

  bool loaded = false;
  bool _busy = false;

  /// Ringkasan cluster untuk banner, mis. "LITTLE 2.0 · BIG 3.0 · PRIME 3.1 GHz".
  String get clusterSummary {
    if (policies.isEmpty) return '';
    final parts = policies
        .map((p) => '${p.label} ${(p.hwMaxKhz / 1000000).toStringAsFixed(1)}')
        .join(' · ');
    return '$parts GHz';
  }

  /// Aman dipanggil berulang (splash, buka shell, pull-to-refresh). Guard
  /// [_busy] mencegah dua deteksi berjalan bersamaan; timeout total menjamin
  /// proses tidak pernah menggantung tanpa batas.
  Future<void> detect() async {
    if (_busy) return;
    _busy = true;
    try {
      await _run().timeout(const Duration(seconds: 15), onTimeout: () {
        debugPrint('DeviceInfo.detect timeout — memakai data parsial');
      });
      loaded = true;
      revision.value++;
    } finally {
      _busy = false;
    }
  }

  Future<void> _run() async {
    // ── Properti dasar: 5 getprop sekaligus (paralel) ──
    final p = await Future.wait([
      Sys.prop('ro.product.model'),
      Sys.prop('ro.product.manufacturer'),
      Sys.prop('ro.board.platform'),
      Sys.prop('ro.build.version.release'),
      Sys.prop('ro.product.cpu.abi'),
    ]);
    model      = p[0].isEmpty ? '---' : p[0];
    brand      = p[1].isEmpty ? '---' : p[1];
    platform   = p[2].isEmpty ? '---' : p[2];
    androidVer = p[3].isEmpty ? '---' : p[3];
    cpuArch    = p[4].isEmpty ? '---' : p[4];

    // ── Validasi silang brand vs chipset asli ──
    // Properti brand/model gampang dipalsukan modul spoofing; chipset
    // (ro.board.platform) jauh lebih sulit karena dibaca driver kernel.
    // Kalau brand mengaku vendor yang mustahil untuk chipset ini, tampilkan
    // nama jujur berbasis chipset + tandai kecurigaan spoof.
    final pl = platform.toLowerCase();
    final bl = brand.toLowerCase();
    final looksMediatek = pl.contains('mt') || pl.startsWith('k6');
    final looksQualcomm = pl.contains('sm') ||
        pl.contains('msm') ||
        pl.contains('kona') ||
        pl.contains('lahaina');
    final claimsApple =
        bl.contains('apple') || model.toLowerCase().contains('iphone');
    spoofSuspected = claimsApple && (looksMediatek || looksQualcomm);

    if (spoofSuspected) {
      displayName = 'Android (chipset $platform)';
    } else if (model == '---' && brand == '---') {
      displayName = 'Perangkat tidak dikenal';
    } else {
      displayName = '$brand $model';
    }

    // ── Jumlah core: langsung dari runtime, tanpa loop 16 kali baca sysfs ──
    cpuCores = Platform.numberOfProcessors;
    if (cpuCores <= 0) cpuCores = 1;

    // ── Cluster CPU (policy*) ──
    policies.clear();
    final found = <int>[];
    try {
      final dir = Directory('/sys/devices/system/cpu/cpufreq');
      for (final e in dir.listSync(followLinks: false)) {
        final name = e.path.split('/').last;
        if (name.startsWith('policy')) {
          final n = int.tryParse(name.substring(6));
          if (n != null) found.add(n);
        }
      }
    } catch (_) {
      // fallback: probe policy0..9 secara paralel
      final probes = await Future.wait(List.generate(
          10,
          (n) => Sys.read(
              '/sys/devices/system/cpu/cpufreq/policy$n/scaling_cur_freq')));
      for (var n = 0; n < probes.length; n++) {
        if (probes[n].isNotEmpty) found.add(n);
      }
    }
    found.sort();

    if (found.isNotEmpty) {
      // Baca batas hardware tiap policy — semuanya paralel.
      final reads = await Future.wait(found.expand((n) sync* {
        yield Sys.read('/sys/devices/system/cpu/cpufreq/policy$n/cpuinfo_min_freq');
        yield Sys.read('/sys/devices/system/cpu/cpufreq/policy$n/cpuinfo_max_freq');
      }).toList());
      for (var k = 0; k < found.length; k++) {
        final pol = CpuPolicy(index: found[k])
          ..hwMinKhz = int.tryParse(reads[k * 2]) ?? 0
          ..hwMaxKhz = int.tryParse(reads[k * 2 + 1]) ?? 0;
        policies.add(pol);
      }
      // Label berdasarkan urutan clock maksimum antar cluster.
      final byMax = [...policies]
        ..sort((a, b) => a.hwMaxKhz.compareTo(b.hwMaxKhz));
      for (var k = 0; k < byMax.length; k++) {
        byMax[k].label = switch (policies.length) {
          1 => 'CPU',
          2 => const ['LITTLE', 'BIG'][k],
          3 => const ['LITTLE', 'BIG', 'PRIME'][k],
          _ => 'CL${k + 1}',
        };
      }
    }

    // ── Governor dari cluster pertama (umumnya identik antar cluster) ──
    final govPath = policies.isNotEmpty
        ? '${policies.first.path}/scaling_available_governors'
        : '/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors';
    governors = (await Sys.read(govPath))
        .split(RegExp(r'\s+'))
        .where((g) => g.isNotEmpty)
        .toList();

    // ── Thermal zone CPU: scan 20 zona SEKALI (paralel), simpan path valid ──
    final temps = await Future.wait(List.generate(
        20, (z) => Sys.read('/sys/class/thermal/thermal_zone$z/temp')));
    thermalPath = null;
    for (var z = 0; z < temps.length; z++) {
      final n = int.tryParse(temps[z]) ?? 0;
      if (n > 20000 && n < 100000) {
        thermalPath = '/sys/class/thermal/thermal_zone$z/temp';
        break;
      }
    }

    // ── Path suhu baterai: kandidat dibaca paralel, ambil yang pertama ada ──
    const candidates = [
      '/sys/class/power_supply/battery/temp',
      '/sys/class/power_supply/mtk-gauge/temp',
      '/sys/class/power_supply/bms/temp',
    ];
    final bt = await Future.wait(candidates.map(Sys.read));
    batteryTempPath = null;
    for (var k = 0; k < candidates.length; k++) {
      if (bt[k].isNotEmpty) {
        batteryTempPath = candidates[k];
        break;
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────────────────────

class XyzAiApp extends StatelessWidget {
  const XyzAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isNightNotifier,
      builder: (_, night, __) => MaterialApp(
        title: 'Xyz_AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: kBg,
          colorScheme: ColorScheme.fromSeed(
              seedColor: kCyan,
              brightness: night ? Brightness.dark : Brightness.light),
          splashFactory: NoSplash.splashFactory, // umpan balik via widget Tap
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPLASH
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _main, _orbit;
  late final Animation<double> _scale, _fade, _progress;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..forward();
    _orbit =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..repeat();
    _scale = CurvedAnimation(
        parent: _main,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut));
    _fade = CurvedAnimation(
        parent: _main, curve: const Interval(0.4, 1.0, curve: Curves.easeOut));
    _progress = CurvedAnimation(parent: _main, curve: Curves.easeInOut);
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _status = 'Checking root...');
    final hasRoot = await Root.check();
    isRootNotifier.value = hasRoot;
    if (mounted) {
      setState(() => _status = hasRoot ? 'Root detected ✓' : 'Non-root mode');
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _status = 'Detecting device...');
    await DeviceInfo.i.detect();
    if (mounted) setState(() => _status = DeviceInfo.i.displayName);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (_, a, __) =>
            FadeTransition(opacity: a, child: const RootShell()),
      ),
    );
  }

  @override
  void dispose() {
    _main.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060612),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: Listenable.merge([_main, _orbit]),
            builder: (_, __) => Stack(alignment: Alignment.center, children: [
              Transform.rotate(
                angle: _orbit.value * 2 * math.pi,
                child: SizedBox(
                    width: 160,
                    height: 160,
                    child: CustomPaint(painter: _OrbitPainter(_orbit.value))),
              ),
              Container(
                width: 118 + 6 * (_orbit.value % 1),
                height: 118 + 6 * (_orbit.value % 1),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: kCyan.withOpacity(0.10 * _scale.value.clamp(0, 1)),
                        width: 1)),
              ),
              ScaleTransition(scale: _scale, child: const _AppIcon(size: 92)),
            ]),
          ),
          const SizedBox(height: 36),
          FadeTransition(
            opacity: _fade,
            child: Column(children: [
              const Text('XYZ_AI',
                  style: TextStyle(
                      color: kCyan,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8)),
              const SizedBox(height: 4),
              Text('COMMAND CENTER',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 5)),
              const SizedBox(height: 28),
              SizedBox(
                width: 160,
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (_, __) => Column(children: [
                    LinearProgressIndicator(
                        value: _progress.value,
                        minHeight: 2,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        valueColor: const AlwaysStoppedAnimation(kCyan),
                        borderRadius: BorderRadius.circular(2)),
                    const SizedBox(height: 10),
                    Text(_status,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP ICON — chip heksagon (dipakai splash & header halaman)
// ─────────────────────────────────────────────────────────────────────────────

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
              center: Alignment(-0.3, -0.3),
              colors: [Color(0xFF1C1C44), Color(0xFF080816)]),
          boxShadow: [
            BoxShadow(
                color: kCyan.withOpacity(.35), blurRadius: 26, spreadRadius: 1),
            BoxShadow(
                color: kPurple.withOpacity(.18),
                blurRadius: 46,
                spreadRadius: -6),
          ],
        ),
        child: CustomPaint(painter: _IconPainter(), size: Size(size, size)),
      );
}

class _IconPainter extends CustomPainter {
  Offset _hex(double cx, double cy, double r, int i) {
    final a = (i * 60 - 90) * math.pi / 180;
    return Offset(cx + r * math.cos(a), cy + r * math.sin(a));
  }

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final rOuter = s.width * 0.34, rInner = s.width * 0.16;

    final legPaint = Paint()
      ..color = kCyan.withOpacity(.5)
      ..strokeWidth = s.width * 0.022
      ..strokeCap = StrokeCap.round;
    final padPaint = Paint()..color = kCyan.withOpacity(.7);
    for (int i = 0; i < 6; i++) {
      final inner = _hex(cx, cy, rOuter, i);
      final outer = _hex(cx, cy, rOuter + s.width * 0.1, i);
      canvas.drawLine(inner, outer, legPaint);
      canvas.drawCircle(outer, s.width * 0.026, padPaint);
    }

    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final p = _hex(cx, cy, rOuter, i);
      i == 0 ? hexPath.moveTo(p.dx, p.dy) : hexPath.lineTo(p.dx, p.dy);
    }
    hexPath.close();
    canvas.drawPath(
        hexPath,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kCyan.withOpacity(.18), kPurple.withOpacity(.08)])
              .createShader(
                  Rect.fromCircle(center: Offset(cx, cy), radius: rOuter)));
    canvas.drawPath(
        hexPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width * 0.028
          ..strokeJoin = StrokeJoin.round
          ..color = kCyan
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));

    final corePath = Path();
    for (int i = 0; i < 6; i++) {
      final p = _hex(cx, cy, rInner, i);
      i == 0 ? corePath.moveTo(p.dx, p.dy) : corePath.lineTo(p.dx, p.dy);
    }
    corePath.close();
    canvas.drawPath(
        corePath,
        Paint()
          ..shader = RadialGradient(colors: [kCyan, const Color(0xFF0080A0)])
              .createShader(
                  Rect.fromCircle(center: Offset(cx, cy), radius: rInner))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));

    canvas.drawCircle(
        Offset(cx, cy),
        s.width * 0.045,
        Paint()
          ..color = Colors.white
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(
        Offset(cx, cy), s.width * 0.028, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.v);
  final double v;

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2, cy = s.height / 2, r = s.width / 2 - 4;
    for (int i = 0; i < 12; i++) {
      final a = (i / 12) * 2 * math.pi;
      canvas.drawCircle(
          Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
          i % 3 == 0 ? 2.2 : 1.2,
          Paint()..color = kCyan.withOpacity(i % 3 == 0 ? .45 : .18));
    }
    final ma = v * 2 * math.pi;
    canvas.drawCircle(
        Offset(cx + r * math.cos(ma), cy + r * math.sin(ma)),
        4,
        Paint()
          ..color = kCyan
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.v != v;
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT SHELL — IndexedStack + bottom navigation
// ─────────────────────────────────────────────────────────────────────────────

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _idx = 0;

  // IndexedStack: keempat tab hidup terus → posisi scroll & state awet saat
  // berpindah tab. Biaya latar (timer/animasi) nol berkat TabGate di tiap
  // komponen yang punya pekerjaan berkala.
  static const _pages = <Widget>[
    DashboardTab(),
    CommandTab(),
    ToolsTab(),
    AboutTab(),
  ];

  @override
  void initState() {
    super.initState();
    activeTabIndex.value = 0;
    // Deteksi ulang setiap kali shell terbentuk (cold start / kembali dari
    // proses mati) — app selalu mengenal device tempat ia berjalan sekarang.
    DeviceInfo.i.detect();
  }

  void _select(int i) {
    if (_idx == i) return;
    HapticFeedback.selectionClick();
    setState(() => _idx = i);
    activeTabIndex.value = i; // beri tahu semua TabGate
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isNightNotifier,
      builder: (_, night, __) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          statusBarIconBrightness: night ? Brightness.light : Brightness.dark,
          systemNavigationBarIconBrightness:
              night ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: kBg,
          body: SafeArea(
              bottom: false,
              child: IndexedStack(index: _idx, children: _pages)),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: kPanel,
              border: Border(top: BorderSide(color: kBorder, width: .5)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(.3),
                    blurRadius: 20,
                    offset: const Offset(0, -4))
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _navItem(0, Icons.dashboard_rounded, 'Dashboard', kCyan),
                    _navItem(1, Icons.account_tree_rounded, 'Command', kPurple),
                    _navItem(2, Icons.construction_rounded, 'Tools', kOrange),
                    _navItem(3, Icons.person_rounded, 'Tentang', kGreen),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label, Color accent) {
    final on = _idx == i;
    return Tap(
      onTap: () => _select(i),
      pressedScale: .93,
      child: AnimatedContainer(
        duration: Motion.med,
        curve: Motion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: on ? accent.withOpacity(.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: on ? accent.withOpacity(.3) : Colors.transparent)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 21, color: on ? accent : mut(.3)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  color: on ? accent : mut(.3),
                  letterSpacing: .3)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  DASHBOARD
//  Pola inti optimasi: seluruh data polling dibungkus satu objek
//  immutable [DashStats] yang dipublikasikan lewat ValueNotifier.
//  Hanya kartu statistik yang rebuild tiap 3 detik — header, banner,
//  dan scroll view TIDAK ikut rebuild, sehingga scroll tetap 60fps
//  walau timer sedang jalan.
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  RAM CLEANER
//  Pembersihan bertingkat lewat bottom sheet — dipakai kartu RAM di
//  Dashboard dan Aksi Cepat di Command:
//    Ringan     : drop page cache (aman, instan).
//    Sedang     : + `am kill-all` — ActivityManager menutup SEMUA proses
//                 background yang aman ditutup (whitelist system dijaga
//                 Android sendiri).
//    Menyeluruh : + force-stop seluruh app pihak ketiga (kecuali app
//                 foreground = app ini) + kill -9 proses cached
//                 (oom_score_adj >= 900). Butuh konfirmasi: musik/alarm/
//                 notifikasi app lain ikut berhenti.
//  Hasil diukur nyata: MemAvailable sebelum vs sesudah.
// ═══════════════════════════════════════════════════════════════════

enum RamCleanLevel { ringan, sedang, menyeluruh }

class _RamStep {
  const _RamStep(this.label, this.cmd,
      {this.timeout = const Duration(seconds: 15)});
  final String label, cmd;

  /// Batas waktu per-tahap. Force-stop puluhan paket bisa makan 30+ detik —
  /// timeout default Root.exec (8 dtk) akan memotong pipeline di tengah.
  final Duration timeout;
}

const String _ramDropCmd = 'sync; echo 3 > /proc/sys/vm/drop_caches; echo OK';

const String _ramKillAllCmd = 'am kill-all; echo OK';

/// kill -9 semua proses CACHED (adj >= 900). App foreground (termasuk app
/// ini) ber-adj 0 dan proses sistem persistent ber-adj negatif — keduanya
/// otomatis lolos dari filter.
const String _ramKillCachedCmd = '''
n=0
for d in /proc/[0-9]*; do
  adj=\$(cat "\$d/oom_score_adj" 2>/dev/null) || continue
  case "\$adj" in ''|-*) continue;; esac
  if [ "\$adj" -ge 900 ]; then
    kill -9 "\${d#/proc/}" 2>/dev/null && n=\$((n+1))
  fi
done
echo "OK: \$n proses cached dimatikan"
''';

/// Force-stop semua paket pihak ketiga KECUALI app foreground (app ini).
/// Kalau deteksi foreground gagal, tahap ini di-SKIP total — lebih baik
/// kurang bersih daripada app ini ikut tertutup.
const String _ramForceStopCmd = '''
fg=\$(dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -oE '[A-Za-z0-9._]+/' | tail -1 | tr -d /)
[ -n "\$fg" ] || { echo "SKIP: app foreground tidak terdeteksi"; exit 0; }
n=0
for p in \$(pm list packages -3 2>/dev/null | cut -d: -f2); do
  [ "\$p" = "\$fg" ] && continue
  am force-stop "\$p" 2>/dev/null && n=\$((n+1))
done
echo "OK: \$n aplikasi ditutup paksa"
''';

Future<void> showRamCleanSheet(BuildContext context,
    {Future<void> Function()? onDone}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: kPanel,
    isScrollControlled: true,
    // Sheet TIDAK bisa ditutup dengan tap-luar/drag: proses pembersihan
    // tidak boleh terputus di tengah. Tombol ✕ & tombol Selesai tetap ada
    // di fase pilih & fase hasil.
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _RamCleanSheet(onDone: onDone),
  );
}

class _RamCleanSheet extends StatefulWidget {
  const _RamCleanSheet({this.onDone});
  final Future<void> Function()? onDone;

  @override
  State<_RamCleanSheet> createState() => _RamCleanSheetState();
}

class _RamCleanSheetState extends State<_RamCleanSheet> {
  int _phase = 0; // 0 = pilih level · 1 = berjalan · 2 = hasil
  List<_RamStep> _steps = const [];
  List<bool> _ok = const [];
  int _stepIdx = -1;
  int _beforeMb = 0, _freedMb = 0, _freeNowMb = 0;
  bool _measured = false; // true bila meminfo terbaca sebelum & sesudah
  Color _accent = kGreen;

  static Future<int> _availMb() async {
    final txt = await Sys.read('/proc/meminfo');
    for (final l in txt.split('\n')) {
      if (l.startsWith('MemAvailable')) {
        final p = l.split(RegExp(r'\s+'));
        if (p.length >= 2) return (int.tryParse(p[1]) ?? 0) ~/ 1024;
      }
    }
    return 0;
  }

  Future<void> _run(RamCleanLevel lv) async {
    if (_phase != 0) return; // double-tap tidak boleh memicu dua pipeline
    if (!isRootNotifier.value) {
      showSnack(context, '⚠ Butuh akses root untuk membersihkan RAM');
      return;
    }
    if (lv == RamCleanLevel.menyeluruh) {
      final ok = await confirmAction(context,
          title: 'Bersih Menyeluruh',
          message:
              'Semua aplikasi pihak ketiga akan DITUTUP PAKSA. Musik, alarm, '
              'dan notifikasi dari app lain bisa berhenti sampai app itu '
              'dibuka lagi. Lanjutkan?',
          accent: kRed);
      if (!ok || !mounted) return;
    }
    final steps = switch (lv) {
      RamCleanLevel.ringan => const [
          _RamStep('Membuang page cache', _ramDropCmd),
        ],
      RamCleanLevel.sedang => const [
          _RamStep('Menutup proses background', _ramKillAllCmd,
              timeout: Duration(seconds: 20)),
          _RamStep('Membuang page cache', _ramDropCmd),
        ],
      RamCleanLevel.menyeluruh => const [
          _RamStep('Menutup aplikasi pihak ketiga', _ramForceStopCmd,
              timeout: Duration(seconds: 60)),
          _RamStep('Mematikan proses cached', _ramKillCachedCmd,
              timeout: Duration(seconds: 25)),
          _RamStep('Menutup proses background', _ramKillAllCmd,
              timeout: Duration(seconds: 20)),
          _RamStep('Membuang page cache', _ramDropCmd),
        ],
    };
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = 1;
      _steps = steps;
      _ok = List.filled(steps.length, false);
      _stepIdx = 0;
      _accent = switch (lv) {
        RamCleanLevel.ringan => kGreen,
        RamCleanLevel.sedang => kYellow,
        RamCleanLevel.menyeluruh => kRed,
      };
    });
    // Apa pun yang terjadi di dalam, sheet TIDAK BOLEH terkunci selamanya
    // di fase "berjalan" — selalu berakhir di fase hasil.
    try {
      _beforeMb = await _availMb();
      for (int i = 0; i < steps.length; i++) {
        if (!mounted) return;
        setState(() => _stepIdx = i);
        final out = await Root.exec(steps[i].cmd, timeout: steps[i].timeout);
        if (!mounted) return;
        setState(() => _ok[i] = !out.startsWith('ERR') && out != 'NO_ROOT');
      }
      // Beri waktu kernel menyelesaikan reclaim sebelum diukur ulang.
      await Future.delayed(const Duration(milliseconds: 900));
      final after = await _availMb();
      if (!mounted) return;
      setState(() {
        _phase = 2;
        _measured = _beforeMb > 0 && after > 0;
        _freeNowMb = after;
        _freedMb = after - _beforeMb;
        _stepIdx = _steps.length;
      });
      HapticFeedback.mediumImpact();
      await widget.onDone?.call();
    } catch (e) {
      debugPrint('RamClean error: $e');
      if (mounted) {
        setState(() {
          _phase = 2;
          _measured = false;
          _stepIdx = _steps.length;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tombol back sistem juga dikunci selama proses berjalan.
    return WillPopScope(
      onWillPop: () async => _phase != 1,
      child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: mut(.2), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 0, 14),
            child: Row(children: [
              Icon(Icons.memory_rounded,
                  color: _phase == 0 ? kPurple : _accent, size: 19),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(
                      _phase == 0
                          ? 'Bersihkan RAM'
                          : _phase == 1
                              ? 'Membersihkan…'
                              : 'Selesai',
                      style: TextStyle(
                          color: kWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.w800))),
              if (_phase != 1)
                Tap(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded,
                            color: mut(.4), size: 20))),
            ]),
          ),
          if (_phase == 0) ..._buildPicker(),
          if (_phase == 1) _buildProgress(),
          if (_phase == 2) _buildResult(),
        ]),
      ),
      ),
    );
  }

  // ── fase 0: pilih tingkat ──
  List<Widget> _buildPicker() => [
        _levelRow(
          RamCleanLevel.ringan,
          Icons.cleaning_services_rounded,
          kGreen,
          'Ringan',
          'Buang page cache — aman & instan',
        ),
        const SizedBox(height: 8),
        _levelRow(
          RamCleanLevel.sedang,
          Icons.delete_sweep_rounded,
          kYellow,
          'Sedang',
          'Tutup proses background + buang cache',
        ),
        const SizedBox(height: 8),
        _levelRow(
          RamCleanLevel.menyeluruh,
          Icons.local_fire_department_rounded,
          kRed,
          'Menyeluruh',
          'Tutup paksa SEMUA app lain sampai bersih — '
          'musik/alarm/notifikasi app lain bisa berhenti',
          danger: true,
        ),
        const SizedBox(height: 6),
      ];

  Widget _levelRow(RamCleanLevel lv, IconData icon, Color c, String title,
          String desc,
          {bool danger = false}) =>
      Tap(
        onTap: () => _run(lv),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: mut(.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: danger
                      ? kRed.withOpacity(.3)
                      : kBorder.withOpacity(.6))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: c.withOpacity(.12),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: c, size: 18)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Text(title,
                        style: TextStyle(
                            color: kWhite,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    if (danger) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.warning_amber_rounded,
                          color: kRed.withOpacity(.8), size: 13),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(
                          color: mut(.38), fontSize: 10.5, height: 1.35)),
                ])),
            Icon(Icons.chevron_right_rounded, color: mut(.25), size: 20),
          ]),
        ),
      );

  // ── fase 1: checklist berjalan ──
  Widget _buildProgress() => Column(children: [
        for (int i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              SizedBox(
                width: 18,
                height: 18,
                child: i < _stepIdx || (_stepIdx == i && _ok.length > i && _ok[i])
                    ? Icon(
                        _ok[i]
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        color: _ok[i] ? kGreen : kRed,
                        size: 18)
                    : i == _stepIdx
                        ? CircularProgressIndicator(
                            strokeWidth: 2, color: _accent)
                        : Icon(Icons.circle_outlined,
                            color: mut(.18), size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(_steps[i].label,
                      style: TextStyle(
                          color: i <= _stepIdx ? kWhite : mut(.35),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        const SizedBox(height: 4),
        Text('Jangan tutup sheet ini…',
            style: TextStyle(color: mut(.3), fontSize: 10.5)),
        const SizedBox(height: 8),
      ]);

  // ── fase 2: hasil ──
  Widget _buildResult() {
    final gained = _measured && _freedMb > 0;
    final headline = gained
        ? '+$_freedMb MB'
        : _measured
            ? 'RAM sudah lega'
            : 'Selesai';
    final sub = gained
        ? 'RAM dibebaskan · Free sekarang: $_freeNowMb MB'
        : _measured
            ? 'Tidak banyak yang bisa dibebaskan · Free: $_freeNowMb MB'
            : 'Pembersihan dijalankan — hasil tidak terukur';
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
            color: (gained ? kGreen : kYellow).withOpacity(.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: (gained ? kGreen : kYellow).withOpacity(.25))),
        child: Column(children: [
          Text(headline,
              style: TextStyle(
                  color: gained ? kGreen : kYellow,
                  fontSize: gained ? 28 : 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(color: mut(.4), fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 10),
      for (int i = 0; i < _steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(_ok[i] ? Icons.check_rounded : Icons.close_rounded,
                color: _ok[i] ? kGreen : kRed, size: 14),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_steps[i].label,
                    style: TextStyle(color: mut(.45), fontSize: 11))),
          ]),
        ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: Tap(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
                color: kGreen.withOpacity(.14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: kGreen.withOpacity(.35))),
            child: Center(
                child: Text('Selesai',
                    style: TextStyle(
                        color: kGreen,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800))),
          ),
        ),
      ),
    ]);
  }
}

class DashStats {
  const DashStats({
    required this.ready,
    required this.freqText,
    required this.gov,
    required this.tempText,
    required this.tempC,
    required this.batText,
    required this.batPct,
    required this.batStatus,
    required this.batTempText,
    required this.uptime,
    required this.memTotalMb,
    required this.memUsedMb,
    required this.clusterLabels,
    required this.clusterCurKhz,
    required this.clusterMaxKhz,
    required this.freqHist,
    required this.tempHist,
    required this.memHist,
    required this.batHist,
  });

  final bool ready;
  final String freqText, gov, tempText, batText, batStatus, batTempText, uptime;
  final double? tempC;
  final int? batPct;
  final int memTotalMb, memUsedMb;

  /// Data per-cluster (LITTLE/BIG/PRIME) — index sejajar antar list.
  final List<String> clusterLabels;
  final List<int> clusterCurKhz, clusterMaxKhz;

  final List<double> freqHist, tempHist, memHist, batHist;

  /// Kondisi awal sebelum sampel pertama masuk (skeleton tampil).
  static DashStats initial() => const DashStats(
      ready: false, freqText: '---', gov: '---', tempText: '---',
      tempC: null, batText: '---', batPct: null, batStatus: '---',
      batTempText: '---', uptime: '---',
      memTotalMb: 0, memUsedMb: 0,
      clusterLabels: [], clusterCurKhz: [], clusterMaxKhz: [],
      freqHist: [], tempHist: [], memHist: [], batHist: []);

  /// Dipakai setelah 2x polling gagal total: tampilkan '---' alih-alih
  /// membiarkan spinner skeleton berputar selamanya.
  static DashStats offline(List<double> f, List<double> t, List<double> m,
          List<double> b) =>
      DashStats(
          ready: true, freqText: '---', gov: '---', tempText: '---',
          tempC: null, batText: '---', batPct: null, batStatus: '---',
          batTempText: '---', uptime: '---',
          memTotalMb: 0, memUsedMb: 0,
          clusterLabels: const [], clusterCurKhz: const [],
          clusterMaxKhz: const [],
          freqHist: f, tempHist: t, memHist: m, batHist: b);
}

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final ValueNotifier<DashStats> _stats =
      ValueNotifier<DashStats>(DashStats.initial());

  late final TabGate _gate;
  Timer? _timer;
  bool _ticking = false; // cegah tick menumpuk bila I/O lambat
  int _fail = 0;

  // Riwayat untuk sparkline. Dibatasi 24 sampel (≈72 detik) supaya memori
  // konstan & repaint murah.
  static const int _histLen = 24;
  final List<double> _freqHist = [];
  final List<double> _tempHist = [];
  final List<double> _memHist = [];
  final List<double> _batHist = [];

  void _push(List<double> l, double v) {
    l.add(v);
    if (l.length > _histLen) l.removeAt(0);
  }

  @override
  void initState() {
    super.initState();
    // Polling HANYA saat tab Dashboard aktif DAN app di foreground.
    // Pindah tab / app ke background → timer berhenti → hemat baterai,
    // tidak ada proses baca sysfs sia-sia di belakang layar.
    _gate = TabGate(
      tab: 0,
      onChanged: (on) {
        if (on) {
          DeviceInfo.i.detect(); // selalu re-deteksi saat dashboard tampil
          _start();
        } else {
          _stop();
        }
      },
    )..attach();
  }

  void _start() {
    _timer?.cancel();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    _gate.detach();
    _stats.dispose();
    super.dispose();
  }

  int _kb(String meminfo, String key) {
    for (final l in meminfo.split('\n')) {
      if (l.startsWith(key)) {
        final parts = l.split(RegExp(r'\s+'));
        if (parts.length >= 2) return int.tryParse(parts[1]) ?? 0;
      }
    }
    return 0;
  }

  /// Satu siklus sampling. SEMUA pembacaan dijalankan paralel lewat
  /// Future.wait — total latensi = pembacaan terlambat, bukan penjumlahan
  /// semuanya (dulu: belasan await berurutan + scan 15 zona thermal).
  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final di = DeviceInfo.i;

      // Frekuensi dibaca PER-POLICY (LITTLE/BIG/PRIME). Membaca cpu0 saja
      // menyesatkan — cluster LITTLE hampir selalu menampilkan angka rendah
      // yang sama walau cluster PRIME sedang bekerja penuh.
      final freqPaths = di.policies.isNotEmpty
          ? di.policies.map((p) => p.curFreqPath).toList()
          : ['/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq'];
      final govPath = di.policies.isNotEmpty
          ? '${di.policies.first.path}/scaling_governor'
          : '/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor';
      final nFreq = freqPaths.length;

      final r = await Future.wait<String>([
        ...freqPaths.map(Sys.read),                                   // 0..n-1
        Sys.read(govPath),                                            // n
        di.thermalPath != null                                        // n+1
            ? Sys.read(di.thermalPath!)
            : Future<String>.value(''),
        Sys.read('/proc/meminfo'),                                    // n+2
        Sys.read('/proc/uptime'),                                     // n+3
        Sys.read('/sys/class/power_supply/battery/capacity'),         // n+4
        di.batteryTempPath != null                                    // n+5
            ? Sys.read(di.batteryTempPath!)
            : Future<String>.value(''),
        Sys.read('/sys/class/power_supply/battery/status'),           // n+6
      ]);

      // ── Per-cluster: label + frekuensi live + batas hardware ──
      final cLabels = <String>[];
      final cCur = <int>[];
      final cMax = <int>[];
      for (int i = 0; i < di.policies.length && i < nFreq; i++) {
        cLabels.add(di.policies[i].label);
        cMax.add(di.policies[i].hwMaxKhz);
        cCur.add(int.tryParse(r[i]) ?? 0);
      }

      // ── CPU: pakai frekuensi TERTINGGI antar cluster sebagai angka utama ──
      int khzMax = 0;
      for (int i = 0; i < nFreq; i++) {
        final v = int.tryParse(r[i]) ?? 0;
        if (v > khzMax) khzMax = v;
      }
      final freqText = khzMax <= 0
          ? '---'
          : khzMax >= 1000000
              ? '${(khzMax / 1000000).toStringAsFixed(2)} GHz'
              : '${(khzMax / 1000).round()} MHz';

      final gov = r[nFreq].isEmpty ? '---' : r[nFreq];

      // ── Thermal: path SUDAH di-cache oleh DeviceInfo.detect() ──
      double? tempC;
      final tRaw = int.tryParse(r[nFreq + 1]) ?? 0;
      if (tRaw > 25000 && tRaw < 120000) tempC = tRaw / 1000.0;
      final tempText =
          tempC == null ? '---' : '${tempC.toStringAsFixed(1)}°C';

      // ── Memori ──
      final mem = r[nFreq + 2];
      final mtMb = _kb(mem, 'MemTotal') ~/ 1024;
      final maMb = _kb(mem, 'MemAvailable') ~/ 1024;
      final usedMb = (mtMb - maMb).clamp(0, 1 << 30);

      // ── Uptime (dengan hari) ──
      final sec = double.tryParse(r[nFreq + 3].split(' ').first) ?? 0;
      final d = sec ~/ 86400, h = (sec % 86400) ~/ 3600, m = (sec % 3600) ~/ 60;
      final uptime = sec <= 0
          ? '---'
          : d > 0
              ? '${d}d ${h}h ${m}m'
              : '${h}h ${m}m';

      // ── Baterai ──
      final batPct = int.tryParse(r[nFreq + 4]);
      final batText = batPct == null ? '---' : '$batPct%';
      final btRaw = int.tryParse(r[nFreq + 5]) ?? 0;
      final batTempText = btRaw == 0
          ? '---'
          : btRaw.abs() > 100
              ? '${(btRaw / 10).toStringAsFixed(1)}°C'
              : '$btRaw°C';
      final batStatus = r[nFreq + 6].trim();

      final allDead = khzMax <= 0 && mtMb <= 0 && sec <= 0;
      if (allDead) {
        _fail++;
        if (_fail >= 2) {
          _stats.value =
              DashStats.offline(_freqHist, _tempHist, _memHist, _batHist);
        }
        return;
      }
      _fail = 0;

      // Sampel tidak valid TIDAK dicatat — grafik bebas lonjakan palsu ke 0.
      if (khzMax > 0) _push(_freqHist, khzMax / 1000000);
      if (tempC != null) _push(_tempHist, tempC);
      if (mtMb > 0) _push(_memHist, usedMb / mtMb * 100);
      if (batPct != null) _push(_batHist, batPct.toDouble());

      // Publikasi objek baru → HANYA ValueListenableBuilder kartu yang
      // rebuild. Tidak ada setState halaman penuh.
      _stats.value = DashStats(
        ready: true,
        freqText: freqText,
        gov: gov,
        tempText: tempText,
        tempC: tempC,
        batText: batText,
        batPct: batPct,
        batStatus: batStatus.isEmpty ? '---' : batStatus,
        batTempText: batTempText,
        uptime: uptime,
        memTotalMb: mtMb,
        memUsedMb: usedMb,
        clusterLabels: cLabels,
        clusterCurKhz: cCur,
        clusterMaxKhz: cMax,
        freqHist: _freqHist,
        tempHist: _tempHist,
        memHist: _memHist,
        batHist: _batHist,
      );
    } catch (e) {
      debugPrint('Dashboard tick error: $e');
    } finally {
      _ticking = false;
    }
  }

  /// Aksi cepat dari kartu RAM — buka sheet pembersih bertingkat, lalu
  /// refresh statistik begitu selesai supaya bar RAM langsung turun.
  Future<void> _clearCache() =>
      showRamCleanSheet(context, onDone: () async => _tick());

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isNightNotifier,
      builder: (_, __, ___) => RefreshIndicator(
        onRefresh: () async {
          await DeviceInfo.i.detect();
          await _tick();
        },
        color: kCyan,
        backgroundColor: kPanel,
        child: SingleChildScrollView(
          physics: kScroll,
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pageHeader('Dashboard', 'Live System Monitor', kCyan),
            const SizedBox(height: 14),
            const _RootBanner(),
            const SizedBox(height: 18),
            _sectionLabel('PROCESSOR', kCyan),
            const SizedBox(height: 10),
            // RepaintBoundary per seksi: repaint sparkline/angka terkurung
            // di area kartu, tidak merambat ke seluruh layar.
            RepaintBoundary(
              child: ValueListenableBuilder<DashStats>(
                valueListenable: _stats,
                builder: (_, s, __) {
                  if (!s.ready) {
                    return const Column(children: [
                      _Skeleton(198),
                      SizedBox(height: 10),
                      _Skeleton(108),
                    ]);
                  }
                  final tempColor = s.tempC == null
                      ? kBlue
                      : s.tempC! > 55
                          ? kRed
                          : s.tempC! > 45
                              ? kYellow
                              : kGreen;
                  return Column(children: [
                    // Kartu hero: frekuensi tertinggi + sparkline + bar live
                    // per-cluster (LITTLE/BIG/PRIME), governor & suhu sebagai
                    // pill — sekali lihat, semua kondisi CPU terbaca.
                    _CpuHeroCard(s),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _StatTile('CPU Temp', s.tempText,
                              Icons.thermostat_rounded, tempColor,
                              history: s.tempHist)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _StatTile('Uptime', s.uptime,
                              Icons.timer_rounded, kTeal)),
                    ]),
                  ]);
                },
              ),
            ),
            const SizedBox(height: 18),
            _sectionLabel('MEMORY', kPurple),
            const SizedBox(height: 10),
            RepaintBoundary(
              child: ValueListenableBuilder<DashStats>(
                valueListenable: _stats,
                builder: (_, s, __) => s.ready
                    ? _MemCard(
                        totalMb: s.memTotalMb,
                        usedMb: s.memUsedMb,
                        onClean: _clearCache)
                    : const _Skeleton(110),
              ),
            ),
            const SizedBox(height: 18),
            _sectionLabel('BATTERY', kGreen),
            const SizedBox(height: 10),
            RepaintBoundary(
              child: ValueListenableBuilder<DashStats>(
                valueListenable: _stats,
                builder: (_, s, __) =>
                    s.ready ? _BatteryCard(s) : const _Skeleton(108),
              ),
            ),
            const SizedBox(height: 18),
            _sectionLabel('KENYAMANAN LAYAR', kOrange),
            const SizedBox(height: 10),
            const _EyeCareQuickCard(),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

/// Banner status root. Judul memakai chipset hasil deteksi (dinamis, bukan
/// hardcode 'MT6895'), dan badge ROOT/SAFE bisa DITEKAN untuk memeriksa
/// ulang akses root tanpa restart app.
class _RootBanner extends StatelessWidget {
  const _RootBanner();

  Future<void> _recheck(BuildContext context) async {
    showSnack(context, 'Memeriksa ulang akses root…');
    final ok = await Root.check();
    isRootNotifier.value = ok;
    if (!context.mounted) return;
    showSnack(context, ok ? 'Root terdeteksi ✓' : 'Root tidak tersedia',
        bg: ok ? const Color(0xFF0E3B2E) : null);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isRootNotifier,
      builder: (_, root, __) => ValueListenableBuilder<int>(
        valueListenable: DeviceInfo.revision,
        builder: (ctx, rev, child) {
          final plat = DeviceInfo.i.platform;
          final chip = plat == '---' ? 'System' : plat.toUpperCase();
          final c = root ? kGreen : kYellow;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: c.withOpacity(.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.withOpacity(.25))),
            child: Row(children: [
              Icon(root ? Icons.verified_rounded : Icons.info_rounded,
                  color: c, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(root ? 'Root Aktif — $chip' : 'Mode Non-Root',
                        style: TextStyle(
                            color: kWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(
                        root
                            ? 'Akses penuh · Semua fitur tersedia'
                            : 'Mode aman — ketuk badge untuk cek ulang',
                        style: TextStyle(color: mut(.4), fontSize: 11)),
                  ])),
              Tap(
                onTap: () => _recheck(context),
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: c.withOpacity(.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(root ? 'ROOT' : 'SAFE',
                        style: TextStyle(
                            color: c,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1))),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// Kartu statistik. Tinggi tetap (108) agar layout stabil antar-update,
/// nilai dibungkus FittedBox supaya teks panjang ('schedutil') menyusut
/// rapi alih-alih overflow.
class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value, this.icon, this.accent,
      {this.history});

  final String label, value;
  final IconData icon;
  final Color accent;
  final List<double>? history;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(.18))),
      child: Stack(children: [
        // Sparkline realtime di lapisan belakang bawah kartu.
        if (history != null && history!.length >= 2)
          Positioned.fill(
            child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                    height: 26,
                    child: CustomPaint(
                        painter: _SparklinePainter(history!, accent),
                        size: Size.infinite))),
          ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: accent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: accent, size: 16)),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    color: accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace')),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: mut(.38),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .8)),
        ]),
      ]),
    );
  }
}

class _MemCard extends StatelessWidget {
  const _MemCard({required this.totalMb, required this.usedMb, this.onClean});
  final int totalMb, usedMb;
  final VoidCallback? onClean;

  @override
  Widget build(BuildContext context) {
    final t = totalMb <= 0 ? 1 : totalMb;
    final pct = (usedMb / t).clamp(0.0, 1.0);
    final freeMb = (t - usedMb).clamp(0, 1 << 30);
    final barColor = pct > .85 ? kRed : pct > .65 ? kYellow : kPurple;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.memory_rounded, color: kPurple, size: 18),
          const SizedBox(width: 8),
          Text('RAM Usage',
              style: TextStyle(
                  color: kWhite, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(totalMb <= 0 ? '---' : '$usedMb / $totalMb MB',
              style: TextStyle(
                  color: kPurple,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
                tween: Tween(end: pct),
                duration: Motion.med,
                curve: Motion.curve,
                builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 8,
                    backgroundColor: mut(.06),
                    valueColor: AlwaysStoppedAnimation(barColor)))),
        const SizedBox(height: 8),
        Row(children: [
          Text('Free: ${totalMb <= 0 ? '---' : '$freeMb MB'}',
              style: TextStyle(color: mut(.4), fontSize: 11)),
          const SizedBox(width: 8),
          Text('· ${(pct * 100).toStringAsFixed(0)}% used',
              style: TextStyle(color: mut(.4), fontSize: 11)),
          const Spacer(),
          // Aksi cepat: drop caches langsung dari dashboard — tanpa
          // pindah ke tab Command.
          if (onClean != null)
            Tap(
              onTap: onClean!,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: kGreen.withOpacity(.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: kGreen.withOpacity(.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cleaning_services_rounded,
                      color: kGreen, size: 12),
                  const SizedBox(width: 5),
                  Text('Bersihkan',
                      style: TextStyle(
                          color: kGreen,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// CPU HERO — satu kartu untuk seluruh kondisi prosesor: frekuensi
// tertinggi (angka besar + sparkline), governor & suhu sebagai pill,
// dan bar frekuensi LIVE per-cluster. Data cluster sudah dibaca
// per-policy oleh _tick — sebelumnya hanya nilai max yang ditampilkan.
// ─────────────────────────────────────────────────────────────────────
class _CpuHeroCard extends StatelessWidget {
  const _CpuHeroCard(this.s);
  final DashStats s;

  Color _clusterColor(String label) => switch (label) {
        'LITTLE' => kGreen,
        'BIG' => kOrange,
        'PRIME' => kRed,
        _ => kCyan,
      };

  @override
  Widget build(BuildContext context) {
    final tempColor = s.tempC == null
        ? kBlue
        : s.tempC! > 55
            ? kRed
            : s.tempC! > 45
                ? kYellow
                : kGreen;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kCyan.withOpacity(.18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kCyan.withOpacity(.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.speed_rounded, color: kCyan, size: 16)),
          const SizedBox(width: 9),
          Text('CPU',
              style: TextStyle(
                  color: kWhite, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          _pill(Icons.tune_rounded, s.gov, kPurple),
          const SizedBox(width: 6),
          _pill(Icons.thermostat_rounded, s.tempText, tempColor),
        ]),
        const SizedBox(height: 8),
        // Angka utama + sparkline di lapisan belakang.
        SizedBox(
          height: 46,
          child: Stack(children: [
            if (s.freqHist.length >= 2)
              Positioned.fill(
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                        height: 30,
                        child: CustomPaint(
                            painter: _SparklinePainter(s.freqHist, kCyan),
                            size: Size.infinite))),
              ),
            Align(
                alignment: Alignment.bottomLeft,
                child: Text(s.freqText,
                    style: TextStyle(
                        color: kCyan,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace'))),
          ]),
        ),
        Text('FREKUENSI TERTINGGI',
            style: TextStyle(
                color: mut(.35),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        if (s.clusterLabels.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (int i = 0; i < s.clusterLabels.length; i++)
            Padding(
              padding: EdgeInsets.only(
                  bottom: i == s.clusterLabels.length - 1 ? 0 : 8),
              child: _clusterRow(i),
            ),
        ],
      ]),
    );
  }

  Widget _pill(IconData icon, String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: c.withOpacity(.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withOpacity(.25))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 11),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  color: c,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ]),
      );

  Widget _clusterRow(int i) {
    final label = s.clusterLabels[i];
    final cur = s.clusterCurKhz[i];
    final max = s.clusterMaxKhz[i];
    final pct = max <= 0 ? 0.0 : (cur / max).clamp(0.0, 1.0);
    final c = _clusterColor(label);
    final curTxt = cur <= 0 ? '--' : (cur / 1000000).toStringAsFixed(2);
    final maxTxt = max <= 0 ? '--' : (max / 1000000).toStringAsFixed(1);
    return Row(children: [
      SizedBox(
          width: 50,
          child: Text(label,
              style: TextStyle(
                  color: mut(.45),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  fontFamily: 'monospace'))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
              tween: Tween(end: pct),
              duration: Motion.med,
              curve: Motion.curve,
              builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: mut(.06),
                  valueColor: AlwaysStoppedAnimation(c.withOpacity(.85)))),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
          width: 84,
          child: Text('$curTxt / $maxTxt GHz',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: c.withOpacity(.9),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace'))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────
// BATTERY — kapasitas + sparkline, suhu, dan status pengisian daya
// (dibaca dari power_supply/battery/status) dalam SATU kartu.
// ─────────────────────────────────────────────────────────────────────
class _BatteryCard extends StatelessWidget {
  const _BatteryCard(this.s);
  final DashStats s;

  @override
  Widget build(BuildContext context) {
    final charging = s.batStatus == 'Charging';
    final full = s.batStatus == 'Full';
    final low = s.batPct != null && s.batPct! <= 20 && !charging;
    final c = low ? kRed : kGreen;
    final statusTxt = charging
        ? 'Mengisi daya'
        : full
            ? 'Penuh'
            : s.batStatus == 'Discharging'
                ? 'Memakai baterai'
                : s.batStatus == 'Not charging'
                    ? 'Tidak mengisi'
                    : s.batStatus;
    return Container(
      height: 108,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.withOpacity(.18))),
      child: Row(children: [
        // Kiri: kapasitas besar + sparkline.
        Expanded(
          child: Stack(children: [
            if (s.batHist.length >= 2)
              Positioned.fill(
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                        height: 24,
                        child: CustomPaint(
                            painter: _SparklinePainter(s.batHist, c),
                            size: Size.infinite))),
              ),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: c.withOpacity(.12),
                          borderRadius: BorderRadius.circular(9)),
                      child: Icon(
                          charging
                              ? Icons.bolt_rounded
                              : Icons.battery_full_rounded,
                          color: c,
                          size: 15)),
                  const Spacer(),
                  Text(s.batText,
                      style: TextStyle(
                          color: c,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace')),
                  Text('KAPASITAS',
                      style: TextStyle(
                          color: mut(.35),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                ]),
          ]),
        ),
        Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: kBorder.withOpacity(.7)),
        // Kanan: suhu + status pengisian.
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _mini(Icons.device_thermostat_rounded, kOrange, 'Suhu',
                    s.batTempText),
                const SizedBox(height: 12),
                _mini(
                    charging
                        ? Icons.bolt_rounded
                        : Icons.power_settings_new_rounded,
                    charging ? kYellow : c,
                    'Status',
                    statusTxt),
              ]),
        ),
      ]),
    );
  }

  Widget _mini(IconData icon, Color c, String label, String value) =>
      Row(children: [
        Icon(icon, color: c, size: 14),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: mut(.35),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: kWhite,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace')),
              ]),
        ),
      ]);
}

/// Kartu pintasan Dashboard: dua sakelar paling sering dipakai —
/// Mode Mata Sehat (night_display_activated) & Layar Redup
/// (reduce_bright_colors_activated). Status dibaca sekali saat kartu
/// tampil, lalu tiap toggle langsung menulis via Root.exec + optimistic
/// UI (switch berubah duluan, dikoreksi lagi bila perintah gagal).
class _EyeCareQuickCard extends StatefulWidget {
  const _EyeCareQuickCard();
  @override
  State<_EyeCareQuickCard> createState() => _EyeCareQuickCardState();
}

class _EyeCareQuickCardState extends State<_EyeCareQuickCard> {
  bool? _eyeCare; // null = belum terbaca
  bool? _dim;
  bool _busyEye = false;
  bool _busyDim = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!isRootNotifier.value) return;
    final r = await Future.wait([
      Root.exec(
          'settings get secure night_display_activated 2>/dev/null'),
      Root.exec(
          'settings get secure reduce_bright_colors_activated 2>/dev/null'),
    ]);
    if (!mounted) return;
    setState(() {
      _eyeCare = r[0].trim() == '1';
      _dim = r[1].trim() == '1';
    });
  }

  Future<void> _toggleEye(bool v) async {
    if (_busyEye) return;
    setState(() { _eyeCare = v; _busyEye = true; }); // optimistic
    final r = await Root.exec(
        'settings put secure night_display_activated ${v ? 1 : 0}; echo OK');
    if (!mounted) return;
    setState(() => _busyEye = false);
    if (r == 'NO_ROOT' || r.startsWith('ERR') || r.startsWith('ERROR')) {
      setState(() => _eyeCare = !v); // rollback
      showSnack(context, 'Gagal ubah Mode Mata Sehat — cek akses root.');
    }
  }

  Future<void> _toggleDim(bool v) async {
    if (_busyDim) return;
    setState(() { _dim = v; _busyDim = true; });
    final r = await Root.exec(
        'settings put secure reduce_bright_colors_activated ${v ? 1 : 0}; echo OK');
    if (!mounted) return;
    setState(() => _busyDim = false);
    if (r == 'NO_ROOT' || r.startsWith('ERR') || r.startsWith('ERROR')) {
      setState(() => _dim = !v);
      showSnack(context, 'Gagal ubah Layar Redup — cek akses root.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isRootNotifier,
      builder: (_, hasRoot, __) {
        if (hasRoot && _eyeCare == null && _dim == null) {
          // root baru aktif & belum sempat load — coba sekali lagi
          WidgetsBinding.instance.addPostFrameCallback((_) => _load());
        }
        return Container(
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          child: Column(children: [
            _eyeCareRow(
              icon: Icons.remove_red_eye_rounded,
              color: kOrange,
              title: 'Mode Mata Sehat',
              sub: 'Layar kekuningan — nyaman malam hari',
              value: _eyeCare,
              busy: _busyEye,
              hasRoot: hasRoot,
              onChanged: _toggleEye,
            ),
            Divider(height: 1, color: kBorder, indent: 62, endIndent: 16),
            _eyeCareRow(
              icon: Icons.brightness_low_rounded,
              color: kBlue,
              title: 'Layar Redup',
              sub: 'Lebih redup dari kecerahan minimum',
              value: _dim,
              busy: _busyDim,
              hasRoot: hasRoot,
              onChanged: _toggleDim,
            ),
          ]),
        );
      },
    );
  }

  Widget _eyeCareRow({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required bool? value,
    required bool busy,
    required bool hasRoot,
    required ValueChanged<bool> onChanged,
  }) {
    final on = value ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: on ? color.withOpacity(.16) : mut(.05),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: on ? color : mut(.4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: kWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                !hasRoot ? 'Butuh akses root' : sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: !hasRoot ? kRed.withOpacity(.7) : mut(.35),
                    fontSize: 10.5),
              ),
            ],
          ),
        ),
        if (busy)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: color.withOpacity(.7)),
          )
        else
          Switch(
            value: on,
            onChanged: hasRoot ? onChanged : null,
            activeColor: color,
          ),
      ]),
    );
  }
}

/// Placeholder loading dengan tinggi eksplisit — layout tidak "loncat"
/// saat data pertama masuk.
class _Skeleton extends StatelessWidget {
  const _Skeleton(this.height);
  final double height;
  @override
  Widget build(BuildContext context) => Container(
      height: height,
      decoration: BoxDecoration(
          color: kPanel, borderRadius: BorderRadius.circular(18)),
      child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: kCyan.withOpacity(.5)))));
}

// ─────────────────────────────────────────────────────────────────────
// SPARKLINE — grafik mini realtime kartu statistik. Auto-scale min-max
// agar pergerakan kecil tetap terlihat; titik paling kanan = "sekarang".
// ─────────────────────────────────────────────────────────────────────
class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);
    final dx = size.width / (data.length - 1);

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final y = size.height - ((data[i] - minV) / range * size.height);
      points.add(Offset(i * dx, y.clamp(0, size.height)));
    }

    final areaPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      areaPath.lineTo(p.dx, p.dy);
    }
    areaPath.lineTo(points.last.dx, size.height);
    areaPath.close();
    canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withOpacity(.22), color.withOpacity(0)])
              .createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        linePath,
        Paint()
          ..color = color.withOpacity(.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    canvas.drawCircle(points.last, 2.6, Paint()..color = color);
    canvas.drawCircle(points.last, 4.2, Paint()..color = color.withOpacity(.25));
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data.length != data.length ||
      (data.isNotEmpty && old.data.isNotEmpty && old.data.last != data.last);
}

// ═══════════════════════════════════════════════════════════════════
//  COMMAND TAB
//  Stateless + ValueListenableBuilder(DeviceInfo.revision): begitu
//  deteksi device selesai/berubah, daftar grup ikut ter-update tanpa
//  setState manual. Grup ber-polling (RefreshRate, Band) adalah widget
//  stateful terpisah — setState mereka TIDAK menyentuh sisa halaman.
// ═══════════════════════════════════════════════════════════════════

String _stripErr(String s) =>
    s.replaceFirst(RegExp(r'^ERR(OR)?:\s*'), '').trim();

class CommandTab extends StatelessWidget {
  const CommandTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isNightNotifier,
      builder: (_, __, ___) => ValueListenableBuilder<int>(
        valueListenable: DeviceInfo.revision,
        builder: (ctx, rev, child) {
          // Dihitung SEKALI per build & disimpan lokal.
          final govGroup = _buildGovGroup();
          final freqGroup = _buildFreqGroup();
          return SingleChildScrollView(
            physics: kScroll,
            padding: const EdgeInsets.all(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pageHeader('Command', 'Device Control Hub', kPurple),
                  const SizedBox(height: 10),
                  const _RootStrip(),
                  const SizedBox(height: 14),
                  const _DeviceBanner(),
                  const SizedBox(height: 18),

                  // ── PERFORMA ────────────────────────────────────────
                  _sectionLabel('PERFORMA', kCyan),
                  const SizedBox(height: 10),
                  if (govGroup != null) govGroup,
                  if (freqGroup != null) freqGroup,
                  const _RefreshRateGroup(),
                  _thermalGroup(),

                  const SizedBox(height: 8),
                  // ── JARINGAN ────────────────────────────────────────
                  _sectionLabel('JARINGAN', kBlue),
                  const SizedBox(height: 10),
                  _bandLockGroup(),
                  _dnsGroup(),
                  _tcpGroup(),

                  const SizedBox(height: 8),
                  // ── MEMORI & STORAGE ────────────────────────────────
                  _sectionLabel('MEMORI & STORAGE', kPurple),
                  const SizedBox(height: 10),
                  _swappinessGroup(),
                  _ioGroup(),

                  const SizedBox(height: 8),
                  // ── LAYAR ───────────────────────────────────────────
                  _sectionLabel('LAYAR & GESTURE', kPink),
                  const SizedBox(height: 10),
                  _dt2wGroup(),
                  _nightLightGroup(),
                  _nightLightTempGroup(),
                  _extraDimGroup(),

                  const SizedBox(height: 8),
                  // ── AKSI CEPAT ──────────────────────────────────────
                  _sectionLabel('AKSI CEPAT', kOrange),
                  const SizedBox(height: 10),
                  const _QuickActions(),

                  const SizedBox(height: 24),
                ]),
          );
        },
      ),
    );
  }

  // ── CPU Governor: tulis ke policy* (satu tulis per cluster). Chip yang
  //    sedang aktif dibaca langsung dari sysfs — tanpa buka dialog. ──
  _ChoiceGroup? _buildGovGroup() {
    final govs = DeviceInfo.i.governors;
    if (govs.isEmpty) return null;
    const sub = {
      'performance': 'Gaming — max',
      'powersave': 'Hemat penuh',
      'schedutil': 'Harian ✦',
      'ondemand': 'Naik cepat',
      'conservative': 'Naik pelan',
      'interactive': 'Responsif UI',
    };
    return _ChoiceGroup(
      icon: Icons.developer_board_rounded,
      label: 'CPU Governor',
      accent: kCyan,
      note: 'Berlaku untuk semua cluster sekaligus.',
      readCmd:
          'cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor 2>/dev/null | head -1',
      choices: [
        for (final g in govs)
          _Choice(g, g,
              sub: sub[g],
              cmd:
                  'ok=0; for f in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do echo $g > "\$f" 2>/dev/null && ok=1; done; [ \$ok -eq 1 ] && echo OK || echo "ERR: gagal menulis governor"'),
      ],
    );
  }

  // ── CPU Frekuensi: tier PERSENTASE per-cluster. Tiap policy dihitung
  //    dari cpuinfo_max-nya sendiri, jadi LITTLE/BIG/PRIME turun
  //    proporsional. Tier aktif dideteksi dari rasio scaling_max /
  //    cpuinfo_max policy pertama. Chip "Full" sekaligus reset penuh
  //    (mengembalikan max & min hardware). ──
  _ChoiceGroup? _buildFreqGroup() {
    final d = DeviceInfo.i;
    if (d.policies.isEmpty) return null;
    return _ChoiceGroup(
      icon: Icons.speed_rounded,
      label: 'CPU Frekuensi',
      accent: kOrange,
      note: d.clusterSummary.isEmpty
          ? 'Kunci frekuensi per-cluster'
          : d.clusterSummary,
      readCmd: _readTierCmd,
      parse: (raw) {
        final p = int.tryParse(raw.trim());
        if (p == null) return '';
        if (p >= 92) return '100';
        if (p >= 70) return '80';
        if (p >= 50) return '60';
        return '40';
      },
      choices: [
        const _Choice('100', 'Full', sub: '100% — default', cmd: _resetFreqCmd),
        _Choice('80', 'Tinggi', sub: '±80% tiap cluster', cmd: _tierCmd(80)),
        _Choice('60', 'Seimbang', sub: '±60% — adem', cmd: _tierCmd(60)),
        _Choice('40', 'Hemat', sub: '±40% — baterai', cmd: _tierCmd(40)),
      ],
    );
  }

  // ── Thermal throttle sebagai saklar dua-pilihan dengan status live. ──
  _ChoiceGroup _thermalGroup() => _ChoiceGroup(
        icon: Icons.thermostat_rounded,
        label: 'Thermal Throttle',
        accent: kRed,
        note: 'Mati = performa tanpa rem suhu — pantau Dashboard!',
        readCmd: 'cat /sys/class/thermal/thermal_zone0/mode 2>/dev/null',
        parse: (r) => r.contains('disabled')
            ? 'off'
            : r.contains('enabled')
                ? 'on'
                : '',
        choices: const [
          _Choice('on', 'Aktif', sub: 'Aman — default',
              cmd:
                  'ok=0; for m in /sys/class/thermal/thermal_zone*/mode; do echo enabled > "\$m" 2>/dev/null && ok=1; done; [ \$ok -eq 1 ] && echo OK || echo "ERR: node mode tidak tersedia"'),
          _Choice('off', 'Mati', sub: 'Tanpa throttle', danger: true,
              cmd:
                  'ok=0; for m in /sys/class/thermal/thermal_zone*/mode; do echo disabled > "\$m" 2>/dev/null && ok=1; done; [ \$ok -eq 1 ] && echo OK || echo "ERR: node mode tidak tersedia"'),
        ],
      );

  // ── Network / Band Lock — chip menyorot MODE tersimpan (settings),
  //    sedangkan tipe jaringan aktual tampil live di header ("Sinyal: …").
  //    Kode mode dari RILConstants: 26 = NR/LTE/GSM/WCDMA · 11 = LTE only
  //    · 9 = LTE/GSM/WCDMA. Ditulis juga ke key per-slot untuk dual-SIM. ──
  static String _netCmd(int mode) =>
      'settings put global preferred_network_mode $mode; '
      'settings put global preferred_network_mode0 $mode; '
      'settings put global preferred_network_mode1 $mode; echo OK';

  _ChoiceGroup _bandLockGroup() => _ChoiceGroup(
        icon: Icons.signal_cellular_alt_rounded,
        label: 'Network / Band Lock',
        accent: kBlue,
        note: 'Dukungan tergantung modem. Kalau tidak berubah, coba mode lain.',
        pollEvery: 6,
        readCmd:
            'm=\$(settings get global preferred_network_mode0 2>/dev/null); { [ -n "\$m" ] && [ "\$m" != "null" ]; } || m=\$(settings get global preferred_network_mode 2>/dev/null); echo "\$m"',
        parse: (r) => r == '26'
            ? '5g'
            : r == '11'
                ? '4g'
                : r == '9'
                    ? '4g3g'
                    : '',
        statusCmd:
            'dumpsys telephony.registry | grep -oE "mDataNetworkType=[A-Za-z0-9_]+" | head -1',
        statusParse: (r) {
          final v = r.replaceFirst('mDataNetworkType=', '').trim();
          return (v.isEmpty || v == 'OK') ? '' : 'Sinyal: $v';
        },
        choices: [
          _Choice('5g', '5G Preferred',
              sub: 'NR/LTE — jangkauan penuh', cmd: _netCmd(26)),
          _Choice('4g', '4G Only', sub: 'LTE saja — stabil', cmd: _netCmd(11)),
          _Choice('4g3g', '4G/3G',
              sub: 'LTE + fallback WCDMA', cmd: _netCmd(9)),
        ],
      );

  // ── DNS Pribadi (DoT) — provider aktif dideteksi dari specifier. ──
  static String _dnsCmd(String host) =>
      'settings put global private_dns_mode hostname; settings put global private_dns_specifier $host; echo OK';

  _ChoiceGroup _dnsGroup() => _ChoiceGroup(
        icon: Icons.dns_rounded,
        label: 'DNS Pribadi',
        accent: kTeal,
        readCmd:
            'm=\$(settings get global private_dns_mode 2>/dev/null); s=\$(settings get global private_dns_specifier 2>/dev/null); echo "\$m|\$s"',
        parse: (r) {
          final i = r.indexOf('|');
          final m = (i < 0 ? r : r.substring(0, i)).trim();
          final s = i < 0 ? '' : r.substring(i + 1).trim();
          if (m != 'hostname') return 'off';
          if (s.contains('adguard')) return 'adguard';
          if (s.contains('one.one')) return 'cf';
          if (s.contains('quad9')) return 'q9';
          if (s.contains('dns.google')) return 'g';
          return '';
        },
        choices: [
          _Choice('adguard', 'AdGuard',
              sub: 'Blokir iklan', cmd: _dnsCmd('dns.adguard-dns.com')),
          _Choice('cf', 'Cloudflare',
              sub: '1.1.1.1', cmd: _dnsCmd('one.one.one.one')),
          _Choice('q9', 'Quad9',
              sub: 'Anti-malware', cmd: _dnsCmd('dns.quad9.net')),
          _Choice('g', 'Google', sub: '8.8.8.8', cmd: _dnsCmd('dns.google')),
          const _Choice('off', 'Off',
              sub: 'Otomatis',
              cmd: 'settings put global private_dns_mode off; echo OK'),
        ],
      );

  // ── TCP congestion control — nilai aktif dibaca dari procfs. ──
  _ChoiceGroup _tcpGroup() => _ChoiceGroup(
        icon: Icons.network_check_rounded,
        label: 'TCP Congestion',
        accent: kGreen,
        readCmd: 'cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null',
        parse: (r) => (r == 'bbr' || r == 'cubic') ? r : '',
        choices: const [
          _Choice('bbr', 'BBR',
              sub: 'Algoritma Google',
              cmd:
                  'echo bbr > /proc/sys/net/ipv4/tcp_congestion_control && echo OK || echo "ERR: bbr tidak tersedia di kernel"'),
          _Choice('cubic', 'Cubic',
              sub: 'Default Linux',
              cmd:
                  'echo cubic > /proc/sys/net/ipv4/tcp_congestion_control && echo OK || echo "ERR: gagal menulis"'),
        ],
      );

  // ── Swappiness — nilai aktif dibaca dari /proc. ──
  _ChoiceGroup _swappinessGroup() => _ChoiceGroup(
        icon: Icons.swap_horiz_rounded,
        label: 'Swappiness',
        accent: kPurple,
        readCmd: 'cat /proc/sys/vm/swappiness 2>/dev/null',
        parse: (r) => (r == '10' || r == '60') ? r : '',
        choices: const [
          _Choice('10', '10', sub: 'Prioritaskan RAM',
              cmd: 'echo 10 > /proc/sys/vm/swappiness && echo OK'),
          _Choice('60', '60', sub: 'Seimbang — default',
              cmd: 'echo 60 > /proc/sys/vm/swappiness && echo OK'),
        ],
      );

  // ── I/O Scheduler — scheduler aktif = nilai dalam kurung [x].
  //    Kernel modern memakai nama blk-mq (none / mq-deadline), jadi tiap
  //    chip mencoba nama legacy dulu lalu fallback ke nama mq. ──
  _ChoiceGroup _ioGroup() => _ChoiceGroup(
        icon: Icons.storage_rounded,
        label: 'I/O Scheduler',
        accent: kTeal,
        readCmd: 'cat /sys/block/*/queue/scheduler 2>/dev/null | head -1',
        parse: (r) {
          final m = RegExp(r'\[([a-z\-]+)\]').firstMatch(r);
          final v = m?.group(1) ?? '';
          if (v == 'noop' || v == 'none') return 'noop';
          if (v == 'deadline' || v == 'mq-deadline') return 'deadline';
          return '';
        },
        choices: const [
          _Choice('noop', 'Noop / None',
              sub: 'Overhead minimal',
              cmd:
                  'ok=0; for d in /sys/block/*/queue/scheduler; do { echo noop > "\$d" 2>/dev/null || echo none > "\$d" 2>/dev/null; } && ok=1; done; [ \$ok -eq 1 ] && echo OK || echo "ERR: scheduler tidak tersedia"'),
          _Choice('deadline', 'Deadline',
              sub: 'Responsif I/O',
              cmd:
                  'ok=0; for d in /sys/block/*/queue/scheduler; do { echo deadline > "\$d" 2>/dev/null || echo mq-deadline > "\$d" 2>/dev/null; } && ok=1; done; [ \$ok -eq 1 ] && echo OK || echo "ERR: scheduler tidak tersedia"'),
        ],
      );

  // ── DT2W via settings system os_action_tapping_wake (kunci
  //    Transsion/Infinix). Node hardware goodix SENGAJA tidak dipakai:
  //    menulis ke node itu pernah menyebabkan device reboot. ──
  _ChoiceGroup _dt2wGroup() => _ChoiceGroup(
        icon: Icons.touch_app_rounded,
        label: 'Double Tap to Wake',
        accent: kPink,
        note: 'Aman via settings — bukan node hardware.',
        readCmd: 'settings get system os_action_tapping_wake 2>/dev/null',
        parse: (r) => r == '1'
            ? 'on'
            : (r == '0' || r == 'null' || r.isEmpty || r == 'OK')
                ? 'off'
                : '',
        choices: const [
          _Choice('on', 'Aktif', sub: 'Ketuk 2x → layar nyala',
              cmd: 'settings put system os_action_tapping_wake 1; echo OK'),
          _Choice('off', 'Mati', sub: 'Gesture dimatikan',
              cmd: 'settings put system os_action_tapping_wake 0; echo OK'),
        ],
      );

  // ── Perawatan Mata (Night Light) via Secure Settings — sama seperti
  //    fitur bawaan Android, tanpa menyentuh node hardware apa pun. ──
  _ChoiceGroup _nightLightGroup() => _ChoiceGroup(
        icon: Icons.remove_red_eye_rounded,
        label: 'Perawatan Mata',
        accent: kOrange,
        note: 'Layar jadi kekuningan — nyaman di malam hari.',
        readCmd: 'settings get secure night_display_activated 2>/dev/null',
        parse: (r) => r == '1'
            ? 'on'
            : (r == '0' || r == 'null' || r.isEmpty || r == 'OK')
                ? 'off'
                : '',
        choices: const [
          _Choice('on', 'Aktif', sub: 'Filter cahaya biru menyala',
              cmd: 'settings put secure night_display_activated 1; echo OK'),
          _Choice('off', 'Nonaktif', sub: 'Warna layar normal',
              cmd: 'settings put secure night_display_activated 0; echo OK'),
        ],
      );

  // ── Intensitas warna Perawatan Mata: Dingin ↔ Hangat. Nilai Android
  //    asli 1000K–10000K (semakin kecil = semakin hangat/kuning). Di sini
  //    dipetakan ke 3 tier sederhana biar tetap konsisten gaya _ChoiceGroup. ──
  _ChoiceGroup _nightLightTempGroup() => _ChoiceGroup(
        icon: Icons.thermostat_rounded,
        label: 'Intensitas Warna',
        accent: kPink,
        note: 'Berlaku saat Perawatan Mata aktif.',
        readCmd:
            'settings get secure night_display_color_temperature 2>/dev/null',
        parse: (r) {
          final v = int.tryParse(r.trim());
          if (v == null) return '';
          if (v >= 4500) return 'cold';
          if (v >= 3000) return 'mid';
          return 'warm';
        },
        choices: const [
          _Choice('cold', 'Dingin', sub: '~4500K — perubahan minim',
              cmd:
                  'settings put secure night_display_color_temperature 4500; echo OK'),
          _Choice('mid', 'Sedang', sub: '~3000K — seimbang',
              cmd:
                  'settings put secure night_display_color_temperature 3000; echo OK'),
          _Choice('warm', 'Hangat', sub: '~1800K — paling kekuningan',
              cmd:
                  'settings put secure night_display_color_temperature 1800; echo OK'),
        ],
      );

  // ── Ekstra Redup (Reduce Bright Colors) — meredupkan layar melebihi
  //    batas kecerahan minimum hardware. Fitur bawaan Android, dikontrol
  //    lewat Secure Settings yang sama seperti menu Aksesibilitas. ──
  _ChoiceGroup _extraDimGroup() => _ChoiceGroup(
        icon: Icons.brightness_low_rounded,
        label: 'Ekstra Redup',
        accent: kBlue,
        note: 'Layar lebih redup dari kecerahan minimum ponsel.',
        readCmd:
            'settings get secure reduce_bright_colors_activated 2>/dev/null',
        parse: (r) => r == '1'
            ? 'on'
            : (r == '0' || r == 'null' || r.isEmpty || r == 'OK')
                ? 'off'
                : '',
        choices: const [
          _Choice('on', 'Aktif', sub: 'Redupkan layar lebih jauh',
              cmd:
                  'settings put secure reduce_bright_colors_activated 1; echo OK'),
          _Choice('off', 'Nonaktif', sub: 'Kecerahan normal',
              cmd:
                  'settings put secure reduce_bright_colors_activated 0; echo OK'),
        ],
      );


  static const String _readTierCmd = '''
p=""
for d in /sys/devices/system/cpu/cpufreq/policy*; do p="\$d"; break; done
[ -n "\$p" ] || exit 0
m=\$(cat "\$p/cpuinfo_max_freq" 2>/dev/null)
c=\$(cat "\$p/scaling_max_freq" 2>/dev/null)
[ -n "\$m" ] && [ -n "\$c" ] && [ "\$m" -gt 0 ] && echo \$((c * 100 / m))
''';

  /// Skrip tier frekuensi (POSIX murni — tanpa awk/bc, jalan di toybox).
  /// ATURAN URUTAN PENTING: scaling_min TIDAK BOLEH melebihi scaling_max
  /// walau sesaat — kernel menolak tulisan itu. Maka saat MENURUNKAN max:
  /// turunkan min ke cpuinfo_min dulu, baru tulis max target.
  static String _tierCmd(int pct) => '''
ok=0
for pol in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -f "\$pol/scaling_max_freq" ] || continue
  hwmax=\$(cat "\$pol/cpuinfo_max_freq" 2>/dev/null)
  hwmin=\$(cat "\$pol/cpuinfo_min_freq" 2>/dev/null)
  [ -n "\$hwmax" ] || continue
  want=\$((hwmax * $pct / 100))
  best=""; bestd=999999999
  for f in \$(cat "\$pol/scaling_available_frequencies" 2>/dev/null); do
    d=\$((f - want)); [ \$d -lt 0 ] && d=\$((0 - d))
    if [ \$d -lt \$bestd ]; then bestd=\$d; best=\$f; fi
  done
  [ -n "\$best" ] || best=\$want
  curmin=\$(cat "\$pol/scaling_min_freq" 2>/dev/null)
  if [ -n "\$curmin" ] && [ "\$curmin" -gt "\$best" ]; then
    echo "\$hwmin" > "\$pol/scaling_min_freq"
  fi
  echo "\$best" > "\$pol/scaling_max_freq" && ok=1
done
[ \$ok -eq 1 ] && echo OK || echo "ERR: tidak ada policy yang bisa ditulis"
''';

  /// Reset: max DULU baru min — arah menaikkan, urutan ini yang aman.
  static const String _resetFreqCmd = '''
ok=0
for pol in /sys/devices/system/cpu/cpufreq/policy*; do
  hwmax=\$(cat "\$pol/cpuinfo_max_freq" 2>/dev/null); [ -n "\$hwmax" ] || continue
  hwmin=\$(cat "\$pol/cpuinfo_min_freq" 2>/dev/null)
  echo "\$hwmax" > "\$pol/scaling_max_freq" && ok=1
  [ -n "\$hwmin" ] && echo "\$hwmin" > "\$pol/scaling_min_freq"
done
[ \$ok -eq 1 ] && echo OK || echo "ERR: policy tidak ditemukan"
''';
}

/// Strip status root ringkas di atas halaman Command.
class _RootStrip extends StatelessWidget {
  const _RootStrip();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: isRootNotifier,
        builder: (_, root, __) {
          final c = root ? kGreen : kRed;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: c.withOpacity(.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.withOpacity(.25))),
            child: Row(children: [
              Icon(root ? Icons.check_circle_rounded : Icons.lock_rounded,
                  color: c, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      root
                          ? 'Root aktif — semua perintah dapat dieksekusi'
                          : 'Non-root — hanya perintah info yang tersedia',
                      style: TextStyle(color: c, fontSize: 11.5))),
            ]),
          );
        },
      );
}

/// Banner hasil deteksi device — nama, chipset, cluster, & peringatan
/// bila brand tidak konsisten dengan chipset (modul spoofing aktif).
class _DeviceBanner extends StatelessWidget {
  const _DeviceBanner();
  @override
  Widget build(BuildContext context) {
    final d = DeviceInfo.i;
    final accent = d.spoofSuspected ? kYellow : kCyan;
    final sub = [
      if (d.platform != '---') d.platform,
      if (d.cpuCores > 0) '${d.cpuCores} core',
      if (d.androidVer != '---') 'Android ${d.androidVer}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: accent.withOpacity(.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.phone_android_rounded, color: accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.displayName,
              style: TextStyle(
                  color: kWhite, fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty)
            Text(sub, style: TextStyle(color: mut(.4), fontSize: 10.5)),
          if (d.clusterSummary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(d.clusterSummary,
                style: TextStyle(
                    color: accent.withOpacity(.75),
                    fontSize: 10,
                    fontFamily: 'monospace')),
          ],
          if (d.spoofSuspected) ...[
            const SizedBox(height: 3),
            Text(
                '⚠️ Brand tidak konsisten dengan chipset — kemungkinan modul spoofing aktif',
                style: TextStyle(color: kYellow, fontSize: 9.5, height: 1.3)),
          ],
        ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// REFRESH RATE — lock + monitoring, dengan JENDELA PROTEKSI ANTI-ADAPTIF:
// selama ~6 detik setelah user memilih Hz, hasil polling TIDAK menimpa
// highlight pilihan user (sistem adaptif sering butuh beberapa detik
// untuk benar-benar pindah). Teks status tetap menampilkan nilai AKTUAL
// apa adanya — yang di-hold hanya highlight tombol.
// ─────────────────────────────────────────────────────────────────────
class _RefreshRateGroup extends StatefulWidget {
  const _RefreshRateGroup();
  @override
  State<_RefreshRateGroup> createState() => _RefreshRateGroupState();
}

class _RefreshRateGroupState extends State<_RefreshRateGroup> {
  String _current = '---';
  int? _currentHz;
  int? _heldHz;
  DateTime? _holdUntil;
  Timer? _timer;
  late final TabGate _gate;
  bool _polling = false;

  bool get _inHold =>
      _holdUntil != null && DateTime.now().isBefore(_holdUntil!);

  @override
  void initState() {
    super.initState();
    // Polling 4 detik HANYA saat tab Command terlihat & app foreground.
    _gate = TabGate(
      tab: 1,
      onChanged: (on) {
        if (on) {
          _poll();
          _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
        } else {
          _timer?.cancel();
          _timer = null;
        }
      },
    )..attach();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gate.detach();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      String hz = '';
      // 1) node non-root paling murah
      final fb = await Sys.read('/sys/class/graphics/fb0/measured_fps');
      if (fb.isNotEmpty) hz = fb;
      // 2) dumpsys (root) — angka fps aktual dari display service
      if (hz.isEmpty && isRootNotifier.value) {
        final out = await Root.exec(
            'dumpsys display | grep -oE "fps=[0-9]+\\.?[0-9]*" | head -1 | grep -oE "[0-9]+\\.?[0-9]*"');
        if (!out.startsWith('ERR') && out != 'OK') hz = out;
      }
      // 3) fallback: settings get (jalan tanpa root)
      if (hz.isEmpty) {
        final out = await Sys.sh('settings get system peak_refresh_rate');
        if (!out.startsWith('ERR') && out != 'null') hz = out;
      }
      final parsed = double.tryParse(hz.trim());
      final valid = (parsed != null && parsed >= 24 && parsed <= 165)
          ? parsed.round()
          : null;
      if (!mounted) return;
      setState(() {
        _currentHz = valid;
        _current = valid != null ? '$valid Hz' : '---';
      });
    } finally {
      _polling = false;
    }
  }

  Future<void> _lock(int hz) async {
    if (!isRootNotifier.value) {
      showSnack(context, '⚠ Butuh akses root untuk mengunci refresh rate');
      return;
    }
    HapticFeedback.mediumImpact();
    // Aktifkan jendela proteksi SEBELUM eksekusi — pilihan user langsung
    // tersorot & tidak "berkedip" digeser hasil poll berikutnya.
    setState(() {
      _heldHz = hz;
      _holdUntil = DateTime.now().add(const Duration(seconds: 6));
    });
    // peak = min ke Hz yang sama menutup celah sistem menaik-turunkan
    // sendiri; key MIUI/user ikut ditulis untuk kompatibilitas lintas ROM.
    final out = await Root.exec('''
settings put system peak_refresh_rate $hz.0
settings put system min_refresh_rate $hz.0
settings put system user_refresh_rate $hz
settings put system miui_refresh_rate $hz
echo OK''');
    if (!mounted) return;
    final ok = !out.startsWith('ERR');
    showSnack(context,
        ok ? '✓ Refresh rate dikunci ke ${hz}Hz' : '✗ Gagal: ${_stripErr(out)}');
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) _poll();
  }

  @override
  Widget build(BuildContext context) {
    const options = [60, 90, 120, 144];
    final highlightHz = _inHold ? _heldHz : _currentHz;
    final status = _current == '---'
        ? 'Membaca status…'
        : _inHold && _heldHz != _currentHz
            ? 'Aktif: $_current · mengunci ${_heldHz}Hz…'
            : 'Aktif sekarang: $_current';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder)),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: kTeal.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kTeal.withOpacity(.2))),
                child: Icon(Icons.monitor_rounded, color: kTeal, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Refresh Rate',
                      style: TextStyle(
                          color: kWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _current == '---' ? mut(.2) : kGreen)),
                    Expanded(
                        child: Text(status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: mut(.4), fontSize: 10.5))),
                  ]),
                ])),
          ]),
          const SizedBox(height: 14),
          Row(
              children: options.map((hz) {
            final on = highlightHz == hz;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: hz == options.last ? 0 : 8),
                child: Tap(
                  onTap: () => _lock(hz),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    curve: Motion.curve,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                        color: on ? kTeal.withOpacity(.16) : mut(.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: on ? kTeal : Colors.transparent)),
                    child: Column(children: [
                      Text('$hz',
                          style: TextStyle(
                              color: on ? kTeal : kWhite,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace')),
                      Text('Hz',
                          style: TextStyle(
                              color: on ? kTeal.withOpacity(.7) : mut(.35),
                              fontSize: 9)),
                    ]),
                  ),
                ),
              ),
            );
          }).toList()),
        ]),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────
// CHOICE GROUP — pengganti dialog perintah. Satu kartu = satu setelan;
// semua pilihan tampil sebagai chip INLINE dan yang aktif dibaca live
// dari sistem, jadi alur "ketuk kartu → dialog → ketuk → tutup" menjadi
// cukup SATU ketukan. Pola jendela-proteksi 6 detik mengikuti
// _RefreshRateGroup: pilihan user langsung tersorot & tidak berkedip
// digeser hasil poll berikutnya.
//   readCmd    : shell pembaca status → di-parse jadi key chip aktif.
//   statusCmd  : (opsional) status live tambahan di header, mis. tipe
//                sinyal aktual pada Band Lock.
//   pollEvery  : (opsional) poll berkala N detik; default hanya poll saat
//                tab terlihat & sesudah apply — hemat proses shell.
// ─────────────────────────────────────────────────────────────────────
class _Choice {
  const _Choice(this.key, this.label, {this.sub, this.cmd, this.danger = false});
  final String key;    // identitas — dicocokkan dengan hasil readCmd
  final String label;  // teks chip
  final String? sub;   // subteks kecil di bawah label
  final String? cmd;   // shell yang dijalankan saat chip diketuk
  final bool danger;   // minta konfirmasi dulu
}

class _ChoiceGroup extends StatefulWidget {
  const _ChoiceGroup({
    required this.icon,
    required this.label,
    required this.accent,
    required this.choices,
    this.readCmd,
    this.parse,
    this.statusCmd,
    this.statusParse,
    this.note,
    this.pollEvery,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final List<_Choice> choices;
  final String? readCmd;
  final String Function(String raw)? parse;
  final String? statusCmd;
  final String Function(String raw)? statusParse;
  final String? note;
  final int? pollEvery;

  @override
  State<_ChoiceGroup> createState() => _ChoiceGroupState();
}

class _ChoiceGroupState extends State<_ChoiceGroup> {
  /// Penjadwal berjenjang: 10 grup TIDAK menembakkan 10 proses shell
  /// serentak saat tab Command dibuka — tiap grup diberi jeda ~120 ms
  /// bertingkat, beban su/sh tersebar mulus tanpa lonjakan.
  static int _staggerSeq = 0;

  String _current = '';   // key chip aktif ('' = belum diketahui)
  String _status = '';    // status live tambahan (mis. "Sinyal: LTE")
  bool _known = false;    // true begitu readCmd berhasil dibaca sekali
  String? _held;          // pilihan user — dilindungi dari poll sesaat
  DateTime? _holdUntil;
  Timer? _timer;
  late final TabGate _gate;
  bool _polling = false;
  bool _applying = false; // double-tap tidak boleh memicu dua perintah
  bool _active = false;   // gate sedang menyala (tab terlihat + foreground)

  bool get _inHold =>
      _holdUntil != null && DateTime.now().isBefore(_holdUntil!);

  @override
  void initState() {
    super.initState();
    _gate = TabGate(
      tab: 1,
      onChanged: (on) {
        _active = on;
        if (on) {
          final delay =
              Duration(milliseconds: (_staggerSeq++ % 10) * 120);
          Future.delayed(delay, () {
            if (mounted && _active) _poll();
          });
          final s = widget.pollEvery;
          if (s != null) {
            _timer = Timer.periodic(Duration(seconds: s), (_) => _poll());
          }
        } else {
          _timer?.cancel();
          _timer = null;
        }
      },
    )..attach();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gate.detach();
    super.dispose();
  }

  Future<String> _sh(String cmd) async =>
      isRootNotifier.value ? Root.exec(cmd) : Sys.sh(cmd);

  bool _usable(String raw) =>
      raw.isNotEmpty &&
      !raw.startsWith('ERR') &&
      raw != 'NO_ROOT' &&
      raw != 'OK' &&
      raw != 'timeout';

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      if (widget.readCmd != null) {
        final raw = await _sh(widget.readCmd!);
        if (!mounted) return;
        if (_usable(raw)) {
          final key = widget.parse?.call(raw.trim()) ?? raw.trim();
          setState(() {
            _current = key;
            _known = true; // status terbaca — walau tak cocok chip mana pun
          });
        }
      }
      if (widget.statusCmd != null) {
        final raw = await _sh(widget.statusCmd!);
        if (!mounted) return;
        if (_usable(raw)) {
          final s = widget.statusParse?.call(raw.trim()) ?? raw.trim();
          setState(() => _status = s);
        }
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _apply(_Choice c) async {
    final cmd = c.cmd;
    if (cmd == null || _applying) return;
    if (!isRootNotifier.value) {
      showSnack(context, '⚠ Butuh akses root untuk ${widget.label}');
      return;
    }
    _applying = true;
    try {
      if (c.danger) {
        final ok = await confirmAction(context,
            title: '${widget.label}: ${c.label}',
            message:
                'Perintah ini berdampak besar pada sistem. Yakin melanjutkan?',
            accent: widget.accent);
        if (!ok || !mounted) return;
      }
      HapticFeedback.mediumImpact();
      // Jendela proteksi SEBELUM eksekusi — chip langsung tersorot.
      setState(() {
        _held = c.key;
        _holdUntil = DateTime.now().add(const Duration(seconds: 6));
      });
      final out = await Root.exec(cmd);
      if (!mounted) return;
      final err = out.startsWith('ERR');
      showSnack(context,
          err ? '✗ Gagal: ${_stripErr(out)}' : '✓ ${c.label} diterapkan');
      if (err) {
        setState(() {
          _held = null;
          _holdUntil = null;
        });
      }
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) _poll();
    } finally {
      _applying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.choices
        .where((c) => c.key == _current && c.key.isNotEmpty)
        .toList();
    final activeLabel = active.isEmpty ? '' : active.first.label;
    final unknown = !_known && _status.isEmpty;
    final statusTxt = unknown
        ? 'Membaca status…'
        : [
            if (_known)
              activeLabel.isNotEmpty
                  ? 'Aktif: $activeLabel'
                  : 'Kustom / tidak dikenali',
            if (_status.isNotEmpty) _status,
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder)),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: widget.accent.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.accent.withOpacity(.2))),
                child: Icon(widget.icon, color: widget.accent, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.label,
                      style: TextStyle(
                          color: kWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: unknown ? mut(.2) : kGreen)),
                    Expanded(
                        child: Text(statusTxt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: mut(.4), fontSize: 10.5))),
                  ]),
                ])),
          ]),
          if (widget.note != null) ...[
            const SizedBox(height: 6),
            Text(widget.note!,
                style: TextStyle(color: mut(.28), fontSize: 9.5, height: 1.3)),
          ],
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.choices.map(_chip).toList()),
        ]),
      ),
    );
  }

  Widget _chip(_Choice c) {
    final hl = _inHold ? _held : _current;
    final on = c.key.isNotEmpty && hl == c.key;
    final a = widget.accent;
    return Tap(
      onTap: () => _apply(c),
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
            color: on ? a.withOpacity(.16) : mut(.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? a : kBorder.withOpacity(.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (on) ...[
            Icon(Icons.check_rounded, color: a, size: 13),
            const SizedBox(width: 5),
          ] else if (c.danger) ...[
            Icon(Icons.warning_amber_rounded,
                color: kRed.withOpacity(.7), size: 12),
            const SizedBox(width: 5),
          ],
          Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.label,
                    style: TextStyle(
                        color: on ? a : kWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                if (c.sub != null) ...[
                  const SizedBox(height: 1),
                  Text(c.sub!,
                      style: TextStyle(
                          color: on ? a.withOpacity(.7) : mut(.32),
                          fontSize: 9)),
                ],
              ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// AKSI CEPAT — perintah sekali-jalan (bukan pilihan) dalam grid 2 kolom.
//   readOnly : boleh jalan TANPA root (via Sys.sh), hasil → bottom sheet.
//   danger   : minta konfirmasi dulu (Reboot).
// ─────────────────────────────────────────────────────────────────────
class _QuickAction {
  const _QuickAction(this.label, this.desc, this.icon, this.color, this.cmd,
      {this.readOnly = false, this.danger = false, this.ramSheet = false});
  final String label, desc, cmd;
  final IconData icon;
  final Color color;
  final bool readOnly, danger, ramSheet;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const List<_QuickAction> _actions = [
    _QuickAction('Clear RAM', 'Cache · tutup app',
        Icons.cleaning_services_rounded, kGreen, '',
        ramSheet: true),
    _QuickAction('Baca Suhu', 'Semua zona', Icons.thermostat_rounded, kCyan,
        'for z in /sys/class/thermal/thermal_zone*; do t=\$(cat "\$z/temp" 2>/dev/null); n=\$(cat "\$z/type" 2>/dev/null); [ -n "\$t" ] && echo "\${n:-\$z}: \$t"; done',
        readOnly: true),
    _QuickAction('Info Build', 'Model & Android', Icons.info_rounded, kBlue,
        'getprop ro.product.model; getprop ro.board.platform; getprop ro.build.version.release',
        readOnly: true),
    _QuickAction('Cek DNS', 'Private DNS aktif', Icons.search_rounded,
        kPurple, 'settings get global private_dns_specifier',
        readOnly: true),
    _QuickAction('Clear Logcat', 'Bersihkan log', Icons.delete_rounded,
        kOrange, 'logcat -c'),
    _QuickAction('Reboot', 'Mulai ulang', Icons.restart_alt_rounded, kRed,
        'reboot',
        danger: true),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 64),
      itemCount: _actions.length,
      itemBuilder: (_, i) => _QuickTile(_actions[i]),
    );
  }
}

class _QuickTile extends StatefulWidget {
  const _QuickTile(this.a);
  final _QuickAction a;

  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
  bool _flash = false, _running = false;

  Future<void> _exec() async {
    final a = widget.a;
    if (_running) return;
    if (a.ramSheet) {
      await showRamCleanSheet(context);
      return;
    }
    if (a.danger) {
      final ok = await confirmAction(context,
          title: a.label,
          message:
              'Perintah ini berdampak besar pada sistem. Yakin melanjutkan?',
          accent: a.color);
      if (!ok || !mounted) return;
    }
    HapticFeedback.mediumImpact();
    _running = true;
    try {
      final out = isRootNotifier.value
          ? await Root.exec(a.cmd)
          : await Sys.sh(a.cmd); // jalur non-root untuk aksi readOnly
      if (!mounted) return;
      final isErr = out.startsWith('ERR');
      if (a.readOnly) {
        showOutputSheet(context,
            title: a.label,
            body: (out == 'OK' || out.isEmpty)
                ? '(tidak ada output)'
                : isErr
                    ? _stripErr(out)
                    : out,
            icon: a.icon,
            color: isErr ? kRed : a.color);
        return;
      }
      if (isErr) {
        showSnack(context, '✗ ${_stripErr(out)}');
        return;
      }
      setState(() => _flash = true);
      showSnack(context, '✓ ${a.label} diterapkan');
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _flash = false);
      });
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    return ValueListenableBuilder<bool>(
      valueListenable: isRootNotifier,
      builder: (_, root, __) {
        final locked = !root && !a.readOnly;
        return Tap(
          onTap: locked
              ? () => showSnack(context, '⚠ Butuh akses root')
              : _exec,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: _flash
                    ? a.color.withOpacity(.18)
                    : locked
                        ? mut(.03)
                        : kPanel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: _flash ? a.color.withOpacity(.5) : kBorder)),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: (locked ? mut(.1) : a.color).withOpacity(.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(locked ? Icons.lock_rounded : a.icon,
                      color: locked ? mut(.3) : a.color, size: 17)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Flexible(
                          child: Text(a.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: kWhite,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700))),
                      if (a.danger) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.warning_amber_rounded,
                            color: kRed.withOpacity(.8), size: 11),
                      ],
                      if (a.readOnly) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.visibility_rounded,
                            color: a.color.withOpacity(.55), size: 11),
                      ],
                    ]),
                    const SizedBox(height: 1),
                    Text(a.desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: mut(.35), fontSize: 9.5)),
                  ])),
            ]),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TOOLS TAB — utilitas baca-saja. Hasil ditampilkan lewat bottom sheet
//  monospace yang bisa diseleksi/disalin.
// ═══════════════════════════════════════════════════════════════════

class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key});

  Future<void> _run(BuildContext context, String title, String cmd,
      {bool needRoot = false}) async {
    if (needRoot && !isRootNotifier.value) {
      showOutputSheet(context,
          title: 'Butuh Root',
          body: 'Fitur ini memerlukan akses root aktif.',
          icon: Icons.lock_rounded,
          color: kYellow);
      return;
    }
    HapticFeedback.selectionClick();
    final out = isRootNotifier.value
        ? await Root.exec(cmd)
        : await Sys.sh(cmd);
    if (!context.mounted) return;
    final isErr = out.startsWith('ERR');
    showOutputSheet(context,
        title: title,
        body: (out == 'OK' || out.isEmpty)
            ? 'Tidak ada output'
            : isErr
                ? _stripErr(out)
                : out,
        color: isErr ? kRed : kCyan);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isNightNotifier,
      builder: (_, __, ___) => SingleChildScrollView(
        physics: kScroll,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _pageHeader('Tools', 'System Utilities', kOrange),
          const SizedBox(height: 18),
          _sectionLabel('INFO (TANPA ROOT)', kCyan),
          const SizedBox(height: 10),
          _tool(context, 'CPU Info', 'Model, core, frekuensi, BogoMIPS',
              Icons.developer_board_rounded, kCyan, false,
              'cat /proc/cpuinfo | grep -E "model name|processor|cpu MHz|BogoMIPS|Hardware" | head -20'),
          _tool(context, 'Memory Detail', 'MemTotal, MemFree, Cached, Swap',
              Icons.memory_rounded, kPurple, false, 'cat /proc/meminfo'),
          _tool(context, 'Battery Detail', 'Status, kapasitas, suhu',
              Icons.battery_full_rounded, kGreen, false,
              'cat /sys/class/power_supply/battery/uevent 2>/dev/null || cat /sys/class/power_supply/*/uevent 2>/dev/null'),
          _tool(context, 'Suhu Thermal', 'Semua zona + nama sensor',
              Icons.thermostat_rounded, kRed, false,
              'for z in /sys/class/thermal/thermal_zone*; do t=\$(cat "\$z/temp" 2>/dev/null); n=\$(cat "\$z/type" 2>/dev/null); [ -n "\$t" ] && echo "\${n:-\$z}: \$t"; done'),
          _tool(context, 'Uptime & Load', 'Uptime dan load average sistem',
              Icons.timer_rounded, kTeal, false,
              'uptime; echo "---"; cat /proc/loadavg; echo "---"; cat /proc/uptime'),
          _tool(context, 'Disk Usage', 'Partisi dan penggunaan storage',
              Icons.storage_rounded, kOrange, false, 'df -h'),
          _tool(context, 'Network Info', 'IP, interface, DNS aktif',
              Icons.wifi_rounded, kBlue, false,
              'ip addr show 2>/dev/null; echo "---"; getprop net.dns1; getprop net.dns2'),
          _tool(context, 'Android Props', 'Build, model, versi OS',
              Icons.android_rounded, kGreen, false,
              'getprop ro.product.model; getprop ro.board.platform; getprop ro.build.version.release; getprop ro.product.manufacturer'),
          const SizedBox(height: 18),
          _sectionLabel('ROOT TOOLS', kRed),
          const SizedBox(height: 10),
          _tool(context, 'Kernel Log', 'dmesg 30 baris terakhir',
              Icons.article_rounded, kRed, true, 'dmesg | tail -30'),
          _tool(context, 'Proses Berjalan', 'Snapshot proses aktif',
              Icons.list_alt_rounded, kOrange, true, 'ps aux | head -25'),
          _tool(context, 'Governor per Core', 'Governor aktif tiap core CPU',
              Icons.tune_rounded, kCyan, true,
              'for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "\$c: \$(cat "\$c" 2>/dev/null)"; done'),
          _tool(context, 'Frekuensi per Core', 'Frekuensi aktif tiap core CPU',
              Icons.speed_rounded, kBlue, true,
              'for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do echo "\$c: \$(cat "\$c" 2>/dev/null)"; done'),
          _tool(context, 'Modules Kernel', 'Modul kernel yang ter-load',
              Icons.extension_rounded, kTeal, true, 'lsmod | head -25'),
          _tool(context, 'Swappiness Saat Ini', 'Nilai swappiness aktif',
              Icons.swap_horiz_rounded, kPurple, true,
              'cat /proc/sys/vm/swappiness'),
          _tool(context, 'TCP Congestion Aktif', 'Algoritma TCP aktif',
              Icons.compress_rounded, kGreen, true,
              'cat /proc/sys/net/ipv4/tcp_congestion_control'),
          _tool(context, 'I/O Scheduler Aktif', 'Scheduler tiap block device',
              Icons.storage_rounded, kYellow, true,
              'for d in /sys/block/*/queue/scheduler; do echo "\$d: \$(cat "\$d" 2>/dev/null)"; done'),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _tool(BuildContext context, String title, String desc, IconData icon,
          Color color, bool needRoot, String cmd) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Tap(
          onTap: () => _run(context, title, cmd, needRoot: needRoot),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
                color: kPanel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder)),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: color.withOpacity(.1),
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: color, size: 18)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: kWhite,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700))),
                      if (needRoot) ...[
                        const SizedBox(width: 6),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                                color: kRed.withOpacity(.1),
                                borderRadius: BorderRadius.circular(5)),
                            child: Text('ROOT',
                                style: TextStyle(
                                    color: kRed,
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .8))),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: mut(.38), fontSize: 10.5)),
                  ])),
              Icon(Icons.chevron_right_rounded, color: mut(.25), size: 18),
            ]),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════
//  ABOUT TAB
// ═══════════════════════════════════════════════════════════════════

/// Avatar robot animasi. Ticker HANYA berjalan saat tab Tentang terlihat
/// & app foreground (TabGate) — IndexedStack menjaga widget ini tetap
/// hidup di semua tab, tapi tanpa gate ia akan memaksa repaint 60fps
/// terus-menerus di latar belakang.
class _AnimatedAvatar extends StatefulWidget {
  const _AnimatedAvatar();
  @override
  State<_AnimatedAvatar> createState() => _AnimatedAvatarState();
}

class _AnimatedAvatarState extends State<_AnimatedAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _p;
  late final AnimationController _o;
  late final TabGate _gate;

  @override
  void initState() {
    super.initState();
    _p = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _o = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    _gate = TabGate(
      tab: 3,
      onChanged: (on) {
        if (on) {
          _p.repeat(reverse: true);
          _o.repeat();
        } else {
          _p.stop();
          _o.stop();
        }
      },
    )..attach();
  }

  @override
  void dispose() {
    _gate.detach();
    _p.dispose();
    _o.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
            animation: Listenable.merge([_p, _o]),
            builder: (_, __) => CustomPaint(
                size: const Size(130, 130),
                painter: _AvatarPainter(_p.value, _o.value))),
      );
}

class _AvatarPainter extends CustomPainter {
  final double pulse, orbit;
  _AvatarPainter(this.pulse, this.orbit);

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2, cy = s.height / 2, r = s.width / 2;
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
                  colors: [const Color(0xFF1A1A40), const Color(0xFF060612)])
              .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
    for (int i = 0; i < 8; i++) {
      final a = (i / 8 + orbit) * 2 * math.pi;
      canvas.drawCircle(
          Offset(cx + r * .82 * math.cos(a), cy + r * .82 * math.sin(a)),
          i % 2 == 0 ? 2.5 : 1.5,
          Paint()..color = kCyan.withOpacity(i % 2 == 0 ? .5 + .3 * pulse : .2));
    }
    canvas.drawCircle(
        Offset(cx, cy),
        r * (.78 + .04 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kCyan.withOpacity(.15 + .1 * pulse)
          ..strokeWidth = 1.2);
    final body = Path()
      ..moveTo(cx - r * .3, cy + r * .2)
      ..lineTo(cx + r * .3, cy + r * .2)
      ..lineTo(cx + r * .42, cy + r * .75)
      ..lineTo(cx - r * .42, cy + r * .75)
      ..close();
    canvas.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(
                  colors: [const Color(0xFF1E1E50), kCyan.withOpacity(.2)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter)
              .createShader(
                  Rect.fromLTWH(cx - r * .42, cy + r * .2, r * .84, r * .55)));
    canvas.drawPath(
        Path()
          ..moveTo(cx - r * .1, cy + r * .2)
          ..lineTo(cx, cy + r * .35)
          ..lineTo(cx + r * .1, cy + r * .2),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kCyan.withOpacity(.5)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(
        Offset(cx, cy - r * .18),
        r * .28,
        Paint()
          ..shader = RadialGradient(
                  colors: [const Color(0xFF252560), const Color(0xFF0F0F30)])
              .createShader(Rect.fromCircle(
                  center: Offset(cx - r * .05, cy - r * .28), radius: r * .28)));
    canvas.drawCircle(
        Offset(cx, cy - r * .18),
        r * .28,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kCyan.withOpacity(.3)
          ..strokeWidth = 1.2);
    final hair = Path()
      ..addArc(
          Rect.fromCircle(center: Offset(cx, cy - r * .18), radius: r * .28),
          math.pi + .25,
          2.63)
      ..lineTo(cx, cy - r * .18)
      ..close();
    canvas.drawPath(hair, Paint()..color = const Color(0xFF5030D0));
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx - r * .07, cy - r * .38), radius: r * .08),
        3.8,
        1.4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kPurple.withOpacity(.5)
          ..strokeWidth = 2);
    for (final dx in [-r * .1, r * .1]) {
      canvas.drawCircle(
          Offset(cx + dx, cy - r * .2),
          3.5,
          Paint()
            ..color = kCyan
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawCircle(
          Offset(cx + dx, cy - r * .2), 1.5, Paint()..color = Colors.white);
    }
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx, cy - r * .08), width: r * .22, height: r * .13),
        .3,
        2.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kCyan.withOpacity(.6)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);
    final badge = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy + r * .4), width: r * .5, height: r * .17),
        const Radius.circular(4));
    canvas.drawRRect(badge, Paint()..color = kCyan.withOpacity(.12));
    canvas.drawRRect(
        badge,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kCyan.withOpacity(.45)
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_AvatarPainter o) => o.pulse != pulse || o.orbit != orbit;
}

class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  Future<void> _recheckRoot(BuildContext context) async {
    showSnack(context, 'Memeriksa ulang akses root…');
    final ok = await Root.check();
    isRootNotifier.value = ok;
    if (!context.mounted) return;
    showSnack(context, ok ? 'Root terdeteksi ✓' : 'Root tidak tersedia');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isNightNotifier,
      builder: (_, __, ___) => ValueListenableBuilder<int>(
        // Deteksi ulang selesai → tab ini otomatis rebuild dengan data baru.
        valueListenable: DeviceInfo.revision,
        builder: (_, rev, ___) => ValueListenableBuilder<bool>(
          valueListenable: isRootNotifier,
          builder: (ctx, root, child) {
            final d = DeviceInfo.i;
            return SingleChildScrollView(
              physics: kScroll,
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pageHeader('Tentang', 'About This App', kGreen),
                    const SizedBox(height: 20),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [
                                  kCyan.withOpacity(.08),
                                  kPurple.withOpacity(.06)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(24),
                            border:
                                Border.all(color: kCyan.withOpacity(.2))),
                        child: Column(children: [
                          Stack(alignment: Alignment.bottomRight, children: [
                            const _AnimatedAvatar(),
                            Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                    color: kGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: kPanel, width: 2.5)),
                                child: const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 12)),
                          ]),
                          const SizedBox(height: 14),
                          Text('Xyz_AI',
                              style: TextStyle(
                                  color: kWhite,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.5)),
                          const SizedBox(height: 4),
                          Text('Android Developer & Enthusiast',
                              style:
                                  TextStyle(color: mut(.4), fontSize: 13)),
                          const SizedBox(height: 14),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Chip root BISA DITEKAN → cek ulang akses
                                // root tanpa restart aplikasi.
                                Tap(
                                    onTap: () => _recheckRoot(ctx),
                                    child: _chip(
                                        root ? 'Root Active' : 'Non-Root',
                                        Icons.security_rounded,
                                        root ? kGreen : kYellow)),
                                const SizedBox(width: 8),
                                _chip(
                                    d.platform == '---' ? '…' : d.platform,
                                    Icons.developer_board_rounded,
                                    kCyan),
                                const SizedBox(width: 8),
                                _chip('v2.2', Icons.rocket_launch_rounded,
                                    kPurple),
                              ]),
                        ])),
                    const SizedBox(height: 20),
                    _sectionLabel('SPESIFIKASI', kCyan),
                    const SizedBox(height: 10),
                    // Semua nilai REALTIME dari DeviceInfo — dibaca dari
                    // device tempat app benar-benar berjalan, bukan hardcode.
                    _info('Perangkat', d.displayName,
                        Icons.phone_android_rounded,
                        d.spoofSuspected ? kYellow : kCyan),
                    _info('Chipset', d.platform,
                        Icons.developer_board_rounded, kPurple),
                    _info('CPU Core', '${d.cpuCores} core',
                        Icons.memory_rounded, kBlue),
                    _info('Root', root ? 'Aktif' : 'Tidak aktif',
                        Icons.verified_rounded, root ? kGreen : kRed),
                    _info('Android', 'Android ${d.androidVer}',
                        Icons.android_rounded, kTeal),
                    const SizedBox(height: 20),
                    _sectionLabel('FITUR', kPurple),
                    const SizedBox(height: 10),
                    _feat(Icons.account_tree_rounded, kPurple,
                        'Nested Command Menu',
                        'Kontrol berlapis — governor, frekuensi, cache, thermal, network, I/O.'),
                    _feat(Icons.terminal_rounded, kCyan, 'Eksekusi Root Real',
                        'Semua perintah dijalankan langsung via su -c ke kernel perangkat.'),
                    _feat(Icons.dashboard_rounded, kBlue, 'Live Dashboard',
                        'CPU multi-cluster, suhu, RAM, baterai — dengan sparkline realtime.'),
                    _feat(Icons.hub_rounded, kTeal, 'Multi-Cluster Aware',
                        'Frekuensi & governor diterapkan per-policy: LITTLE, BIG, dan PRIME.'),
                    _feat(Icons.battery_saver_rounded, kGreen,
                        'Hemat Daya Cerdas',
                        'Polling & animasi berhenti otomatis saat tab tak terlihat atau app di background.'),
                    _feat(Icons.lock_rounded, kYellow, 'Non-Root Compatible',
                        'Mode aman tanpa root — info tetap tampil, kontrol dikunci.'),
                    _feat(Icons.dark_mode_rounded, kOrange,
                        'Night / Light Mode',
                        'Ganti tema kapan saja dengan satu ketukan.'),
                    const SizedBox(height: 24),
                    Center(
                        child: Text('Dibuat dengan ❤️ oleh Xyz_AI',
                            style:
                                TextStyle(color: mut(.3), fontSize: 12))),
                    const SizedBox(height: 6),
                    Center(
                        child: Text('Xyz_AI © 2026',
                            style:
                                TextStyle(color: mut(.2), fontSize: 11))),
                    const SizedBox(height: 20),
                  ]),
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String l, IconData i, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: c.withOpacity(.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, color: c, size: 13),
        const SizedBox(width: 5),
        Text(l,
            style: TextStyle(
                color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      ]));

  Widget _info(String label, String value, IconData icon, Color color) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kBorder)),
              child: Row(children: [
                Icon(icon, color: color, size: 17),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(color: mut(.4), fontSize: 12)),
                const Spacer(),
                Flexible(
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: kWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
              ])));

  Widget _feat(IconData ic, Color c, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: c.withOpacity(.1),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(ic, color: c, size: 19)),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: kWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(body,
                  style:
                      TextStyle(color: mut(.4), fontSize: 11.5, height: 1.4)),
            ])),
          ])));
}

// ═══════════════════════════════════════════════════════════════════
//  SHARED WIDGET HELPERS
// ═══════════════════════════════════════════════════════════════════

Widget _pageHeader(String title, String subtitle, Color accent) {
  return ValueListenableBuilder<bool>(
    valueListenable: isNightNotifier,
    builder: (_, night, __) =>
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _AppIcon(size: 36),
      const SizedBox(width: 12),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                color: kWhite,
                letterSpacing: -.5)),
        Text(subtitle, style: TextStyle(fontSize: 11, color: mut(.35))),
      ])),
      Tap(
        onTap: () => isNightNotifier.value = !isNightNotifier.value,
        child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: (night ? kPurple : kYellow).withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: (night ? kPurple : kYellow).withOpacity(.35))),
            child: Icon(
                night ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: 18,
                color: night ? kPurple : kYellow)),
      ),
    ]),
  );
}

Widget _sectionLabel(String text, Color accent) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
              color: accent, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(text,
          style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8)),
    ]));
