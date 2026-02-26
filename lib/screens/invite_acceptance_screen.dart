import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';

/// Screen shown when the user opens an invite link (deep link or QR).
/// Displays the inviting library name and lets the user accept or decline.
class InviteAcceptanceScreen extends StatefulWidget {
  final Map<String, dynamic> payload;

  const InviteAcceptanceScreen({super.key, required this.payload});

  @override
  State<InviteAcceptanceScreen> createState() => _InviteAcceptanceScreenState();
}

class _InviteAcceptanceScreenState extends State<InviteAcceptanceScreen> {
  bool _isConnecting = false;
  String? _error;

  String get _libraryName =>
      widget.payload['name'] as String? ?? 'BiblioGenius';
  String? get _url {
    final raw = widget.payload['url'] as String?;
    if (raw == null || raw.isEmpty) return null;
    // Ensure scheme is present so Dio can parse the URL
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      return 'http://$raw';
    }
    return raw;
  }
  String? get _ed25519Key =>
      widget.payload['ed25519_public_key'] as String?;
  String? get _x25519Key =>
      widget.payload['x25519_public_key'] as String?;
  String? get _relayUrl => widget.payload['relay_url'] as String?;
  String? get _mailboxId => widget.payload['mailbox_id'] as String?;
  String? get _relayWriteToken =>
      widget.payload['relay_write_token'] as String?;

  Future<void> _acceptInvite() async {
    if (_url == null || _url!.isEmpty) {
      setState(() => _error = 'Invalid invite: missing URL');
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final api = context.read<ApiService>();

    try {
      // Block self-connection: compare E2EE public keys
      final configRes = await api.getLibraryConfig();
      final myEd25519 = configRes.data['ed25519_public_key'] as String?;
      final inviteEd25519 = widget.payload['ed25519_public_key'] as String?;
      if (myEd25519 != null &&
          inviteEd25519 != null &&
          myEd25519 == inviteEd25519) {
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
          _error = TranslationService.translate(context, 'invite_self_error');
        });
        return;
      }

      final response = await api.connectPeer(
        _libraryName,
        _url!,
        ed25519PublicKey: _ed25519Key,
        x25519PublicKey: _x25519Key,
        relayUrl: _relayUrl,
        mailboxId: _mailboxId,
        relayWriteToken: _relayWriteToken,
      );

      // connectLocalPeer returns error responses instead of throwing
      if (response.statusCode != null && response.statusCode! >= 400) {
        final errorMsg = response.data is Map
            ? response.data['error'] ?? 'Connection failed'
            : response.data?.toString() ?? 'Connection failed';
        throw Exception(errorMsg);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${TranslationService.translate(context, 'invite_success')} $_libraryName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      context.go('/network');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Library icon
                  Semantics(
                    image: true,
                    label: TranslationService.translate(
                        context, 'invite_library_icon'),
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.local_library_rounded,
                        size: 44,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // "Invitation from" label
                  Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(context, 'invite_title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Library name
                  Text(
                    _libraryName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Description
                  Text(
                    TranslationService.translate(context, 'invite_description'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Connection info badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      if (_ed25519Key != null)
                        _buildBadge(
                          context,
                          Icons.lock_rounded,
                          TranslationService.translate(
                              context, 'invite_encrypted'),
                        ),
                      if (_relayUrl != null)
                        _buildBadge(
                          context,
                          Icons.cloud_rounded,
                          TranslationService.translate(
                              context, 'invite_remote_ready'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Error message
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 20,
                                color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Connect button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isConnecting ? null : _acceptInvite,
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.handshake_rounded),
                      label: Text(
                        _isConnecting
                            ? TranslationService.translate(
                                context, 'invite_connecting')
                            : TranslationService.translate(
                                context, 'invite_connect'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Decline button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed:
                          _isConnecting ? null : () => context.go('/books'),
                      child: Text(
                        TranslationService.translate(
                            context, 'invite_decline'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
