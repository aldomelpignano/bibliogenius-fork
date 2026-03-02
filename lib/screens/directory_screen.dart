import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/hub_directory.dart';
import '../providers/hub_directory_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../widgets/genie_app_bar.dart';

/// Public library directory screen (ADR-015).
///
/// Shows the paginated list of libraries registered on the hub.
/// The user can follow (or request to follow) any library.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _scrollController = ScrollController();
  Set<String> _connectedPeerIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<HubDirectoryProvider>();
      provider.loadDirectory();
      provider.loadFollowing();
      provider.loadFollowers();
      provider.loadPendingRequests();
      _loadConnectedPeerIds();
    });

    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadConnectedPeerIds() async {
    try {
      final api = context.read<ApiService>();
      final resp = await api.getPeers();
      final peersData =
          ((resp.data as Map<String, dynamic>?)?['data'] as List<dynamic>?) ??
          [];
      final ids = peersData
          .map(
            (j) =>
                (j as Map<String, dynamic>)['library_uuid'] as String?,
          )
          .whereType<String>()
          .toSet();
      if (mounted) setState(() => _connectedPeerIds = ids);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<HubDirectoryProvider>().loadMoreDirectory();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'directory_title'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppDesign.radiusRound),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppDesign.radiusRound),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppDesign
                    .appBarGradientForTheme(themeProvider.themeStyle)
                    .colors
                    .first,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.85),
                labelPadding: EdgeInsets.zero,
                tabs: [
                  _PillTab(
                    icon: Icons.travel_explore,
                    label: TranslationService.translate(
                      context,
                      'directory_tab_explore',
                    ),
                  ),
                  _PillTab(
                    icon: Icons.group,
                    label: TranslationService.translate(
                      context,
                      'directory_tab_following',
                    ),
                  ),
                  Semantics(
                    label: _pendingBadgeLabel(context),
                    child: Tab(
                      child: _PendingBadgeTab(
                        label: TranslationService.translate(
                          context,
                          'directory_tab_requests',
                        ),
                        icon: Icons.mark_email_unread,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _ExploreTab(
              scrollController: _scrollController,
              connectedPeerIds: _connectedPeerIds,
            ),
            const _FollowingTab(),
            const _RequestsTab(),
          ],
        ),
      ),
    );
  }

  String _pendingBadgeLabel(BuildContext context) {
    final count = context.watch<HubDirectoryProvider>().pendingCount;
    final base = TranslationService.translate(context, 'directory_tab_requests');
    return count > 0 ? '$base ($count)' : base;
  }
}

// ---------------------------------------------------------------------------
// Tab: Explore
// ---------------------------------------------------------------------------

class _ExploreTab extends StatelessWidget {
  final ScrollController scrollController;
  final Set<String> connectedPeerIds;

  const _ExploreTab({
    required this.scrollController,
    required this.connectedPeerIds,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<HubDirectoryProvider>(
      builder: (context, provider, _) {
        if (provider.listLoading && provider.profiles.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.listError != null && provider.profiles.isEmpty) {
          return _ErrorState(
            message: provider.listError!,
            onRetry: () => provider.loadDirectory(),
          );
        }

        if (provider.profiles.isEmpty) {
          return _EmptyState(
            icon: Icons.public_off,
            message: TranslationService.translate(
              context,
              'directory_empty',
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: provider.loadDirectory,
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount:
                provider.profiles.length + (provider.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == provider.profiles.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final profile = provider.profiles[index];
              return _LibraryCard(
                profile: profile,
                isConnected: connectedPeerIds.contains(profile.nodeId),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Following
// ---------------------------------------------------------------------------

class _FollowingTab extends StatelessWidget {
  const _FollowingTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<HubDirectoryProvider>(
      builder: (context, provider, _) {
        final active = provider.following
            .where((f) => f.isActive)
            .toList();
        final pending = provider.following
            .where((f) => f.isPending)
            .toList();

        if (active.isEmpty && pending.isEmpty) {
          return _EmptyState(
            icon: Icons.group_off,
            message: TranslationService.translate(
              context,
              'directory_following_empty',
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: provider.loadFollowing,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              if (pending.isNotEmpty) ...[
                _SectionHeader(
                  TranslationService.translate(
                    context,
                    'directory_pending_outgoing',
                  ),
                ),
                ...pending.map(
                  (f) => _FollowTile(follow: f, outgoing: true),
                ),
              ],
              if (active.isNotEmpty) ...[
                _SectionHeader(
                  TranslationService.translate(
                    context,
                    'directory_active_follows',
                  ),
                ),
                ...active.map(
                  (f) => _FollowTile(follow: f, outgoing: true),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Incoming requests
// ---------------------------------------------------------------------------

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<HubDirectoryProvider>(
      builder: (context, provider, _) {
        if (provider.pendingRequests.isEmpty) {
          return _EmptyState(
            icon: Icons.how_to_reg_outlined,
            message: TranslationService.translate(
              context,
              'directory_requests_empty',
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: provider.loadPendingRequests,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: provider.pendingRequests.length,
            itemBuilder: (context, index) {
              return _IncomingRequestTile(
                follow: provider.pendingRequests[index],
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Library card (Explore tab)
// ---------------------------------------------------------------------------

class _LibraryCard extends StatelessWidget {
  final HubProfile profile;
  final bool isConnected;

  const _LibraryCard({required this.profile, this.isConnected = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HubDirectoryProvider>();
    final followStatus = provider.followStatusFor(profile.nodeId);
    final isSelf =
        provider.config?.nodeId == profile.nodeId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Semantics(
        button: true,
        label:
            '${profile.displayName}, ${profile.bookCount} ${TranslationService.translate(context, 'directory_books')}',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(
            '/directory/${Uri.encodeComponent(profile.nodeId)}',
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gradient avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: _avatarGradientFor(profile.displayName),
                    shape: BoxShape.circle,
                    boxShadow: AppDesign.subtleShadow,
                  ),
                  child: Center(
                    child: Text(
                      profile.displayName.isNotEmpty
                          ? profile.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (profile.description != null &&
                          profile.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          profile.description!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _StatChip(
                            icon: Icons.menu_book,
                            label:
                                '${profile.bookCount} ${TranslationService.translate(context, 'directory_books')}',
                          ),
                          if (profile.locationCountry != null)
                            _StatChip(
                              icon: Icons.place,
                              label: profile.locationCountry!,
                            ),
                          if (isConnected)
                            _StatChip(
                              icon: Icons.wifi,
                              label: TranslationService.translate(
                                context,
                                'directory_connected',
                              ),
                              color: Colors.green.shade700,
                            )
                          else if (profile.requiresApproval)
                            _StatChip(
                              icon: Icons.lock_outline,
                              label: TranslationService.translate(
                                context,
                                'directory_requires_approval_short',
                              ),
                              color: Colors.orange.shade700,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Follow button: hidden for self and already-connected peers
                if (!isSelf && !isConnected)
                  _FollowButton(
                    nodeId: profile.nodeId,
                    requiresApproval: profile.requiresApproval,
                    followStatus: followStatus,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Follow button
// ---------------------------------------------------------------------------

class _FollowButton extends StatelessWidget {
  final String nodeId;
  final bool requiresApproval;
  final String? followStatus;

  const _FollowButton({
    required this.nodeId,
    required this.requiresApproval,
    required this.followStatus,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HubDirectoryProvider>();

    final busy = provider.isBusy(nodeId);

    if (followStatus == 'active') {
      return OutlinedButton(
        onPressed: busy
            ? null
            : () => _confirmUnfollow(context, provider),
        child: Text(
          TranslationService.translate(context, 'directory_following'),
        ),
      );
    }

    if (followStatus == 'pending') {
      return OutlinedButton(
        onPressed: null,
        child: Text(
          TranslationService.translate(context, 'directory_pending'),
        ),
      );
    }

    // Not yet following
    return FilledButton(
      onPressed: busy
          ? null
          : () async {
              final ok = await provider.follow(nodeId);
              if (!context.mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      provider.actionError ??
                          TranslationService.translate(
                            context,
                            'directory_follow_error',
                          ),
                    ),
                  ),
                );
              }
            },
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              requiresApproval
                  ? TranslationService.translate(context, 'directory_request')
                  : TranslationService.translate(context, 'directory_follow'),
            ),
    );
  }

  void _confirmUnfollow(
    BuildContext context,
    HubDirectoryProvider provider,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'directory_unfollow_title'),
        ),
        content: Text(
          TranslationService.translate(
            context,
            'directory_unfollow_confirm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              TranslationService.translate(context, 'action_cancel'),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.unfollow(nodeId);
            },
            child: Text(
              TranslationService.translate(context, 'directory_unfollow'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Follow tile (Following tab)
// ---------------------------------------------------------------------------

class _FollowTile extends StatelessWidget {
  final HubFollow follow;
  final bool outgoing;

  const _FollowTile({required this.follow, required this.outgoing});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HubDirectoryProvider>();
    final nodeId =
        outgoing ? follow.followedNodeId : follow.followerNodeId;
    final displayName = follow.followerDisplayName ??
        provider.displayNameFor(nodeId);
    final hasName = displayName != null && displayName.isNotEmpty;
    final label = hasName ? displayName : nodeId;
    final statusLabel = follow.isPending
        ? TranslationService.translate(context, 'directory_pending')
        : TranslationService.translate(context, 'directory_following');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            label.isNotEmpty ? label[0].toUpperCase() : '?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          label,
          style: hasName
              ? const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)
              : const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        subtitle: Text(statusLabel),
        trailing: outgoing && follow.isActive
            ? IconButton(
                tooltip: TranslationService.translate(
                  context,
                  'directory_unfollow',
                ),
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: () => context
                    .read<HubDirectoryProvider>()
                    .unfollow(follow.followedNodeId),
              )
            : null,
        onTap: () => context.push(
          '/directory/${Uri.encodeComponent(nodeId)}',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Incoming request tile (Requests tab)
// ---------------------------------------------------------------------------

class _IncomingRequestTile extends StatelessWidget {
  final HubFollow follow;

  const _IncomingRequestTile({required this.follow});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<HubDirectoryProvider>();
    final displayName = follow.followerDisplayName ??
        provider.displayNameFor(follow.followerNodeId);
    final hasName = displayName != null && displayName.isNotEmpty;
    final label = hasName ? displayName : follow.followerNodeId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                label.isNotEmpty ? label[0].toUpperCase() : '?',
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: hasName
                    ? const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)
                    : const TextStyle(fontFamily: 'monospace', fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Approve
            IconButton(
              tooltip: TranslationService.translate(
                context,
                'directory_approve',
              ),
              icon: const Icon(Icons.check_circle_outline,
                  color: Colors.green),
              onPressed: () =>
                  provider.resolveFollow(follow.id, 'approve'),
            ),
            // Reject
            IconButton(
              tooltip: TranslationService.translate(
                context,
                'directory_reject',
              ),
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              onPressed: () =>
                  provider.resolveFollow(follow.id, 'reject'),
            ),
            // Block
            IconButton(
              tooltip: TranslationService.translate(
                context,
                'directory_block',
              ),
              icon: const Icon(Icons.block, color: Colors.orange),
              onPressed: () =>
                  provider.resolveFollow(follow.id, 'block'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pill tab - compact horizontal icon + label
// ---------------------------------------------------------------------------

class _PillTab extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PillTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending badge tab label
// ---------------------------------------------------------------------------

class _PendingBadgeTab extends StatelessWidget {
  final String label;
  final IconData icon;

  const _PendingBadgeTab({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<HubDirectoryProvider>().pendingCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onError,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Colors.grey[600]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
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
}

// ---------------------------------------------------------------------------
// Stat chip (book count, location, approval)
// ---------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _StatChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDesign.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar gradient helper
// ---------------------------------------------------------------------------

LinearGradient _avatarGradientFor(String name) {
  const gradients = [
    AppDesign.refinedSuccessGradient,
    AppDesign.primaryGradient,
    AppDesign.refinedWarningGradient,
    AppDesign.refinedAccentGradient,
    AppDesign.refinedOceanGradient,
    AppDesign.oceanGradient,
  ];
  final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % gradients.length;
  return gradients[idx];
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
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
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
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
}
