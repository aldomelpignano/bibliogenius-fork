import 'package:flutter/foundation.dart';

import '../models/hub_directory.dart';
import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' as frb;

/// Page size for directory listing.
const int _kPageSize = 20;

/// State manager for the public hub directory feature (ADR-015).
///
/// Responsibilities:
/// - Local config (is_listed, requires_approval, accept_from)
/// - Directory browsing with pagination
/// - Follow/unfollow actions
/// - Incoming follow request management (approve / reject / block)
/// - Pending request count for badge display
class HubDirectoryProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();

  // ── Config ───────────────────────────────────────────────────────────────

  DirectoryConfig? _config;
  bool _configLoading = false;
  String? _configError;

  DirectoryConfig? get config => _config;
  bool get configLoading => _configLoading;
  String? get configError => _configError;
  bool get isRegistered => _config != null;
  bool get isListed => _config?.isListed ?? false;

  // ── Directory listing ─────────────────────────────────────────────────────

  List<HubProfile> _profiles = [];
  bool _listLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _listError;

  List<HubProfile> get profiles => _profiles;
  bool get listLoading => _listLoading;
  bool get hasMore => _hasMore;
  String? get listError => _listError;

  // ── Follow relationships ──────────────────────────────────────────────────

  List<HubFollow> _following = [];
  List<HubFollow> _followers = [];
  List<HubFollow> _pendingRequests = [];

  List<HubFollow> get following => _following;
  List<HubFollow> get followers => _followers;
  List<HubFollow> get pendingRequests => _pendingRequests;

  /// Number of pending incoming follow requests - used for badge.
  int get pendingCount => _pendingRequests.length;

  // ── Name cache ──────────────────────────────────────────────────────────

  /// nodeId -> display name, populated lazily from hub profile lookups.
  final Map<String, String> _nameCache = {};

  // ── Catalog sync ────────────────────────────────────────────────────────

  /// True when the local book list has changed since the last catalog push.
  bool _catalogDirty = false;

  bool get catalogDirty => _catalogDirty;

  // ── Action state ──────────────────────────────────────────────────────────

  /// Node IDs currently being processed (per-item loading).
  final Set<String> _busyNodes = {};
  String? _actionError;

  bool isBusy(String nodeId) => _busyNodes.contains(nodeId);
  bool get actionInProgress => _busyNodes.isNotEmpty;
  String? get actionError => _actionError;

  // ---------------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------------

  /// Load the local config from SQLite. Call once at app start / settings open.
  Future<void> loadConfig() async {
    _configLoading = true;
    _configError = null;
    notifyListeners();

    try {
      final frbConfig = await _ffi.hubDirectoryGetConfig();
      _config =
          frbConfig != null ? DirectoryConfig.fromFrb(frbConfig) : null;
    } catch (e) {
      _configError = e.toString();
      debugPrint('HubDirectoryProvider loadConfig error: $e');
    } finally {
      _configLoading = false;
      notifyListeners();
    }
  }

  /// Register or update the library profile on the hub directory.
  ///
  /// [bookCount] should be the current local book count.
  /// Returns true on success.
  Future<bool> register({
    required String nodeId,
    required String displayName,
    required int bookCount,
    required bool isListed,
    required bool requiresApproval,
    required String acceptFrom,
    String? description,
    String? locationCountry,
  }) async {
    _configLoading = true;
    _configError = null;
    notifyListeners();

    try {
      final params = frb.FrbRegisterParams(
        nodeId: nodeId,
        displayName: displayName,
        bookCount: bookCount,
        isListed: isListed,
        requiresApproval: requiresApproval,
        acceptFrom: acceptFrom,
        description: description,
        locationCountry: locationCountry,
      );
      final result = await _ffi.hubDirectoryRegister(params);
      if (result != null) {
        _config = DirectoryConfig.fromFrb(result);
        return true;
      }
      return false;
    } catch (e) {
      _configError = e.toString();
      debugPrint('HubDirectoryProvider register error: $e');
      return false;
    } finally {
      _configLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Directory listing
  // ---------------------------------------------------------------------------

  /// Load the first page of the directory. Resets existing results.
  Future<void> loadDirectory() async {
    _profiles = [];
    _offset = 0;
    _hasMore = true;
    _listError = null;
    await _fetchNextPage();
  }

  /// Load the next page (infinite scroll).
  Future<void> loadMoreDirectory() async {
    if (_listLoading || !_hasMore) return;
    await _fetchNextPage();
  }

  Future<void> _fetchNextPage() async {
    _listLoading = true;
    _listError = null;
    notifyListeners();

    try {
      final batch = await _ffi.hubDirectoryList(
        limit: _kPageSize,
        offset: _offset,
      );
      final newProfiles = batch.map(HubProfile.fromFrb).toList();
      _profiles.addAll(newProfiles);
      _offset += newProfiles.length;
      _hasMore = newProfiles.length == _kPageSize;
    } catch (e) {
      _listError = e.toString();
      debugPrint('HubDirectoryProvider _fetchNextPage error: $e');
    } finally {
      _listLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Follow / unfollow
  // ---------------------------------------------------------------------------

  /// Follow (or request to follow) a library identified by [nodeId].
  /// Updates the following list on success.
  Future<bool> follow(String nodeId) async {
    _busyNodes.add(nodeId);
    _actionError = null;
    notifyListeners();

    try {
      final result = await _ffi.hubDirectoryFollow(nodeId);
      if (result != null) {
        await loadFollowing();
        return true;
      }
      _actionError = 'Follow request failed';
      debugPrint('HubDirectoryProvider follow: result was null for $nodeId');
      return false;
    } catch (e) {
      _actionError = e.toString();
      debugPrint('HubDirectoryProvider follow error: $e');
      return false;
    } finally {
      _busyNodes.remove(nodeId);
      notifyListeners();
    }
  }

  /// Unfollow a library identified by [nodeId].
  Future<bool> unfollow(String nodeId) async {
    _busyNodes.add(nodeId);
    _actionError = null;
    notifyListeners();

    try {
      final ok = await _ffi.hubDirectoryUnfollow(nodeId);
      if (ok) await loadFollowing();
      return ok;
    } catch (e) {
      _actionError = e.toString();
      debugPrint('HubDirectoryProvider unfollow error: $e');
      return false;
    } finally {
      _busyNodes.remove(nodeId);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Follow relationships
  // ---------------------------------------------------------------------------

  Future<void> loadFollowing() async {
    try {
      final raw = await _ffi.hubDirectoryListFollowing();
      _following = raw.map(HubFollow.fromFrb).toList();
      _resolveNames(
        _following.map((f) => f.followedNodeId).toList(),
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider loadFollowing error: $e');
    }
    notifyListeners();
  }

  Future<void> loadFollowers() async {
    try {
      final raw = await _ffi.hubDirectoryListFollowers();
      _followers = raw.map(HubFollow.fromFrb).toList();
      _resolveNames(
        _followers.map((f) => f.followerNodeId).toList(),
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider loadFollowers error: $e');
    }
    notifyListeners();
  }

  /// Load pending incoming follow requests (badge count).
  Future<void> loadPendingRequests() async {
    try {
      final raw = await _ffi.hubDirectoryPendingRequests();
      _pendingRequests = raw.map(HubFollow.fromFrb).toList();
      _resolveNames(
        _pendingRequests.map((f) => f.followerNodeId).toList(),
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider loadPendingRequests error: $e');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Incoming request resolution
  // ---------------------------------------------------------------------------

  /// Approve or reject an incoming follow request.
  ///
  /// [resolution]: "approve", "reject", or "block"
  Future<bool> resolveFollow(int followId, String resolution) async {
    final key = 'resolve_$followId';
    _busyNodes.add(key);
    _actionError = null;
    notifyListeners();

    try {
      final result =
          await _ffi.hubDirectoryResolveFollow(followId, resolution);
      if (result != null) {
        // Refresh pending list and followers after resolution.
        await Future.wait([loadPendingRequests(), loadFollowers()]);
        return true;
      }
      return false;
    } catch (e) {
      _actionError = e.toString();
      debugPrint('HubDirectoryProvider resolveFollow error: $e');
      return false;
    } finally {
      _busyNodes.remove(key);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Catalog sync
  // ---------------------------------------------------------------------------

  /// Mark the catalog as needing a push to the hub.
  /// Call this after a book is added or deleted.
  void markCatalogDirty() {
    _catalogDirty = true;
  }

  /// Push the full ISBN catalog to the hub.
  /// Returns the number of ISBNs pushed, or -1 on error.
  Future<int> syncCatalog() async {
    if (!isRegistered) return 0;
    try {
      final count = await _ffi.hubDirectorySyncCatalog();
      if (count >= 0) _catalogDirty = false;
      debugPrint('HubDirectoryProvider syncCatalog: pushed $count ISBNs');
      return count;
    } catch (e) {
      debugPrint('HubDirectoryProvider syncCatalog error: $e');
      return -1;
    }
  }

  /// Push catalog only if dirty and registered. Intended for lifecycle hooks.
  Future<void> syncCatalogIfDirty() async {
    if (!_catalogDirty || !isRegistered || !isListed) return;
    await syncCatalog();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the follow status for [nodeId] from the local cache, or null.
  String? followStatusFor(String nodeId) {
    try {
      return _following
          .firstWhere((f) => f.followedNodeId == nodeId)
          .status;
    } catch (_) {
      return null;
    }
  }

  /// Resolves a node ID to a display name.
  /// Checks: name cache, then loaded directory profiles.
  String? displayNameFor(String nodeId) {
    final cached = _nameCache[nodeId];
    if (cached != null) return cached;
    try {
      final name = _profiles
          .firstWhere((p) => p.nodeId == nodeId)
          .displayName;
      _nameCache[nodeId] = name;
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Fetches display names for [nodeIds] not already cached.
  /// Runs in the background and calls notifyListeners when done.
  void _resolveNames(List<String> nodeIds) {
    final unknown = nodeIds
        .where((id) => !_nameCache.containsKey(id))
        .toSet();
    if (unknown.isEmpty) return;

    // Fire-and-forget: fetch each profile and update cache.
    for (final id in unknown) {
      _ffi.hubDirectoryGetProfile(id).then((profile) {
        if (profile != null) {
          _nameCache[id] = profile.displayName;
          notifyListeners();
        }
      }).catchError((e) {
        debugPrint('HubDirectoryProvider _resolveNames($id): $e');
      });
    }
  }

  void clearActionError() {
    _actionError = null;
    notifyListeners();
  }
}
