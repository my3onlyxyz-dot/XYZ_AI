import 'dart:io';

class RootService {
  static bool? _hasRootCache;

  /// Cek apakah device punya akses root. Hasil di-cache supaya tidak
  /// dipanggil berulang-ulang (yang bisa memicu crash kalau dipanggil
  /// terlalu sering pada device tanpa root).
  static Future<bool> hasRoot() async {
    if (_hasRootCache != null) return _hasRootCache!;
    try {
      final result = await Process.run('su', ['-c', 'id'])
          .timeout(const Duration(seconds: 3));
      _hasRootCache = result.exitCode == 0;
    } catch (_) {
      _hasRootCache = false;
    }
    return _hasRootCache!;
  }

  /// Semua command root dijalankan lewat fungsi ini. Apapun yang terjadi
  /// (binary su tidak ada, permission ditolak, timeout, dll), fungsi ini
  /// TIDAK PERNAH throw — selalu mengembalikan String, supaya UI tidak
  /// pernah crash gara-gara unhandled exception.
  static Future<String> runCommand(String command) async {
    try {
      final ok = await hasRoot();
      if (!ok) return 'NO_ROOT';
      final result = await Process.run('su', ['-c', command])
          .timeout(const Duration(seconds: 5));
      final out = result.stdout.toString().trim();
      final err = result.stderr.toString().trim();
      if (out.isEmpty && err.isNotEmpty) return 'NO_ROOT';
      return out;
    } catch (_) {
      // Mencakup ProcessException (su tidak ada), TimeoutException,
      // dan error tak terduga lainnya.
      return 'NO_ROOT';
    }
  }

  static bool isUnavailable(String value) =>
      value == 'NO_ROOT' || value.trim().isEmpty;

  // ===== REFRESH RATE =====
  static Future<String> setRefreshRate(int hz) async {
    return await runCommand(
      'settings put system peak_refresh_rate $hz && settings put system min_refresh_rate $hz',
    );
  }

  static Future<String> getRefreshRate() async {
    return await runCommand('settings get system peak_refresh_rate');
  }

  // ===== RAM =====
  static Future<String> clearRam() async {
    return await runCommand('''
      for pkg in \$(cmd package list packages -3 | cut -f2 -d:); do
        if [ "\$pkg" != "com.dts.freefiremax" ] && [ "\$pkg" != "com.mobile.legends" ]; then
          am force-stop \$pkg 2>/dev/null
        fi
      done
      echo "RAM cleared"
    ''');
  }

  static Future<Map<String, String>> getRamInfo() async {
    try {
      final total = await runCommand(
          "cat /proc/meminfo | grep MemTotal | awk '{print \$2}'");
      final available = await runCommand(
          "cat /proc/meminfo | grep MemAvailable | awk '{print \$2}'");
      final totalMB = (int.tryParse(total) ?? 0) ~/ 1024;
      final availableMB = (int.tryParse(available) ?? 0) ~/ 1024;
      if (totalMB == 0) {
        return {'total': '-', 'available': '-', 'used': '-'};
      }
      return {
        'total': '$totalMB MB',
        'available': '$availableMB MB',
        'used': '${totalMB - availableMB} MB',
      };
    } catch (_) {
      return {'total': '-', 'available': '-', 'used': '-'};
    }
  }

  // ===== CPU/GPU =====
  static Future<String> lockPerformance() async {
    return await runCommand('''
      echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
      echo performance > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
      echo performance > /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor
      echo "CPU locked to performance"
    ''');
  }

  static Future<String> unlockPerformance() async {
    return await runCommand('''
      echo schedutil > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
      echo schedutil > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
      echo schedutil > /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor
      echo "CPU restored to schedutil"
    ''');
  }

  static Future<String> getCpuGovernor() async {
    return await runCommand(
        'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor');
  }

  static Future<String> getCpuFreq() async {
    return await runCommand(
        "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq | awk '{printf \"%.0f MHz\", \$1/1000}'");
  }

  // ===== LTE BAND =====
  static Future<String> lockBand() async {
    return await runCommand('''
      echo "524288" > /data/local/tmp/bandlock.conf
      echo "AT+EPBSE=524288" > /dev/ttyC0
      echo "Band B1+B3+B8 locked"
    ''');
  }

  static Future<String> unlockBand() async {
    return await runCommand('''
      echo "0" > /data/local/tmp/bandlock.conf
      echo "AT+EPBSE=0" > /dev/ttyC0
      echo "Band unlocked (auto)"
    ''');
  }

  static Future<String> getBandStatus() async {
    return await runCommand(
        'cat /data/local/tmp/bandlock.conf 2>/dev/null || echo "0"');
  }

  // ===== THERMAL =====
  static Future<String> setThermalEsports() async {
    return await runCommand(
        'setprop persist.thermal.config esports && echo "Esports mode aktif"');
  }

  static Future<String> setThermalNormal() async {
    return await runCommand(
        'setprop persist.thermal.config default && echo "Normal mode aktif"');
  }

  static Future<String> getThermalMode() async {
    return await runCommand('getprop persist.thermal.config');
  }

  // ===== REBOOT =====
  static Future<String> rebootSystem() async {
    return await runCommand('reboot');
  }

  static Future<String> rebootRecovery() async {
    return await runCommand('reboot recovery');
  }

  static Future<String> rebootFastboot() async {
    return await runCommand('reboot bootloader');
  }

  // ===== SYSTEM INFO =====
  static Future<Map<String, String>> getSystemInfo() async {
    try {
      final rootOk = await hasRoot();
      if (!rootOk) {
        return {
          'battery': '-',
          'temp': '-',
          'cpu_freq': '-',
          'governor': '-',
          'refresh_rate': '-',
          'thermal': 'default',
          'band_locked': 'Auto',
          'root': 'false',
        };
      }

      final battery =
          await runCommand('cat /sys/class/power_supply/battery/capacity');
      final temp = await runCommand(
          "cat /sys/class/thermal/thermal_zone0/temp | awk '{printf \"%.1f°C\", \$1/1000}'");
      final cpuFreq = await getCpuFreq();
      final governor = await getCpuGovernor();
      final refreshRate = await getRefreshRate();
      final thermal = await getThermalMode();
      final band = await getBandStatus();

      return {
        'battery': isUnavailable(battery) ? '-' : '$battery%',
        'temp': isUnavailable(temp) ? '-' : temp,
        'cpu_freq': isUnavailable(cpuFreq) ? '-' : cpuFreq,
        'governor': isUnavailable(governor) ? '-' : governor,
        'refresh_rate': isUnavailable(refreshRate) ? '-' : '${refreshRate}Hz',
        'thermal': isUnavailable(thermal) ? 'default' : thermal,
        'band_locked': band == '524288' ? 'B1+B3+B8 (Tri)' : 'Auto',
        'root': 'true',
      };
    } catch (_) {
      return {
        'battery': '-',
        'temp': '-',
        'cpu_freq': '-',
        'governor': '-',
        'refresh_rate': '-',
        'thermal': 'default',
        'band_locked': 'Auto',
        'root': 'false',
      };
    }
  }
}
