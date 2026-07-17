// ═══════════════════════════════════════════════════════════════════
//  Xyz_AI Command Center — main.dart LENGKAP (bisa langsung di-build)
//
//  File sebelumnya yang di-commit ke repo ternyata hanya POTONGAN
//  (drop-in 3 class) tanpa import / DashStats / konstanta / main().
//  Itulah sebab semua error "Type 'StatelessWidget' not found" dst.
//
//  File ini mandiri: import lengkap, konstanta warna, DashStats +
//  poller statistik (baterai, RAM, CPU freq via root), kartu baterai
//  stabil, sparkline anti-beku, dan kartu Perawatan Mata FUNGSI ASLI
//  (settings put secure night_display_* via su).
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────
// PALET WARNA
// ─────────────────────────────────────────────────────────────────────
const Color kBg = Color(0xFF0A0A0C);
const Color kPanel = Color(0xFF141417);
const Color kBorder = Color(0xFF26262B);
const Color kWhite = Color(0xFFF2F2F5);
const Color kRed = Color(0xFFFF3B30);
const Color kGreen = Color(0xFF34C759);
const Color kOrange = Color(0xFFFF9F0A);
const Color kYellow = Color(0xFFFFD60A);

/// Putih redup dengan opasitas [o] — dipakai untuk label sekunder.
Color mut(double o) => kWhite.withOpacity(o);

// ─────────────────────────────────────────────────────────────────────
// UTIL ROOT
// ─────────────────────────────────────────────────────────────────────
Future<String> rootRun(String cmd) async {
  final r = await Process.run('su', ['-c', cmd]);
  if (r.exitCode != 0) {
    final err = r.stderr.toString().trim();
    throw Exception(err.isNotEmpty ? err : 'exit code ${r.exitCode}');
  }
  return r.stdout.toString().trim();
}

/// Baca file sistem: coba langsung dulu, kalau ditolak baru lewat su.
Future<String?> readSys(String path) async {
  try {
    return (await File(path).readAsString()).trim();
  } catch (_) {
    try {
      return await rootRun('cat $path');
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// DASH STATS — snapshot statistik + riwayat sparkline
// ─────────────────────────────────────────────────────────────────────
class DashStats {
  // CPU
  String cpuText = '---';
  final List<double> freqHist = <double>[];

  // RAM
  String memText = '---';
  final List<double> memHist = <double>[];

  // Baterai
  int? batPct;
  String batStatus = '';
  String batTempText = '---';
  final List<double> batHist = <double>[];

  String get batText => batPct == null ? '---' : '$batPct%';

  static const int _histMax = 24;

  void _push(List<double> hist, double v) {
    hist.add(v);
    if (hist.length > _histMax) hist.removeAt(0);
  }

  Future<void> refresh() async {
    // ── Baterai ──
    final cap =
        await readSys('/sys/class/power_supply/battery/capacity');
    final st = await readSys('/sys/class/power_supply/battery/status');
    final tp = await readSys('/sys/class/power_supply/battery/temp');
    batPct = cap == null ? null : int.tryParse(cap);
    batStatus = st ?? '';
    if (tp != null) {
      final raw = double.tryParse(tp);
      if (raw != null) {
        // Node temp umumnya dalam persepuluh °C (mis. 342 = 34.2°C).
        final c = raw > 100 ? raw / 10.0 : raw;
        batTempText = '${c.toStringAsFixed(1)}°C';
      }
    }
    if (batPct != null) _push(batHist, batPct!.toDouble());

    // ── CPU: frekuensi cpu0 ──
    final f = await readSys(
        '/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq');
    final khz = f == null ? null : double.tryParse(f);
    if (khz != null) {
      final mhz = khz / 1000.0;
      cpuText = mhz >= 1000
          ? '${(mhz / 1000).toStringAsFixed(2)} GHz'
          : '${mhz.toStringAsFixed(0)} MHz';
      _push(freqHist, mhz);
    }

    // ── RAM ──
    final mi = await readSys('/proc/meminfo');
    if (mi != null) {
      int? grab(String key) {
        final m = RegExp('$key:\\s+(\\d+)').firstMatch(mi);
        return m == null ? null : int.tryParse(m.group(1)!);
      }

      final total = grab('MemTotal');
      final avail = grab('MemAvailable');
      if (total != null && avail != null && total > 0) {
        final usedPct = (total - avail) / total * 100;
        final usedGb = (total - avail) / 1048576.0;
        memText = '${usedGb.toStringAsFixed(1)} GB';
        _push(memHist, usedPct);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────────────
void main() => runApp(const XyzApp());

class XyzApp extends StatelessWidget {
  const XyzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xyz_AI Command Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
            primary: kRed, secondary: kGreen, surface: kPanel),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DashStats _stats = DashStats();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  Future<void> _tick() async {
    await _stats.refresh();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: const Text('Command Center',
            style: TextStyle(
                color: kWhite, fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            Expanded(
                child: _StatCard(
                    title: 'CPU',
                    value: _stats.cpuText,
                    icon: Icons.memory_rounded,
                    color: kGreen,
                    hist: _stats.freqHist)),
            const SizedBox(width: 12),
            Expanded(
                child: _StatCard(
                    title: 'RAM',
                    value: _stats.memText,
                    icon: Icons.storage_rounded,
                    color: kOrange,
                    hist: _stats.memHist)),
          ]),
          const SizedBox(height: 12),
          _BatteryCard(_stats),
          const SizedBox(height: 12),
          const EyeCareCard(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// KARTU STAT KECIL (CPU / RAM) dengan sparkline latar
// ─────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color,
      required this.hist});

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final List<double> hist;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(.18))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Stack(children: [
            if (hist.length >= 2)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                height: 22,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: ClipRect(
                      child: CustomPaint(
                          painter: _SparklinePainter(hist, color),
                          size: Size.infinite),
                    ),
                  ),
                ),
              ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 15),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1,
                    style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace')),
              ),
              const SizedBox(height: 2),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: mut(.35),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// BATTERY — kapasitas + sparkline, suhu, dan status pengisian daya
// (dibaca dari power_supply/battery/status) dalam SATU kartu.
// ─────────────────────────────────────────────────────────────────────
class _BatteryCard extends StatelessWidget {
  const _BatteryCard(this.s);
  final DashStats s;

  static const double _cardH = 108;
  static const double _radius = 18;

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
                    : s.batStatus.trim().isEmpty
                        ? '---'
                        : s.batStatus;

    return Container(
      height: _cardH,
      decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: c.withOpacity(.18))),
      // Clip seluruh isi ke radius kartu: sparkline, glow, apa pun —
      // tidak ada yang bisa menggambar keluar sudut kartu.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius - 1),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Kiri: ikon + kapasitas besar + sparkline latar ──
              Expanded(child: _capacityPane(c, charging)),
              Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: kBorder.withOpacity(.7)),
              // ── Kanan: suhu + status pengisian ──
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
            ],
          ),
        ),
      ),
    );
  }

  /// Panel kiri. Sparkline adalah LAPISAN LATAR yang terkurung:
  /// • ClipRect     → goresan/glow tidak keluar area kiri
  /// • RepaintBoundary → repaint per-tick tidak menyeret ikon & teks
  /// • IgnorePointer   → murni dekorasi, tidak mencuri sentuhan
  Widget _capacityPane(Color c, bool charging) {
    return Stack(children: [
      if (s.batHist.length >= 2)
        Positioned(
          left: 0,
          right: 0,
          bottom: 14, // di atas label KAPASITAS
          height: 24,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ClipRect(
                child: CustomPaint(
                    painter: _SparklinePainter(s.batHist, c),
                    size: Size.infinite),
              ),
            ),
          ),
        ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: c.withOpacity(.12),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(
                charging ? Icons.bolt_rounded : Icons.battery_full_rounded,
                color: c,
                size: 15)),
        const Spacer(),
        // FittedBox: angka mengecil sendiri bila ruang sempit.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(s.batText,
              maxLines: 1,
              style: TextStyle(
                  color: c,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace')),
        ),
        const SizedBox(height: 2),
        Text('KAPASITAS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: mut(.35),
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      ]),
    ]);
  }

  Widget _mini(IconData icon, Color c, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, color: c, size: 14)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: mut(.35),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  const SizedBox(height: 1),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kWhite,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace')),
                ]),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────
// SPARKLINE — grafik mini realtime. Snapshot (List.of) + listEquals
// agar shouldRepaint tetap bekerja saat riwayat dimutasi in-place.
// ─────────────────────────────────────────────────────────────────────
class _SparklinePainter extends CustomPainter {
  _SparklinePainter(List<double> source, this.color)
      : data = List.of(source); // snapshot, ±24 double — sangat murah
  final List<double> data;
  final Color color;

  static const double _dotR = 2.6;
  static const double _glowR = 4.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2 ||
        size.width <= _glowR * 2 ||
        size.height <= _glowR * 2) return;

    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    // Margin internal sebesar radius glow: titik "sekarang" tidak
    // pernah terpotong tepi canvas.
    final left = _glowR;
    final right = size.width - _glowR;
    final top = _glowR;
    final bottom = size.height - _glowR;
    final dx = (right - left) / (data.length - 1);

    final points = <Offset>[
      for (int i = 0; i < data.length; i++)
        Offset(left + i * dx,
            bottom - ((data[i] - minV) / range * (bottom - top))),
    ];

    // Area gradasi di bawah garis.
    final areaPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      areaPath.lineTo(p.dx, p.dy);
    }
    areaPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withOpacity(.22), color.withOpacity(0)])
              .createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // Garis utama.
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

    // Titik "sekarang" + glow.
    canvas.drawCircle(
        points.last, _glowR, Paint()..color = color.withOpacity(.25));
    canvas.drawCircle(points.last, _dotR, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !listEquals(old.data, data);
}

// ═══════════════════════════════════════════════════════════════════
//  PERAWATAN MATA — FUNGSI ASLI via root (settings put secure).
//
//  Key bawaan framework Android untuk fitur Perawatan Mata / Eye
//  Comfort (mesinnya night display, teksnya di-translate ROM):
//    night_display_activated          → 0/1     (on/off)
//    night_display_auto_mode          → 0/1/2   (jadwal)
//    night_display_color_temperature  → Kelvin  (intensitas)
//
//  Kalau ROM kamu punya key sendiri, cek:
//    adb shell settings list secure | grep -i night
//  lalu ganti konstanta di _EyeCareKeys.
// ═══════════════════════════════════════════════════════════════════
class _EyeCareKeys {
  static const activated = 'night_display_activated';
  static const autoMode = 'night_display_auto_mode';
  static const colorTemp = 'night_display_color_temperature';
}

class EyeCareCard extends StatefulWidget {
  const EyeCareCard({super.key});

  @override
  State<EyeCareCard> createState() => _EyeCareCardState();
}

class _EyeCareCardState extends State<EyeCareCard> {
  static const double _radius = 18;
  // Rentang suhu warna umum AOSP night display.
  static const int _tempCool = 6670; // paling "Dingin"
  static const int _tempWarm = 2596; // paling "Hangat"

  bool _loading = true;
  bool _active = false;
  int _autoMode = 0; // 0 nonaktif, 1 kustom, 2 senja–fajar
  int _temp = 4500;
  String? _error;

  @override
  void initState() {
    super.initState();
    _readState();
  }

  Future<void> _readState() async {
    try {
      final a = await rootRun('settings get secure ${_EyeCareKeys.activated}');
      final m = await rootRun('settings get secure ${_EyeCareKeys.autoMode}');
      final t = await rootRun('settings get secure ${_EyeCareKeys.colorTemp}');
      if (!mounted) return;
      setState(() {
        _active = a == '1';
        _autoMode = int.tryParse(m) ?? 0;
        _temp = int.tryParse(t) ?? 4500;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Butuh root untuk baca/atur setting ini.';
      });
    }
  }

  Future<void> _setActive(bool v) async {
    final prev = _active;
    setState(() => _active = v);
    try {
      await rootRun(
          'settings put secure ${_EyeCareKeys.activated} ${v ? 1 : 0}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _active = prev);
      _toast('Gagal mengubah Perawatan Mata: $e');
    }
  }

  Future<void> _setAutoMode(int v) async {
    final prev = _autoMode;
    setState(() => _autoMode = v);
    try {
      await rootRun('settings put secure ${_EyeCareKeys.autoMode} $v');
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoMode = prev);
      _toast('Gagal mengubah jadwal: $e');
    }
  }

  Future<void> _setTemp(int v) async {
    try {
      await rootRun('settings put secure ${_EyeCareKeys.colorTemp} $v');
    } catch (e) {
      _toast('Gagal mengubah intensitas: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kRed),
    );
  }

  String get _autoModeLabel {
    switch (_autoMode) {
      case 2:
        return 'Senja–fajar';
      case 1:
        return 'Kustom';
      default:
        return 'Nonaktif';
    }
  }

  double _posFromKelvin(int k) =>
      ((k - _tempCool) / (_tempWarm - _tempCool)).clamp(0.0, 1.0);
  int _kelvinFromPos(double p) =>
      (_tempCool + (_tempWarm - _tempCool) * p).round();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: kRed.withOpacity(.18))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius - 1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Toggle utama ──
                    Row(
                      children: [
                        Icon(Icons.wb_incandescent_rounded,
                            color: _active ? kRed : mut(.4), size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Perawatan Mata',
                              style: TextStyle(
                                  color: kWhite,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Switch(
                          value: _active,
                          activeColor: kRed,
                          onChanged: _setActive,
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(_error!,
                          style: const TextStyle(color: kRed, fontSize: 10.5)),
                    ],
                    const Divider(height: 20),

                    // ── Jadwal ──
                    Text('TAMPILAN',
                        style: TextStyle(
                            color: mut(.35),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickSchedule,
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Kustomisasikan jadwal',
                                style: TextStyle(
                                    color: kWhite,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                          Text(_autoModeLabel,
                              style: TextStyle(color: mut(.5), fontSize: 12)),
                          Icon(Icons.chevron_right_rounded,
                              color: mut(.4), size: 18),
                        ],
                      ),
                    ),
                    const Divider(height: 20),

                    // ── Intensitas ──
                    Text('INTENSITAS',
                        style: TextStyle(
                            color: mut(.35),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Dingin',
                            style: TextStyle(color: mut(.5), fontSize: 11.5)),
                        Text('Hangat',
                            style: TextStyle(color: mut(.5), fontSize: 11.5)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: kRed,
                        inactiveTrackColor: kBorder,
                        thumbColor: kRed,
                        overlayColor: kRed.withOpacity(.15),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _posFromKelvin(_temp),
                        min: 0,
                        max: 1,
                        onChanged: (v) =>
                            setState(() => _temp = _kelvinFromPos(v)),
                        onChangeEnd: (v) => _setTemp(_kelvinFromPos(v)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: mut(.35), size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              'Mengubah warna layar jadi kekuningan agar '
                              'lebih nyaman di mata saat cahaya redup.',
                              style:
                                  TextStyle(color: mut(.35), fontSize: 10.5)),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _pickSchedule() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: kPanel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _scheduleTile(ctx, 0, 'Nonaktif'),
            _scheduleTile(ctx, 2, 'Ikuti senja–fajar (otomatis)'),
          ],
        ),
      ),
    );
    if (choice != null) _setAutoMode(choice);
  }

  Widget _scheduleTile(BuildContext ctx, int value, String label) => ListTile(
        title: Text(label, style: const TextStyle(color: kWhite)),
        trailing: _autoMode == value
            ? const Icon(Icons.check_rounded, color: kRed)
            : null,
        onTap: () => Navigator.pop(ctx, value),
      );
}
