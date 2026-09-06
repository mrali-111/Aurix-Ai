import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<int> getCurrentBuildNumber() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return int.parse(packageInfo.buildNumber);
  }

  static Future<AppUpdate?> checkForUpdate() async {
    try {
      final doc = await _firestore.collection('app_config').doc('app_update').get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final currentBuild = await getCurrentBuildNumber();
      final latestBuild = data['versionCode'] ?? 0;

      if (latestBuild > currentBuild) {
        return AppUpdate(
          version: data['version'] ?? '',
          versionCode: latestBuild,
          forceUpdate: data['forceUpdate'] ?? false,
          updateMessage: data['updateMessage'] ?? 'New update available!',
          whatsNew: List<String>.from(data['whatsNew'] ?? []),
          downloadUrl: data['downloadUrl'] ?? '',
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<void> showUpdateDialog(BuildContext context, AppUpdate update) async {
    return showDialog(
      context: context,
      barrierDismissible: !update.forceUpdate,
      builder: (context) => WillPopScope(
        onWillPop: () async => !update.forceUpdate,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9C27B0), Color(0xFF7C4DFF)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.browser_updated, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Update Available!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF7C4DFF), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        update.updateMessage,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                      ),
                    ),
                  ],
                ),
              ),
              if (update.whatsNew.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'What\'s New:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                ...update.whatsNew.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
              if (update.forceUpdate) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This update is required to continue using the app.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!update.forceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF888888),
                ),
                child: const Text('Later'),
              ),
            ElevatedButton(
              onPressed: () async {
                final Uri url = Uri.parse(update.downloadUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9C27B0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download, size: 18),
                  SizedBox(width: 8),
                  Text('Update Now'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppUpdate {
  final String version;
  final int versionCode;
  final bool forceUpdate;
  final String updateMessage;
  final List<String> whatsNew;
  final String downloadUrl;
  AppUpdate({
    required this.version,
    required this.versionCode,
    required this.forceUpdate,
    required this.updateMessage,
    required this.whatsNew,
    required this.downloadUrl,
  });
}