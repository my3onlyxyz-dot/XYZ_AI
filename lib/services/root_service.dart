import 'dart:io';

class RootService {
  static Future<String> runCommand(String command) async {
    try {
      final result = await Process.run('su', ['-c', command]);
      return result.stdout.toString().trim();
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ===== REFRESH RATE =====
  static Future<String> setRefreshRate(int hz) async {
    return await runCommand(
      'settings put system peak_refresh_rate $hz && settings put system min_refresh_rate $hz',
    );
  }

  static Future<String> getRefreshRate() async {
    final result = await runCommand('settings get system peak_refresh_rate');
    return result.replaceAll('.0', '');
  }

  // ===== RAM =====
  static Future<String> clearRam() async {
    return await runCommand('''
      for pkg in \$(cmd package list packages -3 | cut -f2 -d:); do
        am force-stop \$pkg 2>/dev/null
      done
      sync
      echo 3 > /proc/sys/vm/drop_caches
      echo "RAM cleared"
    ''');
  }

  static Future<Map<String, String>> getRamInfo() async {
    final total = await runCommand("cat /proc/meminfo | grep MemTotal | awk '{print \$2}'");
    final available = await runCommand("cat /proc/meminfo | grep MemAvailable | awk '{print \$2}'");
    final totalMB = (int.tryParse(total) ?? 0) ~/ 1024;
    final availableMB = (int.tryParse(available) ?? 0) ~/ 1024;
    return {
      'total': '$totalMB MB',
      'available': '$availableMB MB',
      'used': '${totalMB - availableMB} MB',
    };
  }

  // ===== CPU/GPU =====
  static Future<String> lockPerformance() async {
    return await runCommand('''
      for i in 0 1 2 3; do echo performance > /sys/devices/system/cpu/cpu\${i}/cpufreq/scaling_governor; echo 2000000 > /sys/devices/system/cpu/cpu\${i}/cpufreq/scaling_min_freq; done
      for i in 4 5 6; do echo performance > /sys/devices/system/cpu/cpu\${i}/cpufreq/scaling_governor; echo 3000000 > /sys/devices/system/cpu/cpu\${i}/cpufreq/scaling_min_freq; done
      echo performance > /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor
      echo 3100000 > /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq
      echo 3100000 > /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq
      echo 950000000 > /sys/class/devfreq/13000000.mali/min_freq
      echo 0 > /proc/mtk_scheduler/capacity_margin
      echo "CPU+GPU locked to performance"
    ''');
  }

  static Future<String> unlockPerformance() async {
    return await runCommand('''
      for i in 0 1 2 3 4 5 6 7; do echo schedutil > /sys/devices/system/cpu/cpu\${i}/cpufreq/scaling_governor; echo 500000 > /sys/devices/system/cpu/cpu\${i}/cpufreq/scaling_min_freq; done
      echo 20 > /proc/mtk_scheduler/capacity_margin
      echo "CPU restored to schedutil"
    ''');
  }

  static Future<String> getCpuGovernor() async {
    return await runCommand('cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor');
  }

  static Future<String> getCpuFreq() async {
    return await runCommand("cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq | awk '{printf \"%.0f MHz\", \$1/1000}'");
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
    return await runCommand('cat /data/local/tmp/bandlock.conf 2>/dev/null || echo "0"');
  }

  // ===== THERMAL =====
  static Future<String> setThermalEsports() async {
    return await runCommand('setprop persist.thermal.config esports && echo "Esports mode aktif"');
  }

  static Future<String> setThermalNormal() async {
    return await runCommand('setprop persist.thermal.config default && echo "Normal mode aktif"');
  }

  static Future<String> getThermalMode() async {
    return await runCommand('getprop persist.thermal.config');
  }

  // ===== SYSTEM INFO =====
  static Future<Map<String, String>> getSystemInfo() async {
    final battery = await runCommand('cat /sys/class/power_supply/battery/capacity');
    final temp = await runCommand("cat /sys/class/thermal/thermal_zone0/temp | awk '{printf \"%.1f°C\", \$1/1000}'");
    final cpuFreq = await getCpuFreq();
    final governor = await getCpuGovernor();
    final refreshRate = await getRefreshRate();
    final thermal = await getThermalMode();
    final band = await getBandStatus();

    return {
      'battery': battery.isEmpty ? 'N/A' : '$battery%',
      'temp': temp.isEmpty ? 'N/A' : temp,
      'cpu_freq': cpuFreq,
      'governor': governor,
      'refresh_rate': '${refreshRate}Hz',
      'thermal': thermal.isEmpty ? 'default' : thermal,
      'band_locked': band == '524288' ? 'B1+B3+B8 (Tri)' : 'Auto',
    };
  }
}
