import 'package:flutter/foundation.dart';
import '../src/rust/api/frb.dart' as frb;

class OperationLogProvider extends ChangeNotifier {
  static final OperationLogProvider _instance =
      OperationLogProvider._internal();
  factory OperationLogProvider() => _instance;
  OperationLogProvider._internal();

  List<frb.FrbOperationLogEntry> _entries = [];
  frb.FrbOperationLogStats? _stats;
  List<String> _entityTypes = [];
  bool _isLoading = false;
  String? _error;

  // Filters
  String? _entityTypeFilter;
  String? _operationFilter;
  String? _statusFilter;
  String? _searchQuery;
  int _page = 0;
  int _totalPages = 1;
  static const int _pageSize = 50;

  // Getters
  List<frb.FrbOperationLogEntry> get entries => _entries;
  frb.FrbOperationLogStats? get stats => _stats;
  List<String> get entityTypes => _entityTypes;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get entityTypeFilter => _entityTypeFilter;
  String? get operationFilter => _operationFilter;
  String? get statusFilter => _statusFilter;
  String? get searchQuery => _searchQuery;
  int get page => _page;
  int get totalPages => _totalPages;

  Future<void> loadEntries() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await frb.operationLogList(
        entityType: _entityTypeFilter,
        operation: _operationFilter,
        status: _statusFilter,
        query: _searchQuery,
        page: BigInt.from(_page),
        limit: BigInt.from(_pageSize),
      );
      _entries = results;
      // Estimate total pages from stats if available
      if (_stats != null) {
        final total = _stats!.total.toInt();
        _totalPages = (total / _pageSize).ceil().clamp(1, 999999);
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('OperationLogProvider.loadEntries error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadStats() async {
    try {
      _stats = await frb.operationLogStats();
      if (_stats != null) {
        final total = _stats!.total.toInt();
        _totalPages = (total / _pageSize).ceil().clamp(1, 999999);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('OperationLogProvider.loadStats error: $e');
    }
  }

  Future<void> loadEntityTypes() async {
    try {
      _entityTypes = await frb.operationLogEntityTypes();
      notifyListeners();
    } catch (e) {
      debugPrint('OperationLogProvider.loadEntityTypes error: $e');
    }
  }

  Future<void> loadAll() async {
    await Future.wait([loadStats(), loadEntityTypes()]);
    await loadEntries();
  }

  void setEntityTypeFilter(String? value) {
    _entityTypeFilter = value;
    _page = 0;
    loadEntries();
  }

  void setOperationFilter(String? value) {
    _operationFilter = value;
    _page = 0;
    loadEntries();
  }

  void setStatusFilter(String? value) {
    _statusFilter = value;
    _page = 0;
    loadEntries();
  }

  void setSearchQuery(String? value) {
    final trimmed = value?.trim();
    _searchQuery = (trimmed != null && trimmed.isEmpty) ? null : trimmed;
    _page = 0;
    loadEntries();
  }

  void nextPage() {
    if (_page < _totalPages - 1) {
      _page++;
      loadEntries();
    }
  }

  void previousPage() {
    if (_page > 0) {
      _page--;
      loadEntries();
    }
  }

  void resetFilters() {
    _entityTypeFilter = null;
    _operationFilter = null;
    _statusFilter = null;
    _searchQuery = null;
    _page = 0;
    loadEntries();
  }
}
