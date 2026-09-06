// services/update_service.dart
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateService {
  static final DatabaseReference _db =
  FirebaseDatabase.instance.ref('app_config/app_update');

  // Check for update (call on app start)
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      // Get local version
      final packageInfo = await PackageInfo.fromPlatform();

      // Get Firebase data
      final snapshot = await _db.get();

      if (!snapshot.exists) return;

      final data = snapshot.value as Map<dynamic, dynamic>;
      final latestVersion = data['latest_version']?.toString() ?? '';
      final latestBuild = int.tryParse(data['latest_build']?.toString() ?? '0') ?? 0;
      final updateUrl = data['update_url']?.toString() ?? '';

      // Check if update needed
      final needsUpdate = _compareVersions(
        currentVersion: packageInfo.version,
        currentBuild: int.tryParse(packageInfo.buildNumber) ?? 1,
        latestVersion: latestVersion,
        latestBuild: latestBuild,
      );

      if (needsUpdate) {
        // Check if user already skipped this version
        final prefs = await SharedPreferences.getInstance();
        final skippedVersion = prefs.getString('skipped_version') ?? '';

        // Show only if not skipped before
        if (skippedVersion != latestVersion) {
          _showUpdateDialog(context, updateUrl, latestVersion);
        }
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  // Version comparison
  static bool _compareVersions({
    required String currentVersion,
    required int currentBuild,
    required String latestVersion,
    required int latestBuild,
  }) {
    final current = currentVersion.split('.').map((e) => int.parse(e)).toList();
    final latest = latestVersion.split('.').map((e) => int.parse(e)).toList();

    // Compare each segment
    for (int i = 0; i < 3; i++) {
      final c = i < current.length ? current[i] : 0;
      final l = i < latest.length ? latest[i] : 0;

      if (l > c) return true;
      if (l < c) return false;
    }

    // If same version, compare build number
    return latestBuild > currentBuild;
  }

  // Show update dialog
  static void _showUpdateDialog(
      BuildContext context, String updateUrl, String latestVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFF7C4DFF)),
            SizedBox(width: 8),
            Text('New Update! 🚀'),
          ],
        ),
        content: const Text(
          'New version available! Bug fixes and improvements.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Skip: Save version to avoid showing again
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('skipped_version', latestVersion);
              Navigator.pop(ctx);
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _openUrl(updateUrl);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  // Open URL
  static Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}