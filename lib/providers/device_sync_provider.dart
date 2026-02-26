import 'package:flutter/foundation.dart';
import '../src/rust/api/frb.dart' as frb;

class DeviceSyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  String? _error;
  frb.FrbSyncResult? _lastResult;
  List<frb.FrbPendingReviewOp> _pendingReview = [];
  bool _isLoadingReview = false;

  // Getters
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  frb.FrbSyncResult? get lastResult => _lastResult;
  List<frb.FrbPendingReviewOp> get pendingReview => _pendingReview;
  bool get isLoadingReview => _isLoadingReview;
  int get pendingReviewCount => _pendingReview.length;

  /// Trigger sync with a linked device
  Future<void> triggerSync(int deviceId) async {
    _isSyncing = true;
    _error = null;
    notifyListeners();

    try {
      final result = await frb.deviceTriggerSync(deviceId: deviceId);
      _lastResult = result;
      // Refresh pending review list after sync
      await _loadPendingReviewSilent();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.triggerSync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Load pending review operations
  Future<void> loadPendingReview() async {
    _isLoadingReview = true;
    _error = null;
    notifyListeners();

    try {
      _pendingReview = await frb.deviceSyncPendingReview();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.loadPendingReview error: $e');
    } finally {
      _isLoadingReview = false;
      notifyListeners();
    }
  }

  /// Internal reload without loading indicator
  Future<void> _loadPendingReviewSilent() async {
    try {
      _pendingReview = await frb.deviceSyncPendingReview();
    } catch (e) {
      debugPrint('DeviceSyncProvider._loadPendingReviewSilent error: $e');
    }
  }

  /// Approve specific operations by IDs
  Future<int> approveOps(List<int> ids) async {
    try {
      final count = await frb.deviceSyncApprove(ids: ids);
      _pendingReview.removeWhere((op) => ids.contains(op.id));
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.approveOps error: $e');
      notifyListeners();
      return 0;
    }
  }

  /// Reject specific operations by IDs
  Future<int> rejectOps(List<int> ids) async {
    try {
      final count = await frb.deviceSyncReject(ids: ids);
      _pendingReview.removeWhere((op) => ids.contains(op.id));
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.rejectOps error: $e');
      notifyListeners();
      return 0;
    }
  }

  /// Approve all pending review operations
  Future<int> approveAll() async {
    try {
      final count = await frb.deviceSyncApproveAll();
      _pendingReview.clear();
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.approveAll error: $e');
      notifyListeners();
      return 0;
    }
  }

  /// Reject all pending review operations
  Future<int> rejectAll() async {
    try {
      final count = await frb.deviceSyncRejectAll();
      _pendingReview.clear();
      notifyListeners();
      return count.toInt();
    } catch (e) {
      _error = e.toString();
      debugPrint('DeviceSyncProvider.rejectAll error: $e');
      notifyListeners();
      return 0;
    }
  }
}
