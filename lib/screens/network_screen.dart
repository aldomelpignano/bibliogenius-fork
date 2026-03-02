import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_design.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/contextual_help_sheet.dart';
import '../widgets/invite_share_sheet.dart';
import '../utils/invite_payload.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import '../models/network_member.dart';
import '../models/library_relation.dart';
import '../data/repositories/contact_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/mdns_service.dart';
import '../providers/pending_peers_provider.dart';
import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'borrow_requests_screen.dart';

/// Unified screen displaying Contacts, Libraries, and Loans tabs
class NetworkScreen extends StatefulWidget {
  final int initialIndex;

  /// Initial sub-tab for LoansScreen: 'requests', 'lent', or 'borrowed'
  final String? initialLoansTab;

  const NetworkScreen({super.key, this.initialIndex = 0, this.initialLoansTab});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;
  final GlobalKey<_ContactsListViewState> _contactsListKey =
      GlobalKey<_ContactsListViewState>();
  final GlobalKey<_LibrariesListViewState> _librariesListKey =
      GlobalKey<_LibrariesListViewState>();

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
    _mainTabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _mainTabController.removeListener(() => setState(() {}));
    _mainTabController.dispose();
    super.dispose();
  }

  /// Shows the modal bottom sheet for adding a new connection
  void _showAddConnectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  TranslationService.translate(context, 'add_connection_title'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('actionEnterManually'),
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade100,
                  child: Icon(Icons.edit, color: Colors.orange.shade700),
                ),
                title: Text(
                  TranslationService.translate(context, 'enter_manually'),
                ),
                subtitle: Text(
                  TranslationService.translate(context, 'type_contact_details'),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final result = await context.push('/contacts/add');
                  if (result == true) {
                    _contactsListKey.currentState?.reloadMembers();
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('actionScanQr'),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.qr_code_scanner, color: Colors.blue.shade700),
                ),
                title: Text(
                  TranslationService.translate(context, 'scan_qr_code'),
                ),
                subtitle: Text(
                  TranslationService.translate(context, 'scan_friend_qr_code'),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final result = await context.push('/scan-qr');
                  if (result == true) {
                    _contactsListKey.currentState?.reloadMembers();
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('actionShowMyCode'),
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade100,
                  child: Icon(Icons.qr_code, color: Colors.purple.shade700),
                ),
                title: Text(
                  TranslationService.translate(context, 'show_my_code'),
                ),
                subtitle: Text(
                  TranslationService.translate(
                    context,
                    'let_someone_scan_your_library',
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      key: const Key('showMyCodeDialog'),
                      title: Text(
                        TranslationService.translate(context, 'show_my_code'),
                      ),
                      content: const ShareContactView(),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(
                            TranslationService.translate(context, 'close'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('actionBrowseDirectory'),
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade100,
                  child: Icon(Icons.travel_explore, color: Colors.teal.shade700),
                ),
                title: Text(
                  TranslationService.translate(context, 'directory_title'),
                ),
                subtitle: Text(
                  TranslationService.translate(context, 'directory_browse_subtitle'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/directory');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'nav_network'),
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                tooltip: TranslationService.translate(context, 'tooltip_open_menu'),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        actions: [
          ContextualHelpIconButton(
            titleKey: 'help_ctx_network_title',
            contentKey: 'help_ctx_network_content',
            tips: const [
              HelpTip(
                icon: Icons.person_add,
                color: Colors.blue,
                titleKey: 'help_ctx_network_tip_add',
                descriptionKey: 'help_ctx_network_tip_add_desc',
              ),
              HelpTip(
                icon: Icons.library_books,
                color: Colors.green,
                titleKey: 'help_ctx_network_tip_browse',
                descriptionKey: 'help_ctx_network_tip_browse_desc',
              ),
              HelpTip(
                icon: Icons.bookmark_add,
                color: Colors.orange,
                titleKey: 'help_ctx_network_tip_request',
                descriptionKey: 'help_ctx_network_tip_request_desc',
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _mainTabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: TranslationService.translate(context, 'contacts')),
            Tab(text: TranslationService.translate(context, 'tab_libraries')),
            Tab(text: TranslationService.translate(context, 'loans_and_borrowings')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          ContactsListView(key: _contactsListKey),
          LibrariesListView(key: _librariesListKey),
          LoansScreen(isTabView: true, initialTab: widget.initialLoansTab),
        ],
      ),
      // Hide FAB on Loans tab
      floatingActionButton: _mainTabController.index == 2
          ? null
          : FloatingActionButton(
              key: const Key('networkAddFab'),
              heroTag: 'network_add_fab',
              onPressed: () => _showAddConnectionSheet(context),
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// The actual list of contacts/peers
class ContactsListView extends StatefulWidget {
  const ContactsListView({super.key});

  @override
  State<ContactsListView> createState() => _ContactsListViewState();
}

class _ContactsListViewState extends State<ContactsListView> {
  List<NetworkMember> _members = []; // borrowers only
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllMembers();
  }

  void reloadMembers() {
    _loadAllMembers();
  }

  Future<void> _pullToRefresh() async {
    await _loadAllMembers();
  }

  Future<void> _loadAllMembers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final contactRepo = Provider.of<ContactRepository>(context, listen: false);
      final libraryId = await authService.getLibraryId() ?? 1;
      final contactsList = await contactRepo.getContacts(libraryId: libraryId);
      final borrowers = contactsList
          .map((c) => NetworkMember.fromContact(c))
          .where((m) => m.type == NetworkMemberType.borrower)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() { _members = borrowers; _isLoading = false; });
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteContact(NetworkMember member) async {
    final contactRepo = Provider.of<ContactRepository>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'delete_contact_title')),
        content: Text(
          '${TranslationService.translate(context, 'confirm_delete')} ${member.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'delete_contact_btn')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await contactRepo.deleteContact(member.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(TranslationService.translate(context, 'contact_deleted')),
          ));
          _loadAllMembers();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InviteBanner(onTap: () => showInviteShareSheet(context)),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _pullToRefresh,
                  child: _members.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [_buildEmptyState(context)],
                        )
                      : ListView.builder(
                          key: const Key('networkMemberList'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _members.length,
                          itemBuilder: (context, i) =>
                              _buildBorrowerTile(_members[i]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildBorrowerTile(NetworkMember member) {
    return Card(
      key: Key('memberTile_${member.id}'),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(member.displayName),
        subtitle: Text(
          member.email ??
              TranslationService.translate(context, 'contact_type_borrower'),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          tooltip: TranslationService.translate(context, 'delete'),
          onPressed: () => _deleteContact(member),
        ),
        onTap: () => context.push(
          '/contacts/${member.id}?isNetwork=false',
          extra: member.toContact(),
        ),
      ),
    );
  }


  Widget _buildEmptyState(BuildContext context) {
    return Center(
      key: const Key('networkEmptyState'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline,
                size: 64,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'no_contacts_title'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, 'no_contacts_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // Primary Button: Add First Contact
            ElevatedButton.icon(
              key: const Key('addFirstContactBtn'),
              onPressed: () {
                final networkScreenState = context
                    .findAncestorStateOfType<_NetworkScreenState>();
                if (networkScreenState != null) {
                  networkScreenState._showAddConnectionSheet(context);
                }
              },
              icon: const Icon(Icons.person_add),
              label: Text(
                TranslationService.translate(context, 'add_first_contact'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Share invite link button
            OutlinedButton.icon(
              key: const Key('shareInviteEmptyStateBtn'),
              onPressed: () => showInviteShareSheet(context),
              icon: const Icon(Icons.share, size: 20),
              label: Text(
                TranslationService.translate(
                    context, 'share_invite_empty_state'),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Secondary Button: QR Code Help
            TextButton.icon(
              onPressed: () => _showQrHelpDialog(context),
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: Text(
                TranslationService.translate(context, 'how_to_add_contact_qr'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Tertiary Button: Show My Code Help
            TextButton.icon(
              onPressed: () => _showShowCodeHelpDialog(context),
              icon: const Icon(Icons.qr_code, size: 20),
              label: Text(
                TranslationService.translate(context, 'how_to_show_code_label'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQrHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('qrHelpDialog'),
        title: Row(
          children: [
            const Icon(Icons.qr_code_2, color: Colors.blue),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                TranslationService.translate(
                  context,
                  'how_to_add_contact_help_title',
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TranslationService.translate(
                context,
                'how_to_add_contact_help_desc',
              ),
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            _buildComparisonRow(
              context,
              icon: Icons.wifi,
              color: Colors.blue,
              label: TranslationService.translate(context, 'status_active'),
              description: TranslationService.translate(context, 'active_explanation'),
            ),
            const SizedBox(height: 10),
            _buildComparisonRow(
              context,
              icon: Icons.link,
              color: Colors.green,
              label: TranslationService.translate(context, 'status_connected'),
              description: TranslationService.translate(context, 'connected_explanation'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(TranslationService.translate(context, 'understood')),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color,
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showShowCodeHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('showCodeHelpDialog'),
        title: Row(
          children: [
            const Icon(Icons.qr_code, color: Colors.purple),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                TranslationService.translate(
                  context,
                  'how_to_show_code_help_title',
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TranslationService.translate(
                context,
                'how_to_show_code_help_desc',
              ),
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Icon(
                Icons.qr_code,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(TranslationService.translate(context, 'understood')),
          ),
        ],
      ),
    );
  }

}

/// View for Sharing Code (extracted from original state)
class ShareContactView extends StatefulWidget {
  const ShareContactView({super.key});

  @override
  State<ShareContactView> createState() => _ShareContactViewState();
}

class _ShareContactViewState extends State<ShareContactView> {
  String? _qrData;
  String? _inviteLink;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('📱 [QR] ShareContactView.initState()');
    _initQRData();
  }

  Future<void> _initQRData() async {
    debugPrint('📱 [QR] _initQRData() START');
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      debugPrint('📱 [QR] Got ApiService OK');

      // Use the same multi-strategy IP resolution as mDNS/peer handshake
      String? localIp;
      try {
        final info = NetworkInfo();
        final wifiIp = await info.getWifiIP();
        debugPrint('📱 [QR] NetworkInfo.getWifiIP() = $wifiIp');
        if (wifiIp != null && !wifiIp.startsWith('169.254.')) {
          localIp = wifiIp;
        }
      } catch (e) {
        debugPrint('📱 [QR] NetworkInfo error: $e');
      }
      localIp ??= await MdnsService.getValidLanIp();
      debugPrint('📱 [QR] Final localIp = $localIp');

      if (localIp == null) {
        debugPrint('⚠️ QR: No valid LAN IP found for QR code');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final configRes = await apiService.getLibraryConfig();
      String libraryName = configRes.data['library_name'] ?? 'My Library';
      final libraryUuid = configRes.data['library_uuid'] as String?;
      final ed25519Key = configRes.data['ed25519_public_key'] as String?;
      final x25519Key = configRes.data['x25519_public_key'] as String?;
      final relayUrl = configRes.data['relay_url'] as String?;
      final mailboxId = configRes.data['mailbox_id'] as String?;
      final relayWriteToken = configRes.data['relay_write_token'] as String?;
      debugPrint('📱 [QR] libraryName=$libraryName, hasKeys=${ed25519Key != null}, hasRelay=${relayUrl != null}');

      final data = buildInvitePayload(
        name: libraryName,
        url: "http://$localIp:${ApiService.httpPort}",
        libraryUuid: libraryUuid,
        ed25519PublicKey: ed25519Key,
        x25519PublicKey: x25519Key,
        relayUrl: relayUrl,
        mailboxId: mailboxId,
        relayWriteToken: relayWriteToken,
      );
      // Precalculate the short invite link (async, falls back to long format)
      final link = await createInviteLink(data, hubBaseUrl: ApiService.hubUrl);
      if (mounted) {
        setState(() {
          _qrData = jsonEncode(data);
          _inviteLink = link;
          _isLoading = false;
        });
        debugPrint('📱 [QR] QR data ready: $_qrData');
      }
    } catch (e, stack) {
      debugPrint('📱 [QR] ERROR in _initQRData: $e');
      debugPrint('📱 [QR] Stack: $stack');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('📱 [QR] build() — isLoading=$_isLoading, qrData=${_qrData != null}');
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_qrData != null) ...[
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TranslationService.translate(context, 'show_code_explanation'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // QR code
          SizedBox(
            width: 200,
            height: 200,
            child: QrImageView(
              key: const Key('myQrCode'),
              data: _qrData!,
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
          const SizedBox(height: 16),
          // Numbered steps
          _buildStep(context, 1, TranslationService.translate(context, 'show_code_step_1')),
          const SizedBox(height: 8),
          _buildStep(context, 2, TranslationService.translate(context, 'show_code_step_2')),
          const SizedBox(height: 8),
          _buildStep(context, 3, TranslationService.translate(context, 'show_code_step_3')),
          const SizedBox(height: 16),
          // Copy + Share invite link buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('copyInviteLinkBtn'),
                onPressed: _inviteLink == null ? null : () {
                  Clipboard.setData(ClipboardData(text: _inviteLink!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TranslationService.translate(
                            context, 'invite_link_copied'),
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.content_copy, size: 18),
                label: Text(
                  TranslationService.translate(context, 'copy_invite_link'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('shareInviteLinkBtn'),
                onPressed: _inviteLink == null ? null : () {
                  Share.share(_inviteLink!);
                },
                icon: const Icon(Icons.share, size: 18),
                label: Text(
                  TranslationService.translate(context, 'share_invite_link'),
                ),
              ),
            ],
          ),
        ] else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  TranslationService.translate(context, 'qr_error'),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  TranslationService.translate(context, 'qr_wifi_suggestion'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStep(BuildContext context, int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pending connections banner - compact, branded
// ---------------------------------------------------------------------------

class _PendingBanner extends StatelessWidget {
  final int count;
  final VoidCallback onAction;

  const _PendingBanner({required this.count, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1A05) : const Color(0xFFFFFBEB);
    final border = isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A);
    final textColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
    final subtleText = isDark ? const Color(0xFFD97706) : const Color(0xFFB45309);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        border: Border.all(color: border),
        boxShadow: AppDesign.subtleShadow,
      ),
      child: Row(
        children: [
          // Left accent bar
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppDesign.warningGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppDesign.radiusMedium),
                bottomLeft: Radius.circular(AppDesign.radiusMedium),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Count badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: AppDesign.warningGradient,
              shape: BoxShape.circle,
              boxShadow: AppDesign.glowShadow(const Color(0xFFF59E0B)),
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              TranslationService.translate(context, 'pending_connections_banner')
                  .replaceAll('{count}', '$count'),
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: subtleText,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              TranslationService.translate(context, 'review_connections'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared banner template - used by directory + invite banners
// ---------------------------------------------------------------------------

class _ActionBanner extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final LinearGradient iconGradient;
  final Color bgLight;
  final Color bgDark;
  final Color borderLight;
  final Color borderDark;
  final Color titleLight;
  final Color titleDark;
  final Color subtitleLight;
  final Color subtitleDark;
  final IconData trailingIcon;

  const _ActionBanner({
    required this.onTap,
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.iconGradient,
    required this.bgLight,
    required this.bgDark,
    required this.borderLight,
    required this.borderDark,
    required this.titleLight,
    required this.titleDark,
    required this.subtitleLight,
    required this.subtitleDark,
    this.trailingIcon = Icons.arrow_forward_ios,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? bgDark : bgLight;
    final border = isDark ? borderDark : borderLight;
    final titleColor = isDark ? titleDark : titleLight;
    final subtitleColor = isDark ? subtitleDark : subtitleLight;

    return Semantics(
      button: true,
      label: TranslationService.translate(context, titleKey),
      child: ScaleOnTap(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            border: Border.all(color: border),
            boxShadow: AppDesign.subtleShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: iconGradient,
                  borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
                  boxShadow: AppDesign.glowShadow(iconGradient.colors.first),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(context, titleKey),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      TranslationService.translate(context, subtitleKey),
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                    ),
                  ],
                ),
              ),
              Icon(trailingIcon, size: 13, color: subtitleColor),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Directory discovery banner (indigo)
// ---------------------------------------------------------------------------

class _DirectoryBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _DirectoryBanner({required this.onTap});

  @override
  Widget build(BuildContext context) => _ActionBanner(
        onTap: onTap,
        icon: Icons.travel_explore,
        titleKey: 'directory_title',
        subtitleKey: 'directory_browse_subtitle',
        iconGradient: AppDesign.primaryGradient,
        bgLight: const Color(0xFFEEF2FF),
        bgDark: const Color(0xFF1A1833),
        borderLight: const Color(0xFFC7D2FE),
        borderDark: const Color(0xFF3730A3),
        titleLight: const Color(0xFF3730A3),
        titleDark: const Color(0xFFA5B4FC),
        subtitleLight: const Color(0xFF6366F1),
        subtitleDark: const Color(0xFF818CF8),
      );
}

// ---------------------------------------------------------------------------
// Invite banner (teal)
// ---------------------------------------------------------------------------

class _InviteBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _InviteBanner({required this.onTap});

  @override
  Widget build(BuildContext context) => _ActionBanner(
        onTap: onTap,
        icon: Icons.person_add,
        titleKey: 'invite_card_title',
        subtitleKey: 'invite_card_subtitle',
        iconGradient: AppDesign.refinedSuccessGradient,
        bgLight: const Color(0xFFE6F4F2),
        bgDark: const Color(0xFF0D2020),
        borderLight: const Color(0xFFB2D8D4),
        borderDark: const Color(0xFF1B4D47),
        titleLight: const Color(0xFF1A4E48),
        titleDark: const Color(0xFF80CBC4),
        subtitleLight: const Color(0xFF2E7D72),
        subtitleDark: const Color(0xFF4DB6AC),
        trailingIcon: Icons.share,
      );
}

// ---------------------------------------------------------------------------
// Libraries tab - unified view of peers + hub follows
// ---------------------------------------------------------------------------

/// Unified list of remote libraries (P2P peers + hub follows), deduplicated
/// by library_uuid / node_id.
class LibrariesListView extends StatefulWidget {
  const LibrariesListView({super.key});

  @override
  State<LibrariesListView> createState() => _LibrariesListViewState();
}

class _LibrariesListViewState extends State<LibrariesListView> {
  List<LibraryRelation> _relations = [];
  /// mDNS-discovered peers not yet saved to the DB (no overlap with _relations)
  List<DiscoveredPeer> _localPeers = [];
  bool _isLoading = true;
  LibraryFilter _filter = LibraryFilter.all;

  @override
  void initState() {
    super.initState();
    _loadLibraries();
  }

  Future<void> _loadLibraries() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final dirProvider =
          Provider.of<HubDirectoryProvider>(context, listen: false);

      // Load saved P2P peers and hub follows concurrently
      final peersResFuture = api.getPeers();
      final followsFuture = dirProvider.loadFollowing();
      final peersRes = await peersResFuture;
      await followsFuture;

      final peersData =
          ((peersRes.data as Map<String, dynamic>?)?['data'] as List<dynamic>?) ?? [];
      final peers = peersData
          .map((j) => NetworkMember.fromPeer(j as Map<String, dynamic>))
          .toList();
      final follows = dirProvider.following;

      // Merge saved peers + follows by library_uuid / node_id
      final Map<String, LibraryRelation> map = {};
      for (final peer in peers) {
        final nodeId = peer.libraryUuid ?? 'peer_${peer.id}';
        map[nodeId] = LibraryRelation(nodeId: nodeId, peer: peer);
      }
      for (final follow in follows) {
        final nodeId = follow.followedNodeId;
        final existing = map[nodeId];
        if (existing != null) {
          map[nodeId] = existing.withFollow(follow);
        } else {
          map[nodeId] = LibraryRelation(nodeId: nodeId, follow: follow);
        }
      }

      final relations = map.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // mDNS peers not yet saved - exclude those already in the saved list.
      // Match by: 1) libraryId (UUID), 2) host/IP.
      final savedUuids = peers
          .map((p) => p.libraryUuid)
          .whereType<String>()
          .toSet();
      final savedHosts = peers
          .map((p) {
            if (p.url == null) return null;
            try {
              return Uri.parse(p.url!).host;
            } catch (_) {
              return null;
            }
          })
          .whereType<String>()
          .toSet();
      final localPeers = MdnsService.peers
          .where((p) {
            if (p.libraryId != null && savedUuids.contains(p.libraryId)) {
              return false;
            }
            if (savedHosts.contains(p.host)) return false;
            return true;
          })
          .toList();

      if (mounted) {
        setState(() {
          _relations = relations;
          _localPeers = localPeers;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading libraries: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<LibraryRelation> get _filtered => switch (_filter) {
        LibraryFilter.all => _relations,
        LibraryFilter.peers => _relations.where((r) => r.isPeer).toList(),
        LibraryFilter.following =>
          _relations.where((r) => r.isFollowing).toList(),
      };

  /// mDNS peers shown only on All and Peers filter tabs
  List<DiscoveredPeer> get _visibleLocalPeers =>
      _filter == LibraryFilter.following ? [] : _localPeers;

  @override
  Widget build(BuildContext context) {
    final pendingProvider = context.watch<PendingPeersProvider>();
    return Column(
      children: [
        if (pendingProvider.pendingCount > 0)
          _PendingBanner(
            count: pendingProvider.pendingCount,
            onAction: pendingProvider.refresh,
          ),
        _DirectoryBanner(onTap: () => context.push('/directory')),
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  LibraryFilter.all, 'lib_filter_all',
                  const Key('libFilterAll'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  LibraryFilter.peers, 'lib_filter_peers',
                  const Key('libFilterPeers'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  LibraryFilter.following, 'lib_filter_following',
                  const Key('libFilterFollowing'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadLibraries,
                  child: (_filtered.isEmpty && _visibleLocalPeers.isEmpty)
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [_buildEmptyState(context)],
                        )
                      : ListView(
                          key: const Key('librariesList'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            // Locally discovered libraries (mDNS, not yet saved)
                            if (_visibleLocalPeers.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _sectionHeader(
                                context,
                                TranslationService.translate(
                                  context, 'local_network_title',
                                ),
                                Icons.wifi,
                                subtitle: TranslationService.translate(
                                  context, 'local_network_hint',
                                ),
                                key: const Key('localNetworkSection'),
                              ),
                              ..._visibleLocalPeers.map(_buildLocalPeerTile),
                              if (_filtered.isNotEmpty) const Divider(height: 8),
                            ],
                            // Saved peers + follows
                            ..._filtered.map(
                              (r) => _LibraryRelationCard(
                                relation: r,
                                onRefresh: _loadLibraries,
                              ),
                            ),
                          ],
                        ),
                ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    Key? key,
    String? subtitle,
  }) {
    return Semantics(
      header: true,
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _buildLocalPeerTile(DiscoveredPeer peer) {
    final url = 'http://${peer.host}:${peer.port}';

    // Compute display name: strip device hostname suffix when present
    String displayName = peer.name;
    if (peer.deviceName != null && peer.deviceName!.isNotEmpty) {
      final suffix = ' ${peer.deviceName}';
      if (peer.name.endsWith(suffix)) {
        displayName = peer.name.substring(0, peer.name.length - suffix.length);
      }
    }
    const defaultNames = {'My Library', 'Ma Bibliothèque', 'BiblioGenius Library'};
    final showDevice = peer.deviceName != null &&
        peer.deviceName!.isNotEmpty &&
        defaultNames.contains(displayName);

    return Semantics(
      button: true,
      label: displayName,
      child: Card(
        key: Key('localPeerTile_${peer.host}_${peer.port}'),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const CircleAvatar(
            backgroundColor: Colors.blue,
            child: Icon(Icons.wifi, color: Colors.white),
          ),
          title: Text(displayName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDevice)
                Text(
                  peer.deviceName!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  TranslationService.translate(context, 'status_active'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          isThreeLine: showDevice,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.menu_book),
                tooltip: TranslationService.translate(context, 'browse_library'),
                onPressed: () => context.push(
                  '/peers/0/books',
                  extra: {'id': 0, 'name': displayName, 'url': url, 'hasRelayCredentials': false},
                ),
              ),
              Consumer<ApiService>(
                builder: (context, api, _) => FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    TranslationService.translate(context, 'connect'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () async {
                    try {
                      await api.connectPeer(
                        peer.name, url,
                        ed25519PublicKey: peer.ed25519PublicKey,
                        x25519PublicKey: peer.x25519PublicKey,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                            '${TranslationService.translate(context, 'request_sent_to')} $displayName',
                          ),
                        ));
                        _loadLibraries();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                            '${TranslationService.translate(context, 'connection_error')}: $e',
                          ),
                        ));
                      }
                    }
                  },
                ),
              ),
            ],
          ),
          onTap: () => context.push(
            '/peers/0/books',
            extra: {'id': 0, 'name': displayName, 'url': url, 'hasRelayCredentials': false},
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(LibraryFilter filter, String labelKey, Key chipKey) {
    final isSelected = _filter == filter;
    return FilterChip(
      key: chipKey,
      selected: isSelected,
      label: Text(
        TranslationService.translate(context, labelKey),
        style: TextStyle(color: isSelected ? Colors.white : null),
      ),
      selectedColor: Theme.of(context).colorScheme.primary,
      checkmarkColor: Colors.white,
      onSelected: (_) => setState(() => _filter = filter),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.library_books_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(context, 'lib_empty_title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, 'lib_empty_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/directory'),
              icon: const Icon(Icons.travel_explore),
              label: Text(TranslationService.translate(context, 'directory_title')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library relation card - shows peer + follow status with actions
// ---------------------------------------------------------------------------

class _LibraryRelationCard extends StatelessWidget {
  final LibraryRelation relation;
  final VoidCallback onRefresh;

  const _LibraryRelationCard({
    required this.relation,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Avatar color encodes the dominant connection type
    final Color avatarColor;
    final IconData avatarIcon;
    if (relation.isPeer && relation.isFollowing) {
      avatarColor = Colors.teal;
      avatarIcon = Icons.wifi;
    } else if (relation.isPeer) {
      avatarColor = Colors.blue;
      avatarIcon = Icons.wifi;
    } else {
      avatarColor = Colors.deepPurple;
      avatarIcon = Icons.library_books;
    }

    return Semantics(
      button: true,
      label: relation.name,
      child: Card(
        key: Key('libraryCard_${relation.nodeId}'),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: avatar + name + connection chips
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: avatarColor,
                    child: Icon(avatarIcon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          relation.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (relation.isPeer)
                              _chip(
                                context,
                                label: TranslationService.translate(
                                  context, 'lib_connection_peer',
                                ),
                                color: Colors.blue,
                              ),
                            if (relation.isFollowing)
                              _chip(
                                context,
                                label: relation.followPending
                                    ? TranslationService.translate(
                                        context, 'lib_follow_pending',
                                      )
                                    : TranslationService.translate(
                                        context, 'lib_follow_active',
                                      ),
                                color: relation.followPending
                                    ? Colors.orange
                                    : Colors.deepPurple,
                                icon: relation.followPending
                                    ? Icons.pending
                                    : Icons.bookmark,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Action row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _buildActions(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];

    // Browse catalog - P2P peer
    if (relation.isPeer && relation.peer?.url != null) {
      final peer = relation.peer!;
      actions.add(IconButton(
        icon: const Icon(Icons.menu_book),
        tooltip: TranslationService.translate(context, 'browse_library'),
        onPressed: () => context.push(
          '/peers/${peer.id}/books',
          extra: {
            'id': peer.id,
            'name': relation.name,
            'url': peer.url,
            'hasRelayCredentials': peer.hasRelayCredentials,
          },
        ),
      ));
    }

    // Browse catalog - active hub follow (no direct peer)
    if (!relation.isPeer &&
        relation.isFollowing &&
        relation.follow!.isActive) {
      actions.add(IconButton(
        icon: const Icon(Icons.menu_book),
        tooltip: TranslationService.translate(context, 'browse_library'),
        onPressed: () =>
            context.push('/directory/${Uri.encodeComponent(relation.nodeId)}'),
      ));
    }

    // Sync (peers only)
    if (relation.isPeer && relation.peer?.url != null) {
      actions.add(
        Consumer<ApiService>(
          builder: (context, api, _) => IconButton(
            icon: const Icon(Icons.sync),
            tooltip: TranslationService.translate(context, 'tooltip_sync'),
            onPressed: () async {
              await api.syncPeer(relation.peer!.url!);
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
      );
    }

    // Unfollow (active follows only)
    if (relation.isFollowing && !relation.followPending) {
      actions.add(
        Consumer<HubDirectoryProvider>(
          builder: (context, dirProvider, _) => IconButton(
            icon: Icon(
              Icons.bookmark_remove,
              color: Theme.of(context).colorScheme.error,
            ),
            tooltip: TranslationService.translate(context, 'lib_unfollow'),
            onPressed: () async {
              await dirProvider.unfollow(relation.nodeId);
              onRefresh();
            },
          ),
        ),
      );
    }

    // Disconnect peer
    if (relation.isPeer) {
      actions.add(
        Consumer<ApiService>(
          builder: (context, api, _) => IconButton(
            icon: Icon(
              Icons.link_off,
              color: Theme.of(context).colorScheme.error,
            ),
            tooltip: TranslationService.translate(context, 'delete'),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    TranslationService.translate(ctx, 'delete_contact_title'),
                  ),
                  content: Text(
                    '${TranslationService.translate(ctx, 'confirm_delete')} '
                    '${relation.name}?',
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
                        TranslationService.translate(ctx, 'delete_contact_btn'),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await api.deletePeer(relation.peer!.id);
                onRefresh();
              }
            },
          ),
        ),
      );
    }

    return actions;
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
