import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addon_models.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
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
        ),
      ),
    );
  }

  Widget _buildSyncSetupWidget(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        tileColor: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        leading: Icon(Icons.cloud_sync, color: AppTheme.primaryGreen, size: 32),
        title: const Text('BeatBoss Sync', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Sync favourites across devices.'),
        trailing: ElevatedButton(
          onPressed: () {
            launchUrl(Uri.parse('https://beatboss-sync-addon.thevolecitor.qzz.io'));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: const Text('Setup', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
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
    final total = addonService.installedAddons.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            'Use the arrows to set fallback priority. Toggle an addon off to temporarily disable it.',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: total,
            itemBuilder: (context, index) {
              final addon = addonService.installedAddons[index];
              final isActive = addonService.activeAddonId == addon.id;
              final isEnabled = addonService.isAddonEnabled(addon.id);

              return Padding(
                key: ValueKey(addon.id),
                padding: const EdgeInsets.only(bottom: 14),
                child: _AddonCard(
                  addon: addon,
                  displayName: addonService.displayNameFor(addon),
                  isActive: isActive,
                  isEnabled: isEnabled,
                  isDark: isDark,
                  canMoveUp: index > 0,
                  canMoveDown: index < total - 1,
                  onMoveUp: () => addonService.reorderAddons(index, index - 1),
                  onMoveDown: () =>
                      addonService.reorderAddons(index, index + 1),
                  onToggleEnabled: (val) =>
                      addonService.setAddonEnabled(addon.id, val),
                  onSetActive: () => addonService.setActiveAddon(addon.id),
                  onUninstall: () =>
                      _confirmUninstall(context, addonService, addon),
                ),
              );
            },
          ),
        ),
      ],
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
  final String displayName;
  final bool isActive;
  final bool isEnabled;
  final bool isDark;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onSetActive;
  final VoidCallback onUninstall;

  const _AddonCard({
    required this.addon,
    required this.displayName,
    required this.isActive,
    required this.isEnabled,
    required this.isDark,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleEnabled,
    required this.onSetActive,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final addonService = context.read<AddonService>();
    final injectedWidget =
        addonService.getUserAddonHandler(addon.id)?.buildAddonPageWidget(context);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.6,
      child: Container(
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
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: addon.icon != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: addon.icon!.startsWith('assets/')
                                  ? Image.asset(addon.icon!, fit: BoxFit.cover)
                                  : CachedNetworkImage(
                                      imageUrl: addon.icon!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 200,
                                    ),
                            )
                          : const Icon(Icons.extension, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(right: isActive ? 124 : 64),
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
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
                                  style: TextStyle(
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
                  const SizedBox(height: 16),
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
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        res.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch.adaptive(
                          value: isEnabled,
                          activeThumbColor: AppTheme.primaryGreen,
                          onChanged: onToggleEnabled,
                        ),
                        Text(
                          isEnabled ? 'Enabled' : 'Disabled',
                          style: TextStyle(
                            fontSize: 12,
                            color: isEnabled
                                ? AppTheme.primaryGreen
                                : (isDark ? Colors.white38 : Colors.black38),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 2,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.end,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                try {
                                  final reloaded =
                                      await addonService.reloadAddon(addon.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Reloaded ${reloaded.name} (v${reloaded.version})'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Reload failed: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              tooltip: 'Reload Manifest',
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _showAddonSettingsDialog(context, addon),
                              icon: const Icon(Icons.settings_outlined,
                                  size: 20),
                              tooltip: 'Addon Settings',
                            ),
                            if (!addon.isBuiltIn)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: onUninstall,
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: Colors.red),
                                tooltip: 'Uninstall',
                              ),
                            if (isEnabled && !isActive && addon.supportsSearch)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: ElevatedButton(
                                  onPressed: onSetActive,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryGreen
                                        .withValues(alpha: isDark ? 0.2 : 0.15),
                                    foregroundColor: AppTheme.primaryGreen,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                  child: const Text('Set Active',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  tooltip: 'Move up',
                  onPressed: canMoveUp ? onMoveUp : null,
                  icon: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: canMoveUp
                        ? (isDark ? Colors.white70 : Colors.black54)
                        : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  tooltip: 'Move down',
                  onPressed: canMoveDown ? onMoveDown : null,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: canMoveDown
                        ? (isDark ? Colors.white70 : Colors.black54)
                        : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

void _showAddonSettingsDialog(BuildContext context, AddonManifest addon) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _AddonSettingsPage(addon: addon),
    ),
  );
}

class _AddonSettingsPage extends StatefulWidget {
  final AddonManifest addon;
  const _AddonSettingsPage({required this.addon});

  @override
  State<_AddonSettingsPage> createState() => _AddonSettingsPageState();
}

class _AddonSettingsPageState extends State<_AddonSettingsPage> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _nameCtrl = TextEditingController(
      text: settings.getAddonDisplayName(widget.addon.id) ?? widget.addon.name,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveDisplayName(SettingsService settings) async {
    final custom = _nameCtrl.text.trim();
    await settings.setAddonDisplayName(
      widget.addon.id,
      (custom.isEmpty || custom == widget.addon.name) ? null : custom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stored = settings.getAddonSettings(widget.addon.id);
    final noticesOn = settings.getAddonNotificationsEnabled(widget.addon.id);
    final addon = widget.addon;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Addon Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              // Addon Header Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: addon.icon != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: addon.icon!.startsWith('assets/')
                                  ? Image.asset(addon.icon!, fit: BoxFit.cover)
                                  : CachedNetworkImage(
                                      imageUrl: addon.icon!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 200,
                                    ),
                            )
                          : const Icon(Icons.extension_rounded, size: 28),
                    ),
                    const SizedBox(width: 14),
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
                          const SizedBox(height: 2),
                          Text(
                            '${addon.id}  •  v${addon.version}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _settingsGroupLabel('GENERAL', isDark),
              _settingsCard(
                isDark: isDark,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Display name',
                        helperText:
                            'Cosmetic only; does not change how the addon works.',
                        filled: true,
                        fillColor: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check_rounded),
                          tooltip: 'Save name',
                          onPressed: () => _saveDisplayName(settings),
                        ),
                      ),
                      onChanged: (_) => _saveDisplayName(settings),
                    ),
                  ),
                  if (addon.supportsNotifications) ...[
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: const Text('Notifications'),
                      subtitle:
                          const Text('Show status notices from this addon'),
                      value: noticesOn,
                      activeThumbColor: AppTheme.primaryGreen,
                      onChanged: (v) =>
                          settings.setAddonNotificationsEnabled(addon.id, v),
                    ),
                  ],
                ],
              ),

              if (addon.settings.isNotEmpty) ...[
                const SizedBox(height: 24),
                _settingsGroupLabel('CONFIGURATION', isDark),
                _settingsCard(
                  isDark: isDark,
                  children: [
                    for (var i = 0; i < addon.settings.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: isDark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      _buildSettingField(
                        field: addon.settings[i],
                        stored: stored,
                        isDark: isDark,
                        onChanged: (key, val) =>
                            settings.setAddonSetting(addon.id, key, val),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsGroupLabel(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
    );
  }

  Widget _settingsCard({required bool isDark, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

Widget _buildSettingField({
  required AddonSettingField field,
  required Map<String, dynamic> stored,
  required bool isDark,
  required Future<void> Function(String key, dynamic val) onChanged,
}) {
  final current = stored[field.key] ?? field.defaultValue;
  switch (field.type) {
    case 'toggle':
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(field.label,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: field.help != null ? Text(field.help!) : null,
        value: current == true || current?.toString() == 'true',
        activeThumbColor: AppTheme.primaryGreen,
        onChanged: (v) => onChanged(field.key, v),
      );
    case 'select':
      final value = current?.toString();
      final valid = field.options.any((o) => o.value == value)
          ? value
          : (field.options.isNotEmpty ? field.options.first.value : null);
      return Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<String>(
          initialValue: valid,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.help,
            helperMaxLines: 3,
            filled: true,
            fillColor: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            for (final opt in field.options)
              DropdownMenuItem(
                value: opt.value,
                child: Text(
                  opt.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(field.key, v);
          },
        ),
      );
    default:
      return Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          initialValue: current?.toString() ?? '',
          maxLength: field.maxLength,
          keyboardType:
              field.type == 'number' ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            helperText: field.help,
            filled: true,
            fillColor: (isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => onChanged(field.key, v),
        ),
      );
  }
}
