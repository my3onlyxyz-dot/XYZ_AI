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
    final sysInfo = await RootService.getSystemInfo();
    final ramInfo = await RootService.getRamInfo();
    if (mounted) {
      setState(() {
        _sysInfo = sysInfo;
        _ramInfo = ramInfo;
        _isLoading = false;
        _cpuLocked = sysInfo['governor'] == 'performance';
        _bandLocked = sysInfo['band_locked'] != 'Auto';
        _esportsMode = sysInfo['thermal'] == 'esports';
        _selectedHz = int.tryParse(
              sysInfo['refresh_rate']?.replaceAll('Hz', '').trim() ?? '144',
            ) ??
            144;
      });
    }
  }

  void _showStatus(String msg) {
    setState(() => _statusMsg = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _statusMsg = '');
    });
  }

  @override
  Widget build(BuildContext context) {
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
                          IconButton(
                            onPressed: _loadInfo,
                            icon: const Icon(Icons.refresh,
                                color: Color(0xFF00E5FF)),
                          ),
                        ],
                      ),

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
                                    onTap: () async {
                                      await RootService.setRefreshRate(hz);
                                      setState(() => _selectedHz = hz);
                                      _showStatus(
                                          '✅ Refresh rate dikunci ke ${hz}Hz');
                                      _loadInfo();
                                    },
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
                        onTap: () async {
                          _showStatus('⏳ Membersihkan RAM...');
                          await RootService.clearRam();
                          await _loadInfo();
                          _showStatus('✅ RAM berhasil dibersihkan!');
                        },
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
                        onTap: () async {
                          if (_cpuLocked) {
                            await RootService.unlockPerformance();
                            _showStatus('✅ CPU dikembalikan ke schedutil');
                          } else {
                            await RootService.lockPerformance();
                            _showStatus('✅ CPU dikunci ke mode Performance');
                          }
                          await _loadInfo();
                        },
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
                        onTap: () async {
                          if (_bandLocked) {
                            await RootService.unlockBand();
                            _showStatus('✅ Band dikembalikan ke Auto');
                          } else {
                            await RootService.lockBand();
                            _showStatus('✅ Band dikunci ke B1+B3+B8 Tri');
                          }
                          await _loadInfo();
                        },
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
                        onTap: () async {
                          if (_esportsMode) {
                            await RootService.setThermalNormal();
                            _showStatus('✅ Thermal dikembalikan ke Normal');
                          } else {
                            await RootService.setThermalEsports();
                            _showStatus('✅ Mode Esports diaktifkan!');
                          }
                          await _loadInfo();
                        },
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
