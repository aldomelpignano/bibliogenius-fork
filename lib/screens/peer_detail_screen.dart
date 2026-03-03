import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/library_relation.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/hub_directory_provider.dart';

/// Detail screen for a library peer / followed library.
class PeerDetailScreen extends StatefulWidget {
  final LibraryRelation relation;

  const PeerDetailScreen({super.key, required this.relation});

  @override
  State<PeerDetailScreen> createState() => _PeerDetailScreenState();
}

class _PeerDetailScreenState extends State<PeerDetailScreen> {
  late LibraryRelation _relation;

  @override
  void initState() {
    super.initState();
    _relation = widget.relation;
  }

  Future<void> _editDisplayName() async {
    final api = context.read<ApiService>();
    final controller = TextEditingController(text: _relation.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(ctx, 'peer_edit_display_name'),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: TranslationService.translate(
              ctx,
              'peer_display_name_label',
            ),
            hintText: TranslationService.translate(
              ctx,
              'peer_display_name_hint',
            ),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(TranslationService.translate(ctx, 'save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;

    final peer = _relation.peer;
    if (peer != null) {
      await api.updatePeerDisplayName(peer.id, newName);
    }

    if (!mounted) return;
    setState(() {
      _relation = _relation.withDisplayName(newName);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        TranslationService.translate(context, 'peer_name_saved'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final peer = _relation.peer;

    // Avatar color encodes connection type
    final Color avatarColor;
    final IconData avatarIcon;
    if (_relation.isPeer && _relation.isFollowing) {
      avatarColor = Colors.teal;
      avatarIcon = Icons.wifi;
    } else if (_relation.isPeer) {
      avatarColor = Colors.blue;
      avatarIcon = Icons.wifi;
    } else {
      avatarColor = Colors.deepPurple;
      avatarIcon = Icons.library_books;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_relation.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: TranslationService.translate(
              context,
              'peer_edit_display_name',
            ),
            onPressed: _editDisplayName,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar
          Center(
            child: Semantics(
              image: true,
              label: _relation.name,
              child: CircleAvatar(
                radius: 48,
                backgroundColor: avatarColor,
                child: Icon(avatarIcon, color: Colors.white, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _relation.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_relation.hasCustomName) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: TranslationService.translate(
                      context,
                      'peer_custom_name_indicator',
                    ),
                    child: Icon(
                      Icons.edit_note,
                      size: 18,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Node ID (truncated, copiable)
          Center(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(
                  ClipboardData(text: _relation.nodeId),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      TranslationService.translate(context, 'copied'),
                    ),
                  ),
                );
              },
              child: Semantics(
                button: true,
                label:
                    '${TranslationService.translate(context, 'peer_node_id')}: ${_relation.nodeId}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 14,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _relation.nodeId.length > 16
                          ? '${_relation.nodeId.substring(0, 8)}...${_relation.nodeId.substring(_relation.nodeId.length - 8)}'
                          : _relation.nodeId,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.copy,
                      size: 12,
                      color: colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Connection chips
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                if (_relation.isPeer)
                  Chip(
                    avatar: const Icon(Icons.wifi, size: 16),
                    label: Text(
                      TranslationService.translate(
                        context,
                        'lib_connection_peer',
                      ),
                    ),
                  ),
                if (_relation.isFollowing)
                  Chip(
                    avatar: Icon(
                      _relation.followPending
                          ? Icons.pending
                          : Icons.bookmark,
                      size: 16,
                    ),
                    label: Text(
                      _relation.followPending
                          ? TranslationService.translate(
                              context, 'lib_follow_pending')
                          : TranslationService.translate(
                              context, 'lib_follow_active'),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 32),

          // Status section
          Semantics(
            header: true,
            child: Text(
              TranslationService.translate(context, 'status'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // E2EE status
          if (peer != null)
            ListTile(
              leading: Icon(
                peer.keyExchangeDone ? Icons.lock : Icons.lock_open,
                color: peer.keyExchangeDone
                    ? Colors.green
                    : colorScheme.outline,
              ),
              title: Text(
                TranslationService.translate(context, 'peer_e2ee_status'),
              ),
              subtitle: Text(
                peer.keyExchangeDone
                    ? TranslationService.translate(
                        context, 'peer_e2ee_active')
                    : TranslationService.translate(
                        context, 'peer_e2ee_inactive'),
              ),
              contentPadding: EdgeInsets.zero,
            ),

          // Last seen
          if (peer?.lastSeen != null)
            ListTile(
              leading: Icon(Icons.access_time, color: colorScheme.outline),
              title: Text(
                TranslationService.translate(context, 'peer_last_seen'),
              ),
              subtitle: Text(peer!.lastSeen!),
              contentPadding: EdgeInsets.zero,
            ),

          // Relay
          if (peer != null && peer.hasRelayCredentials)
            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.blue),
              title: Text(
                TranslationService.translate(context, 'peer_has_relay'),
              ),
              contentPadding: EdgeInsets.zero,
            ),

          const Divider(height: 32),

          // Actions section
          Semantics(
            header: true,
            child: Text(
              TranslationService.translate(context, 'actions'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Browse catalog
          if (_relation.canBrowseCatalog) ...[
            if (_relation.isPeer && peer?.url != null)
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(
                  TranslationService.translate(context, 'browse_library'),
                ),
                onTap: () => context.push(
                  '/peers/${peer!.id}/books',
                  extra: {
                    'id': peer.id,
                    'name': _relation.name,
                    'url': peer.url,
                    'hasRelayCredentials': peer.hasRelayCredentials,
                    'nodeId': _relation.nodeId,
                  },
                ),
              )
            else if (_relation.isFollowing && _relation.follow!.isActive)
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(
                  TranslationService.translate(context, 'browse_library'),
                ),
                onTap: () => context.push(
                  '/directory/${Uri.encodeComponent(_relation.nodeId)}',
                ),
              ),
          ],

          // Sync (peers only)
          if (_relation.isPeer && peer?.url != null)
            Consumer<ApiService>(
              builder: (context, api, _) => ListTile(
                leading: const Icon(Icons.sync),
                title: Text(
                  TranslationService.translate(context, 'tooltip_sync'),
                ),
                onTap: () async {
                  await api.syncPeer(peer!.url!);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        TranslationService.translate(context, 'sync_started'),
                      ),
                    ));
                  }
                },
              ),
            ),

          // Unfollow
          if (_relation.isFollowing && !_relation.followPending)
            Consumer<HubDirectoryProvider>(
              builder: (context, dirProvider, _) => ListTile(
                leading: Icon(
                  Icons.bookmark_remove,
                  color: colorScheme.error,
                ),
                title: Text(
                  TranslationService.translate(context, 'lib_unfollow'),
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () async {
                  await dirProvider.unfollow(_relation.nodeId);
                  if (context.mounted) context.pop();
                },
              ),
            ),

          // Disconnect peer
          if (_relation.isPeer)
            Consumer<ApiService>(
              builder: (context, api, _) => ListTile(
                leading: Icon(Icons.link_off, color: colorScheme.error),
                title: Text(
                  TranslationService.translate(context, 'delete'),
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        TranslationService.translate(
                          ctx,
                          'delete_contact_title',
                        ),
                      ),
                      content: Text(
                        '${TranslationService.translate(ctx, 'confirm_delete')} '
                        '${_relation.name}?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            TranslationService.translate(ctx, 'cancel'),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            TranslationService.translate(
                              ctx,
                              'delete_contact_btn',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await api.deletePeer(peer!.id);
                    if (context.mounted) context.pop();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
