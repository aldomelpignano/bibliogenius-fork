import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/translation_service.dart';

class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();

  String? _pairingCode;
  String? _myIp;
  bool _isLoadingSource = false;
  bool _isLoadingTarget = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyIp();
    });
  }

  Future<void> _loadMyIp() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    // Get IP from config
    try {
      final res = await apiService.getLibraryConfig();
      if (res.statusCode == 200) {
        if (res.data['default_uri'] != null) {
          final uri = Uri.parse(res.data['default_uri']);
          // Don't use localhost - get real IP instead
          if (uri.host != 'localhost' && uri.host != '127.0.0.1') {
            if (mounted) {
              setState(() {
                _myIp = '${uri.host}:${uri.port}';
              });
            }
            return;
          }
        }
        if (res.data['library_ip'] != null &&
            res.data['library_ip'] != 'localhost' &&
            res.data['library_ip'] != '127.0.0.1') {
          if (mounted) {
            setState(() {
              _myIp = '${res.data['library_ip']}:${ApiService.httpPort}';
            });
          }
          return;
        }
      }

      // Fallback: detect local network IP from interfaces
      final ip = await _getLocalIpAddress();
      if (mounted) {
        setState(() {
          _myIp = '$ip:${ApiService.httpPort}';
        });
      }
    } catch (e) {
      debugPrint('Error loading IP: $e');
      final ip = await _getLocalIpAddress();
      if (mounted) {
        setState(() {
          _myIp = '$ip:${ApiService.httpPort}';
        });
      }
    }
  }

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      final List<String> candidates = [];

      for (var interface in interfaces) {
        // Skip loopback interfaces
        if (interface.name.startsWith('lo')) continue;

        for (var addr in interface.addresses) {
          // Skip loopback addresses
          if (addr.address.startsWith('127.')) continue;

          // Collect private network IPs
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            candidates.add(addr.address);
          }
        }
      }

      if (candidates.isNotEmpty) {
        // Prioritize 192.168.x.x (most common home wifi)
        final best = candidates.firstWhere(
          (ip) => ip.startsWith('192.168.'),
          orElse: () => candidates.first,
        );
        return best;
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return 'localhost'; // Last resort fallback
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  // --- Source Logic ---

  Future<void> _generateCode() async {
    setState(() => _isLoadingSource = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);

      final uuid = await authService.getOrCreateLibraryUuid();
      final ip = _myIp ?? 'localhost:${ApiService.httpPort}';

      final res = await apiService.generatePairingCode(
        uuid: uuid,
        secret: uuid,
        ip: ip,
      );

      if (res.statusCode == 200 && res.data['code'] != null) {
        setState(() => _pairingCode = res.data['code']);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'link_device_error'),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error generating pairing code: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSource = false);
      }
    }
  }

  // --- Target Logic ---

  Future<void> _linkDevice() async {
    final code = _codeController.text.trim();
    final host = _ipController.text.trim();

    if (code.isEmpty || host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'fill_all_fields'),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoadingTarget = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);

      // Verify code with remote
      final res = await apiService.verifyRemotePairingCode(
        host: host,
        code: code,
      );

      if (res.statusCode == 200 && res.data['uuid'] != null) {
        final remoteUuid = res.data['uuid'];
        await authService.setLibraryUuid(remoteUuid);

        // Sync peer for mDNS discovery
        await apiService.syncPeer(host);

        // Import all library data from the source device
        final importResult = await apiService.importFromPeer(host);

        if (mounted) {
          final booksCount = importResult['books'] ?? 0;
          final contactsCount = importResult['contacts'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'link_device_success')} ($booksCount livres, $contactsCount contacts)',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
          // Pop back to profile instead of going to root (avoids GoException)
          context.pop();
        }
      } else {
        // Show specific error from server
        final errorMsg = res.data['error'] ?? 'Status ${res.statusCode}';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'link_device_error')}: $errorMsg',
              ),
              backgroundColor: Colors.red,
            ),
          );
          context.pop(); // Go back
        }
      }
    } catch (e) {
      debugPrint('Error linking device: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'link_device_error')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingTarget = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine dark mode from current theme brightness
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: TranslationService.translate(context, 'back'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(TranslationService.translate(context, 'link_device_title')),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            Tab(
              text: TranslationService.translate(
                context,
                'link_device_tab_source',
              ),
            ),
            Tab(
              text: TranslationService.translate(
                context,
                'link_device_tab_target',
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSourceTab(context, isDark),
          _buildTargetTab(context, isDark),
        ],
      ),
    );
  }

  Widget _buildSourceTab(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phonelink_ring, size: 64, color: Colors.indigo),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'link_device_share_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.translate(context, 'link_device_share_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            if (_isLoadingSource)
              const CircularProgressIndicator()
            else if (_pairingCode != null) ...[
              Text(
                _pairingCode!,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                TranslationService.translate(context, 'link_device_code_valid'),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      TranslationService.translate(
                        context,
                        'link_device_your_ip',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _myIp ?? 'Loading...',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            ] else
              ElevatedButton.icon(
                onPressed: _generateCode,
                icon: const Icon(Icons.vpn_key),
                label: Text(
                  TranslationService.translate(
                    context,
                    'link_device_generate_code',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetTab(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.input, size: 64, color: Colors.green),
              const SizedBox(height: 24),
              Text(
                TranslationService.translate(context, 'link_device_join_title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                TranslationService.translate(context, 'link_device_join_desc'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'link_device_pairing_code',
                  ),
                  hintText: TranslationService.translate(
                    context,
                    'link_device_pairing_code_hint',
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 2),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'link_device_host_ip',
                  ),
                  hintText: TranslationService.translate(
                    context,
                    'link_device_host_ip_hint',
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.computer),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 32),
              if (_isLoadingTarget)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _linkDevice,
                  icon: const Icon(Icons.link),
                  label: Text(
                    TranslationService.translate(
                      context,
                      'link_device_verify_link',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                '⚠️ ${TranslationService.translate(context, 'reset_app_confirmation').split('.').first}.',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
