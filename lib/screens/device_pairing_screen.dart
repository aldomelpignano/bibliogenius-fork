import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/device_sync_provider.dart';
import '../services/auth_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../theme/app_design.dart';

enum _PairingView { devices, showCode, enterCode }

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  _PairingView _view = _PairingView.devices;

  // Device list
  List<frb.FrbLinkedDevice> _devices = [];
  bool _isLoadingDevices = true;

  // Code generation
  String? _generatedCode;
  bool _isGenerating = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 300;

  // Code entry
  final _codeController = TextEditingController();
  bool _isPairing = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoadingDevices = true);
    try {
      final devices = await frb.deviceListLinked();
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoadingDevices = false;
        });
      }
    } catch (e) {
      debugPrint('DevicePairing: loadDevices error: $e');
      if (mounted) {
        setState(() => _isLoadingDevices = false);
      }
    }
  }

  Future<void> _generateCode() async {
    setState(() {
      _isGenerating = true;
      _view = _PairingView.showCode;
    });
    try {
      final authService = context.read<AuthService>();
      final libraryUuid = await authService.getOrCreateLibraryUuid();
      final deviceName = Platform.localHostname;

      final offer = await frb.deviceGeneratePairingOffer(
        deviceName: deviceName,
        libraryUuid: libraryUuid,
      );

      if (mounted) {
        setState(() {
          _generatedCode = offer.code;
          _isGenerating = false;
          _remainingSeconds = 300;
        });
        _startCountdown();
      }
    } catch (e) {
      debugPrint('DevicePairing: generateCode error: $e');
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _view = _PairingView.devices;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'pairing_error'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
      });
      if (_remainingSeconds <= 0) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _generatedCode = null;
            _view = _PairingView.devices;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'pairing_code_expired'),
              ),
            ),
          );
        }
      }
    });
  }

  Future<void> _acceptCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    setState(() => _isPairing = true);
    try {
      final deviceName = Platform.localHostname;

      // Fetch our crypto keys for E2EE exchange
      Uint8List ed25519Bytes = Uint8List(0);
      Uint8List x25519Bytes = Uint8List(0);
      try {
        final keysJson = await frb.getPublicKeysFfi();
        final keys = Map<String, dynamic>.from(
          const JsonDecoder().convert(keysJson) as Map,
        );
        final ed25519 = keys['ed25519'] as String?;
        final x25519 = keys['x25519'] as String?;
        if (ed25519 != null) ed25519Bytes = base64.decode(ed25519);
        if (x25519 != null) x25519Bytes = base64.decode(x25519);
      } catch (e) {
        debugPrint('DevicePairing: Could not fetch crypto keys: $e');
      }

      await frb.deviceAcceptPairing(
        code: code,
        deviceName: deviceName,
        ed25519PublicKey: ed25519Bytes,
        x25519PublicKey: x25519Bytes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'pairing_success'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _codeController.clear();
        setState(() {
          _isPairing = false;
          _view = _PairingView.devices;
        });
        _loadDevices();
      }
    } catch (e) {
      debugPrint('DevicePairing: acceptCode error: $e');
      if (mounted) {
        setState(() => _isPairing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'pairing_error')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _syncDevice(frb.FrbLinkedDevice device) async {
    final syncProvider = context.read<DeviceSyncProvider>();
    await syncProvider.triggerSync(device.id);
    if (!mounted) return;

    final result = syncProvider.lastResult;
    if (syncProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${TranslationService.translate(context, 'pairing_error')}: ${syncProvider.error}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final sent = result?.sentCount ?? 0;
    final received = result?.receivedCount ?? 0;
    final pendingReview = result?.pendingReviewCount ?? 0;

    final message = TranslationService.translate(context, 'sync_result_message')
        .replaceFirst('%d', sent.toString())
        .replaceFirst('%d', received.toString());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: pendingReview > 0
            ? SnackBarAction(
                label: TranslationService.translate(
                  context,
                  'sync_pending_review_action',
                ),
                onPressed: () => context.go('/sync-review'),
              )
            : null,
      ),
    );
  }

  Future<void> _removeDevice(frb.FrbLinkedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'pairing_remove_confirm'),
        ),
        content: Text(device.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              TranslationService.translate(context, 'delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await frb.deviceRemoveLinked(deviceId: device.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'pairing_remove_success'),
            ),
          ),
        );
        _loadDevices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'pairing_error')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelPairing() {
    _countdownTimer?.cancel();
    _codeController.clear();
    setState(() {
      _view = _PairingView.devices;
      _generatedCode = null;
      _isGenerating = false;
      _isPairing = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String title;
    switch (_view) {
      case _PairingView.devices:
        title = TranslationService.translate(context, 'pairing_title');
      case _PairingView.showCode:
        title = TranslationService.translate(context, 'pairing_code_title');
      case _PairingView.enterCode:
        title = TranslationService.translate(context, 'pairing_enter_title');
    }

    return Scaffold(
      appBar: AppBar(
        leading: _view != _PairingView.devices
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: TranslationService.translate(
                    context, 'tooltip_cancel_pairing'),
                onPressed: _cancelPairing,
              )
            : null,
        title: Semantics(header: true, child: Text(title)),
      ),
      body: AnimatedSwitcher(
        duration: AppDesign.standardDuration,
        child: _buildCurrentView(theme),
      ),
    );
  }

  Widget _buildCurrentView(ThemeData theme) {
    switch (_view) {
      case _PairingView.devices:
        return _buildDevicesView(theme);
      case _PairingView.showCode:
        return _buildShowCodeView(theme);
      case _PairingView.enterCode:
        return _buildEnterCodeView(theme);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Devices list view
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDevicesView(ThemeData theme) {
    return Column(
      key: const ValueKey('devices'),
      children: [
        Expanded(
          child: _isLoadingDevices
              ? const Center(child: CircularProgressIndicator())
              : _devices.isEmpty
                  ? _buildEmptyState(theme)
                  : RefreshIndicator(
                      onRefresh: _loadDevices,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _devices.length,
                        itemBuilder: (context, index) =>
                            _buildDeviceCard(_devices[index], theme),
                      ),
                    ),
        ),
        // Action buttons
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Tooltip(
                    message: TranslationService.translate(
                        context, 'tooltip_generate_pairing'),
                    child: FilledButton.icon(
                      onPressed: _generateCode,
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(
                        TranslationService.translate(
                            context, 'pairing_generate_code'),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppDesign.radiusMedium),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Tooltip(
                    message: TranslationService.translate(
                        context, 'tooltip_enter_pairing'),
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _view = _PairingView.enterCode),
                      icon: const Icon(Icons.keyboard),
                      label: Text(
                        TranslationService.translate(
                            context, 'pairing_enter_code'),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppDesign.radiusMedium),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.devices_other_rounded,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            TranslationService.translate(context, 'pairing_empty_title'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              TranslationService.translate(context, 'pairing_empty_subtitle'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(frb.FrbLinkedDevice device, ThemeData theme) {
    final pairedDate = _formatDate(device.createdAt ?? '');
    final pairedLabel = TranslationService.translate(context, 'pairing_paired_on')
        .replaceFirst('%s', pairedDate);

    return Semantics(
      button: true,
      label: '${device.name}, $pairedLabel',
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        ),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
            ),
            child: Icon(
              Icons.devices_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          title: Text(
            device.name,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            pairedLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.sync_rounded),
                tooltip: TranslationService.translate(
                    context, 'tooltip_sync_device'),
                onPressed: () => _syncDevice(device),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                tooltip: TranslationService.translate(
                    context, 'tooltip_remove_device'),
                onPressed: () => _removeDevice(device),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Show code view
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildShowCodeView(ThemeData theme) {
    if (_isGenerating) {
      return const Center(
        key: ValueKey('generating'),
        child: CircularProgressIndicator(),
      );
    }

    final code = _generatedCode ?? '';
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeStr =
        '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
    final progress = _remainingSeconds / 300.0;

    return SingleChildScrollView(
      key: const ValueKey('showCode'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Shield icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppDesign.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: AppDesign.glowShadow(theme.colorScheme.primary),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(
                  context, 'pairing_code_instruction'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Code display - hero element
            _buildCodeSlots(code, theme),
            const SizedBox(height: 16),
            // Copy button
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      TranslationService.translate(context, 'copied'),
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text(
                TranslationService.translate(context, 'copy'),
              ),
            ),
            const SizedBox(height: 24),
            // Countdown
            SizedBox(
              width: 200,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        _remainingSeconds < 60
                            ? Colors.red
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    TranslationService.translate(
                            context, 'pairing_code_expires')
                        .replaceFirst('%s', timeStr),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _remainingSeconds < 60
                          ? Colors.red
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            OutlinedButton(
              onPressed: _cancelPairing,
              child: Text(
                TranslationService.translate(context, 'pairing_cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeSlots(String code, ThemeData theme) {
    return Semantics(
      label:
          '${TranslationService.translate(context, 'pairing_code_title')}: ${code.split('').join(' ')}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(code.length, (i) {
            return Container(
              width: 48,
              height: 60,
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : 6,
                right: i == 2 ? 12 : 0, // visual gap after 3rd digit
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                border: Border.all(
                  color:
                      theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: Text(
                  code[i],
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Enter code view
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEnterCodeView(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey('enterCode'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Link icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppDesign.oceanGradient,
                shape: BoxShape.circle,
                boxShadow:
                    AppDesign.glowShadow(const Color(0xFF0EA5E9)),
              ),
              child: const Icon(
                Icons.link_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(
                  context, 'pairing_enter_instruction'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Code input
            SizedBox(
              width: 280,
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppDesign.radiusLarge),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 24,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _codeController.text.length == 6 && !_isPairing
                        ? _acceptCode
                        : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDesign.radiusMedium),
                  ),
                ),
                child: _isPairing
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        TranslationService.translate(
                            context, 'pairing_button_pair'),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _cancelPairing,
              child: Text(
                TranslationService.translate(context, 'pairing_cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}
