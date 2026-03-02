import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hub_directory.dart';
import '../providers/hub_directory_provider.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' show FrbCatalogEntry;
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../widgets/genie_app_bar.dart';

/// Displays a library's public catalog (list of ISBNs) fetched from the hub.
///
/// Only reachable for libraries the user actively follows (status = active).
/// Libraries with [requiresApproval] = true have encrypted catalogs on the hub;
/// the Rust layer handles decryption transparently via the shared follow key.
class LibraryCatalogScreen extends StatefulWidget {
  final String nodeId;

  const LibraryCatalogScreen({super.key, required this.nodeId});

  @override
  State<LibraryCatalogScreen> createState() => _LibraryCatalogScreenState();
}

class _LibraryCatalogScreenState extends State<LibraryCatalogScreen> {
  final FfiService _ffi = FfiService();

  HubProfile? _profile;
  List<FrbCatalogEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profileFrb = await _ffi.hubDirectoryGetProfile(widget.nodeId);
      final entries = await _ffi.hubDirectoryGetCatalog(widget.nodeId);

      if (!mounted) return;
      setState(() {
        _profile =
            profileFrb != null ? HubProfile.fromFrb(profileFrb) : null;
        _entries = entries;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final title = _profile?.displayName ??
        TranslationService.translate(context, 'directory_catalog_title');

    return Scaffold(
      appBar: GenieAppBar(title: title),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
        ),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(
                  TranslationService.translate(context, 'action_retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Check follow status - catalog only visible to active followers
    final provider = context.watch<HubDirectoryProvider>();
    final followStatus = provider.followStatusFor(widget.nodeId);

    if (followStatus == 'pending') {
      return _PendingApprovalState(nodeId: widget.nodeId);
    }

    if (followStatus == null) {
      return _NotFollowingState(
        nodeId: widget.nodeId,
        requiresApproval: _profile?.requiresApproval ?? false,
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_books_outlined,
                  size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(
                  context,
                  'directory_catalog_empty',
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_profile != null) _ProfileHeader(profile: _profile!),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Semantics(
            header: true,
            child: Text(
              '${_entries.length} ${TranslationService.translate(context, 'directory_catalog_isbn_count')}',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _entries.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 16),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final hasTitle = entry.title.isNotEmpty;
                return ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: Text(
                    hasTitle ? entry.title : entry.isbn,
                    style: hasTitle
                        ? null
                        : const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: Text(
                    entry.author ?? entry.isbn,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header strip
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final HubProfile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              profile.displayName.isNotEmpty
                  ? profile.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                ),
                if (profile.locationCountry != null)
                  Text(
                    profile.locationCountry!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${profile.bookCount}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
              Text(
                TranslationService.translate(context, 'directory_books'),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimaryContainer
                      .withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// States when catalog is not yet accessible
// ---------------------------------------------------------------------------

class _PendingApprovalState extends StatelessWidget {
  final String nodeId;

  const _PendingApprovalState({required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, size: 64, color: Colors.orange[400]),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(
                context,
                'directory_catalog_pending',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFollowingState extends StatelessWidget {
  final String nodeId;
  final bool requiresApproval;

  const _NotFollowingState({
    required this.nodeId,
    required this.requiresApproval,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<HubDirectoryProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(
                context,
                'directory_catalog_not_following',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => provider.follow(nodeId),
              icon: const Icon(Icons.add),
              label: Text(
                requiresApproval
                    ? TranslationService.translate(
                        context,
                        'directory_request',
                      )
                    : TranslationService.translate(
                        context,
                        'directory_follow',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
