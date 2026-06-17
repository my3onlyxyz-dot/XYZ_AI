import 'dart:async';
import 'package:flutter/material.dart';
import '../services/root_service.dart';
import '../widgets/info_card.dart';
import '../widgets/control_card.dart';
import '../widgets/section_title.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, String> _sysInfo = {};
  Map<String, String> _ramInfo = {};
  bool _isLoading = true;
  bool _cpuLocked = false;
  bool _bandLocked = false;
  bool _esportsMode = false;
  bool _busy = false;
  int _selectedHz = 144;
  String _statusMsg = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _loadInfo());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    try {
      final sysInfo = await RootService.getSystemInfo();
      final ramInfo = await RootService.getRamInfo();
      if (!mounted) return;
      setState(() {
        _sysInfo = sysInfo;
        _ramInfo = ramInfo;
        _isLoading = false;
        _cpuLocked = sysInfo['governor'] == 'performance';
        _bandLocked = sysInfo['band_locked'] != 'Auto';
        _esportsMode = sysInfo['thermal'] == 'esports';
        _selectedHz = int.tryParse(
              sysInfo['refresh_rate']?.replaceAll('Hz', '').trim() ?? '',
            ) ??
            _selectedHz;
      });
    } catch (_) {
      // Jangan biarkan kegagalan refresh berkala bikin crash.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStatus(String msg) {
    if (!mounted) return;
    setState(() => _statusMsg = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _statusMsg = '');
    });
  }

  /// Pembungkus aman untuk SEMUA aksi "set" (tombol).
  /// - Mencegah double-tap saat masih proses (mencegah race condition).
  /// - Menangkap semua exception supaya UI tidak pernah crash.
  /// - Mendeteksi hasil "NO_ROOT" dan menampilkan pesan ramah.
  Future<void> _runAction(Future<String> Function() action,
      {required String successMsg, String? noRootMsg}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action().timeout(const Duration(seconds: 8));
      if (RootService.isUnavailable(result)) {
        _showStatus('⚠️ ${noRootMsg ?? 'Fitur ini butuh akses root yang aktif.'}');
      } else {
        _showStatus(successMsg);
      }
      await _loadInfo();
    } catch (_) {
      _showStatus('⚠️ Gagal menjalankan aksi. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noRoot = _sysInfo['root'] == 'false';

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
              )
            : RefreshIndicator(
                onRefresh: _loadInfo,
                color: const Color(0xFF00E5FF),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.phone_android,
                              color: Color(0xFF00E5FF), size: 28),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sahrul Control',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Infinix GT 20 Pro',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF00E5FF),
                                ),
                              ),
                            ),
                          IconButton(
                            onPressed: _busy ? null : _loadInfo,
                            icon: const Icon(Icons.refresh,
                                color: Color(0xFF00E5FF)),
                          ),
                        ],
                      ),

                      // Peringatan no-root
                      if (noRoot) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFFFFD700), width: 1),
                          ),
                          child: const Text(
                            '⚠️ Akses root tidak terdeteksi. Berikan izin root lalu tekan refresh.',
                            style: TextStyle(
                                color: Color(0xFFFFD700), fontSize: 12),
                          ),
                        ),
                      ],

                      // Status message
                      if (_statusMsg.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFF00E5FF), width: 1),
                          ),
                          child: Text(
                            _statusMsg,
                            style: const TextStyle(
                                color: Color(0xFF00E5FF), fontSize: 13),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // === SYSTEM INFO ===
                      const SectionTitle(title: '📊 Info Sistem'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InfoCard(
                              icon: Icons.battery_charging_full,
                              label: 'Baterai',
                              value: _sysInfo['battery'] ?? '-',
                              color: const Color(0xFF69FF47),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InfoCard(
                              icon: Icons.thermostat,
                              label: 'Suhu CPU',
                              value: _sysInfo['temp'] ?? '-',
                              color: const Color(0xFFFF6B47),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InfoCard(
                              icon: Icons.memory,
                              label: 'RAM Terpakai',
                              value: _ramInfo['used'] ?? '-',
                              color: const Color(0xFFFFD700),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InfoCard(
                              icon: Icons.speed,
                              label: 'CPU Freq',
                              value: _sysInfo['cpu_freq'] ?? '-',
                              color: const Color(0xFF00E5FF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InfoCard(
                              icon: Icons.monitor,
                              label: 'Refresh Rate',
                              value: _sysInfo['refresh_rate'] ?? '-',
                              color: const Color(0xFFB47FFF),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InfoCard(
                              icon: Icons.signal_cellular_alt,
                              label: 'LTE Band',
                              value: _sysInfo['band_locked'] ?? '-',
                              color: const Color(0xFF47FFEC),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // === REFRESH RATE ===
                      const SectionTitle(title: '🖥️ Refresh Rate'),
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih refresh rate:',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [40, 60, 120, 144].map((hz) {
                                  final isSelected = _selectedHz == hz;
                                  return GestureDetector(
                                    onTap: _busy
                                        ? null
                                        : () => _runAction(
                                              () => RootService
                                                  .setRefreshRate(hz),
                                              successMsg:
                                                  '✅ Refresh rate dikunci ke ${hz}Hz',
                                            ),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF00E5FF)
                                            : const Color(0xFF1E1E2E),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${hz}Hz',
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.black
                                              : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // === RAM ===
                      const SectionTitle(title: '🧹 Manajemen RAM'),
                      const SizedBox(height: 10),
                      ControlCard(
                        icon: Icons.cleaning_services,
                        title: 'Bersihkan RAM',
                        subtitle:
                            'Tersedia: ${_ramInfo['available'] ?? '-'} / ${_ramInfo['total'] ?? '-'}',
                        buttonLabel: 'Bersihkan Sekarang',
                        buttonColor: const Color(0xFFFF6B47),
                        onTap: _busy
                            ? null
                            : () => _runAction(
                                  RootService.clearRam,
                                  successMsg: '✅ RAM berhasil dibersihkan!',
                                ),
                      ),

                      const SizedBox(height: 16),

                      // === CPU/GPU ===
                      const SectionTitle(title: '⚡ CPU / GPU'),
                      const SizedBox(height: 10),
                      ControlCard(
                        icon: Icons.bolt,
                        title: 'Kunci Performa CPU',
                        subtitle: _cpuLocked
                            ? '🟢 Mode: Performance (terkunci)'
                            : '⚪ Mode: ${_sysInfo['governor'] ?? 'schedutil'}',
                        buttonLabel:
                            _cpuLocked ? 'Lepas Kunci' : 'Kunci ke Performance',
                        buttonColor: _cpuLocked
                            ? const Color(0xFF69FF47)
                            : const Color(0xFFFFD700),
                        onTap: _busy
                            ? null
                            : () => _runAction(
                                  _cpuLocked
                                      ? RootService.unlockPerformance
                                      : RootService.lockPerformance,
                                  successMsg: _cpuLocked
                                      ? '✅ CPU dikembalikan ke schedutil'
                                      : '✅ CPU dikunci ke mode Performance',
                                ),
                      ),

                      const SizedBox(height: 16),

                      // === LTE BAND ===
                      const SectionTitle(title: '📶 LTE Band Lock'),
                      const SizedBox(height: 10),
                      ControlCard(
                        icon: Icons.cell_tower,
                        title: 'Lock Band Tri Indonesia',
                        subtitle: _bandLocked
                            ? '🟢 Terkunci: B1 + B3 + B8 (Tri)'
                            : '⚪ Mode: Auto (semua band)',
                        buttonLabel: _bandLocked ? 'Lepas Lock' : 'Lock B1+B3+B8',
                        buttonColor: _bandLocked
                            ? const Color(0xFF47FFEC)
                            : const Color(0xFFB47FFF),
                        onTap: _busy
                            ? null
                            : () => _runAction(
                                  _bandLocked
                                      ? RootService.unlockBand
                                      : RootService.lockBand,
                                  successMsg: _bandLocked
                                      ? '✅ Band dikembalikan ke Auto'
                                      : '✅ Band dikunci ke B1+B3+B8 Tri',
                                  noRootMsg:
                                      'Lock band butuh dukungan modem khusus & root aktif.',
                                ),
                      ),

                      const SizedBox(height: 16),

                      // === THERMAL ===
                      const SectionTitle(title: '🌡️ Mode Thermal'),
                      const SizedBox(height: 10),
                      ControlCard(
                        icon: Icons.sports_esports,
                        title: 'Mode Esports (Gaming)',
                        subtitle: _esportsMode
                            ? '🟢 Aktif: Thermal dibuka untuk gaming'
                            : '⚪ Aktif: Mode Normal',
                        buttonLabel:
                            _esportsMode ? 'Kembali Normal' : 'Aktifkan Esports',
                        buttonColor: _esportsMode
                            ? const Color(0xFF69FF47)
                            : const Color(0xFFFF6B47),
                        onTap: _busy
                            ? null
                            : () => _runAction(
                                  _esportsMode
                                      ? RootService.setThermalNormal
                                      : RootService.setThermalEsports,
                                  successMsg: _esportsMode
                                      ? '✅ Thermal dikembalikan ke Normal'
                                      : '✅ Mode Esports diaktifkan!',
                                  noRootMsg:
                                      'Thermal profile ini tidak didukung di ROM kamu.',
                                ),
                      ),

                      const SizedBox(height: 16),

                      // === REBOOT ===
                      const SectionTitle(title: '🔁 Reboot Perangkat'),
                      const SizedBox(height: 10),
                      ControlCard(
                        icon: Icons.restart_alt,
                        title: 'Reboot Device',
                        subtitle: 'Pilih mode: System / Recovery / Fastboot',
                        buttonLabel: 'Reboot',
                        buttonColor: const Color(0xFFFF4747),
                        onTap: _busy ? null : _showRebootMenu,
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _showRebootMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12121A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Pilih Mode Reboot',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _rebootOption(
                  ctx,
                  icon: Icons.restart_alt,
                  color: const Color(0xFF00E5FF),
                  label: 'Reboot System',
                  desc: 'Restart normal seperti biasa',
                  onConfirm: () => _runAction(
                    RootService.rebootSystem,
                    successMsg: '✅ Perangkat akan restart...',
                    noRootMsg: 'Gagal reboot. Pastikan root aktif.',
                  ),
                ),
                _rebootOption(
                  ctx,
                  icon: Icons.build_circle_outlined,
                  color: const Color(0xFFFFD700),
                  label: 'Reboot Recovery',
                  desc: 'Masuk ke mode recovery',
                  onConfirm: () => _runAction(
                    RootService.rebootRecovery,
                    successMsg: '✅ Masuk ke Recovery...',
                    noRootMsg: 'Gagal reboot. Pastikan root aktif.',
                  ),
                ),
                _rebootOption(
                  ctx,
                  icon: Icons.usb,
                  color: const Color(0xFFB47FFF),
                  label: 'Reboot Fastboot',
                  desc: 'Masuk ke mode fastboot/bootloader',
                  onConfirm: () => _runAction(
                    RootService.rebootFastboot,
                    successMsg: '✅ Masuk ke Fastboot...',
                    noRootMsg: 'Gagal reboot. Pastikan root aktif.',
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rebootOption(
    BuildContext sheetCtx, {
    required IconData icon,
    required Color color,
    required String label,
    required String desc,
    required VoidCallback onConfirm,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        desc,
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
      ),
      onTap: () {
        Navigator.pop(sheetCtx);
        _confirmReboot(label, onConfirm);
      },
    );
  }

  void _confirmReboot(String label, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12121A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi', style: TextStyle(color: Colors.white)),
        content: Text(
          'Yakin ingin menjalankan "$label"? Perangkat akan restart sekarang.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4747),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Ya, Reboot'),
          ),
        ],
      ),
    );
  }
}
