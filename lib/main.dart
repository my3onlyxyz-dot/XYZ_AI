// ═══════════════════════════════════════════════════════════════════
//  DROP-IN REPLACEMENT — Xyz_AI Command Center
//
//  Ganti dua kelas ini di main.dart:
//    1. _BatteryCard      (blok lama ± baris 2371–2492)
//    2. _SparklinePainter (blok lama ± baris 2516–2571)
//
//  Nama, konstruktor, dan pemakaian TIDAK berubah — call site di
//  Dashboard (hero card, RAM card, battery card) tidak perlu disentuh.
//
//  Yang distabilkan:
//  • Seluruh isi kartu dibungkus ClipRRect → tidak ada paint yang bocor
//    keluar radius kartu.
//  • Sparkline dibungkus RepaintBoundary + ClipRect + IgnorePointer:
//    repaint per-tick terkurung di lapisannya sendiri, murni dekorasi.
//  • Band sparkline dinaikkan di atas label KAPASITAS — garis tidak lagi
//    menimpa teks seperti strikethrough.
//  • Painter menyisihkan margin sebesar radius glow → titik "sekarang"
//    tidak pernah terpotong tepi canvas / nempel ke divider.
//  • FIX BUG BEKU: riwayat dimutasi in-place oleh _push(), sehingga
//    shouldRepaint lama selalu membandingkan list yang SAMA dan berhenti
//    repaint begitu riwayat penuh (24 sampel). Painter kini menyimpan
//    SNAPSHOT (List.of) dan membandingkan isi dengan listEquals.
//    Fix ini otomatis berlaku juga untuk CPU hero card & RAM card.
//  • Angka kapasitas dibungkus FittedBox → tidak overflow saat font
//    scale sistem dibesarkan; teks kanan tetap ellipsis.
// ═══════════════════════════════════════════════════════════════════

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
  /// • ClipRect     → goresan/glow tidak keluar area kiri (tidak nempel divider)
  /// • RepaintBoundary → repaint per-tick tidak menyeret ikon & teks
  /// • IgnorePointer   → murni dekorasi, tidak mencuri sentuhan
  /// Band diangkat setinggi label agar garis tidak menimpa 'KAPASITAS'.
  Widget _capacityPane(Color c, bool charging) {
    return Stack(children: [
      if (s.batHist.length >= 2)
        Positioned(
          left: 0,
          right: 0,
          bottom: 14, // di atas label KAPASITAS (≈ tinggi label + jarak)
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
        // FittedBox: angka mengecil sendiri bila ruang sempit / font
        // scale sistem besar — tidak pernah overflow.
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
          // Ikon disejajarkan ke baris label (bukan melayang di tengah
          // dua baris teks).
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
// SPARKLINE — grafik mini realtime kartu statistik. Auto-scale min-max
// agar pergerakan kecil tetap terlihat; titik paling kanan = "sekarang".
//
// PENTING: riwayat asli (_freqHist/_memHist/_batHist) DIMUTASI in-place
// oleh _push(). Painter menyimpan SNAPSHOT (List.of) supaya shouldRepaint
// membandingkan data lama vs baru — bukan objek list yang sama. Tanpa
// ini, sparkline berhenti repaint begitu riwayat penuh (24 sampel).
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

    // Margin internal sebesar radius glow: titik "sekarang" dan ujung
    // stroke tidak pernah terpotong tepi canvas.
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

    // Titik "sekarang" + glow — kini selalu utuh di dalam canvas.
    canvas.drawCircle(points.last, _glowR, Paint()..color = color.withOpacity(.25));
    canvas.drawCircle(points.last, _dotR, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !listEquals(old.data, data);
}

// ═══════════════════════════════════════════════════════════════════
//  PERAWATAN MATA — kartu baru, FUNGSI ASLI (bukan cuma tampilan).
//
//  Menulis langsung ke Settings.Secure Android via root (su), yaitu
//  key BAWAAN framework Android untuk fitur "Perawatan Mata" / Eye
//  Comfort (di banyak ROM ini disebut Night Light di source code-nya,
//  meskipun teksnya di-translate jadi "Perawatan Mata" — mesin di
//  baliknya sama):
//    night_display_activated          → 0/1        (on/off)
//    night_display_auto_mode          → 0/1/2      (jadwal)
//    night_display_color_temperature  → Kelvin     (intensitas)
//
//  CATATAN: kalau di HP kamu ROM-nya punya key SENDIRI yang berbeda
//  (misal MIUI lama pernah pakai 'reading_mode' terpisah), jalankan:
//     adb shell settings list secure | grep -i mata
//     adb shell settings list secure | grep -i night
//     adb shell settings list secure | grep -i reading
//  lalu ganti tiga konstanta di _EyeCareKeys di bawah ini.
//
//  Butuh akses root (su) — sudah sesuai konteks app ini yang baca
//  power_supply langsung.
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
  // Rentang suhu warna umum AOSP night display. Sesuaikan kalau slider
  // terasa mentok terlalu cepat / kurang jauh di HP kamu.
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

  Future<String> _root(String cmd) async {
    final r = await Process.run('su', ['-c', cmd]);
    if (r.exitCode != 0) {
      final err = r.stderr.toString().trim();
      throw Exception(err.isNotEmpty ? err : 'exit code ${r.exitCode}');
    }
    return r.stdout.toString().trim();
  }

  Future<void> _readState() async {
    try {
      final a = await _root('settings get secure ${_EyeCareKeys.activated}');
      final m = await _root('settings get secure ${_EyeCareKeys.autoMode}');
      final t = await _root('settings get secure ${_EyeCareKeys.colorTemp}');
      setState(() {
        _active = a.trim() == '1';
        _autoMode = int.tryParse(m.trim()) ?? 0;
        _temp = int.tryParse(t.trim()) ?? 4500;
        _loading = false;
        _error = null;
      });
    } catch (e) {
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
      await _root(
          'settings put secure ${_EyeCareKeys.activated} ${v ? 1 : 0}');
    } catch (e) {
      setState(() => _active = prev);
      _toast('Gagal mengubah Perawatan Mata: $e');
    }
  }

  Future<void> _setAutoMode(int v) async {
    final prev = _autoMode;
    setState(() => _autoMode = v);
    try {
      await _root('settings put secure ${_EyeCareKeys.autoMode} $v');
    } catch (e) {
      setState(() => _autoMode = prev);
      _toast('Gagal mengubah jadwal: $e');
    }
  }

  Future<void> _setTemp(int v) async {
    try {
      await _root('settings put secure ${_EyeCareKeys.colorTemp} $v');
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
                          style: TextStyle(color: kRed, fontSize: 10.5)),
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
        trailing:
            _autoMode == value ? Icon(Icons.check_rounded, color: kRed) : null,
        onTap: () => Navigator.pop(ctx, value),
      );
}
