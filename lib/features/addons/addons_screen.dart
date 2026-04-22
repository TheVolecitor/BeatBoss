import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addon_models.dart';
import '../../core/services/addon_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'addon_install_dialog.dart';

class AddonsScreen extends StatelessWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final addonService = context.watch<AddonService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Addons'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Install Addon',
            onPressed: () => AddonInstallDialog.show(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!addonService.installedAddons.any((a) => a.id == 'io.thevolecitor.beatboss-sync'))
            _buildSyncSetupWidget(context, isDark),
          Expanded(
            child: addonService.installedAddons.isEmpty
                ? _buildEmptyState(context, isDark)
                : _buildAddonsList(context, addonService, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSetupWidget(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryGreen, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_sync, color: AppTheme.primaryGreen, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BeatBoss Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Sync favourites across devices.', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              launchUrl(Uri.parse('https://beatboss-sync-addon.thevolecitor.qzz.io'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Setup', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.extension_off,
              size: 64, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 16),
          Text(
            'No addons installed',
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.white54 : Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => AddonInstallDialog.show(context),
            icon: const Icon(Icons.add),
            label: const Text('Install Addon'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddonsList(
      BuildContext context, AddonService addonService, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: addonService.installedAddons.length,
      itemBuilder: (context, index) {
        final addon = addonService.installedAddons[index];
        final isActive = addonService.activeAddonId == addon.id;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _AddonCard(
            addon: addon,
            isActive: isActive,
            isDark: isDark,
            onSetActive: () => addonService.setActiveAddon(addon.id),
            onUninstall: () => _confirmUninstall(context, addonService, addon),
          ),
        );
      },
    );
  }

  Future<void> _confirmUninstall(
      BuildContext context, AddonService addonService, AddonManifest addon) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uninstall Addon'),
        content: Text('Are you sure you want to uninstall ${addon.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await addonService.uninstallAddon(addon.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }
  }
}

class _AddonCard extends StatelessWidget {
  final AddonManifest addon;
  final bool isActive;
  final bool isDark;
  final VoidCallback onSetActive;
  final VoidCallback onUninstall;

  const _AddonCard({
    required this.addon,
    required this.isActive,
    required this.isDark,
    required this.onSetActive,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final addonService = context.read<AddonService>();
    final injectedWidget =
        addonService.getUserAddonHandler(addon.id)?.buildAddonPageWidget(context);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive 
              ? AppTheme.primaryGreen 
              : (isDark ? Colors.white10 : Colors.black12),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: const Center(
                child: Text(
                  'ACTIVE SEARCH PROVIDER',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: addon.icon != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(addon.icon!, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.extension, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            addon.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  addon.addonTypeLabel,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryGreen),
                                ),
                              ),
                              if (addon.supportsSync) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'LIBRARY',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Text(
                                'v${addon.version}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (addon.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    addon.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: addon.resources.map((res) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        res.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
                
                // Injected UI from UserAddonHandler (e.g. DAB login)
                if (injectedWidget != null) ...[
                  const SizedBox(height: 16),
                  injectedWidget,
                ],
                
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!addon.isBuiltIn)
                      TextButton.icon(
                        onPressed: onUninstall,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Uninstall'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    const SizedBox(width: 8),
                    if (!isActive && addon.supportsSearch)
                      ElevatedButton(
                        onPressed: onSetActive,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white10 : Colors.black12,
                          foregroundColor: isDark ? Colors.white : Colors.black,
                          elevation: 0,
                        ),
                        child: const Text('Set Active'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
