import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../core/cache_config.dart';
import '../core/cache_state.dart';
import '../storage/hive_cache_storage.dart';

/// Abstract base class for repositories with dual-track caching.
///
/// Implements the Stale-While-Revalidate pattern:
/// 1. On initialization, immediately emit cached data if available
/// 2. Simultaneously fetch fresh data from the network
/// 3. When network data arrives, update cache and emit new data
///
/// Subclasses must implement:
/// - [fetchFromRemote]: Fetch data from the API
/// - [toJson]: Serialize item to JSON for caching
/// - [fromJson]: Deserialize item from cached JSON
/// - [getId]: Get the unique identifier for an item
///
/// Type parameters:
/// - [T]: The domain entity type
/// - [ID]: The type of the unique identifier (usually String)
///
/// Example:
/// ```dart
/// class TaskCachedRepository extends CachedRepository<Task, String> {
///   final ApiClient _apiClient;
///
///   TaskCachedRepository(this._apiClient) : super(boxName: 'tasks_cache');
///
///   @override
///   Future<List<Task>> fetchFromRemote() => _apiClient.getTasks();
///
///   @override
///   Map<String, dynamic> toJson(Task item) => item.toJson();
///
///   @override
///   Task fromJson(Map<String, dynamic> json) => Task.fromJson(json);
///
///   @override
///   String getId(Task item) => item.id;
/// }
/// ```
abstract class CachedRepository<T, ID> {
  /// Name of the Hive box for caching.
  final String boxName;

  /// Cache configuration.
  final CacheConfig config;

  late final HiveCacheStorage<T, ID> _storage;
  late final BehaviorSubject<CacheState<List<T>>> _subject;

  DateTime? _lastRefreshAttempt;
  bool _isInitialized = false;
  bool _isDisposed = false;

  CachedRepository({
    required this.boxName,
    this.config = CacheConfig.defaultConfig,
  }) {
    _subject = BehaviorSubject<CacheState<List<T>>>.seeded(
      CacheState<List<T>>(isLoading: true),
    );
    _storage = HiveCacheStorage<T, ID>(
      boxName: boxName,
      fromJson: fromJson,
      toJson: toJson,
      getId: getId,
      config: config,
    );

    if (config.autoInitialize) {
      _initialize();
    }
  }

  // ==================== Abstract Methods (Must Implement) ====================

  /// Fetch data from the remote API.
  ///
  /// This method should throw on network errors.
  Future<List<T>> fetchFromRemote();

  /// Convert an item to JSON for caching.
  Map<String, dynamic> toJson(T item);

  /// Create an item from cached JSON.
  T fromJson(Map<String, dynamic> json);

  /// Get the unique identifier for an item.
  ID getId(T item);

  // ==================== Optional Hooks (Can Override) ====================

  /// Transform data before caching.
  ///
  /// Override this to filter or modify data before it's stored.
  /// Default implementation returns data unchanged.
  List<T> transformForCache(List<T> data) => data;

  /// Transform data before emitting to the stream.
  ///
  /// Override this to filter or modify data before UI receives it.
  /// Default implementation returns data unchanged.
  List<T> transformForDisplay(List<T> data) => data;

  /// Called when an error occurs during fetch.
  ///
  /// Override this to customize error handling or logging.
  void onFetchError(Object error, StackTrace stackTrace) {
    debugPrint('CachedRepository[$boxName]: Fetch error: $error');
  }

  // ==================== Public API ====================

  /// Stream of cache state changes.
  ///
  /// UI should listen to this stream to receive data updates.
  /// The stream emits:
  /// - Cached data immediately on subscription (if available)
  /// - Updated data when network fetch completes
  /// - Error states when fetch fails
  Stream<CacheState<List<T>>> get stream => _subject.stream;

  /// Current state snapshot.
  CacheState<List<T>> get currentState => _subject.value;

  /// Whether data is currently loading.
  bool get isLoading => _subject.value.isLoading;

  /// Whether cached data is available.
  bool get hasData => _subject.value.hasData;

  /// Manually initialize the repository.
  ///
  /// Usually not needed if [CacheConfig.autoInitialize] is true (default).
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _initialize();
  }

  /// Refresh data from the network.
  ///
  /// Use for pull-to-refresh. Shows loading indicator.
  Future<void> refresh() async {
    _ensureNotDisposed();
    await _fetchRemote(silent: false);
  }

  /// Silently refresh data in the background.
  ///
  /// Use when app returns to foreground. Does not show loading indicator.
  /// Respects throttle configuration to prevent too frequent requests.
  Future<void> silentRefresh() async {
    _ensureNotDisposed();

    // Check throttle
    if (_lastRefreshAttempt != null) {
      final elapsed = DateTime.now().difference(_lastRefreshAttempt!);
      if (elapsed < config.throttleDuration) {
        debugPrint(
          'CachedRepository[$boxName]: Throttled, last refresh was ${elapsed.inSeconds}s ago',
        );
        return;
      }
    }

    // Don't refresh if already loading
    if (_subject.value.isLoading) return;

    await _fetchRemote(silent: true);
  }

  /// Invalidate cache and reload data.
  ///
  /// Clears local cache and fetches fresh data.
  Future<void> invalidate() async {
    _ensureNotDisposed();
    await _storage.clear();
    _isInitialized = false;
    _subject.add(CacheState<List<T>>(isLoading: true));
    await _initialize();
  }

  /// Get a single item by ID.
  ///
  /// First checks cache, can optionally fetch from network.
  Future<T?> getById(ID id, {bool fetchIfMissing = false}) async {
    _ensureNotDisposed();

    // Check cache first
    final cached = await _storage.getById(id);
    if (cached != null) return cached;

    // Optionally fetch from network
    if (fetchIfMissing && !_subject.value.isLoading) {
      await _fetchRemote(silent: true);
      return _storage.getById(id);
    }

    return null;
  }

  /// Dispose resources.
  ///
  /// Call this when the repository is no longer needed.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await _subject.close();
    await _storage.dispose();
  }

  // ==================== Internal Methods ====================

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      await _storage.initialize();

      // Check if disposed during initialization
      if (_isDisposed) return;

      // Step 1: Load from cache
      final cachedItems = await _storage.getAll();
      final lastSync = _storage.lastSyncTime;

      if (cachedItems.isNotEmpty && !_isDisposed) {
        // Emit cached data immediately
        final displayData = transformForDisplay(cachedItems);
        _subject.add(
          _subject.value.withCacheData(displayData, lastSync),
        );
      }

      // Check if disposed before network fetch
      if (_isDisposed) return;

      // Step 2: Fetch from network
      await _fetchRemote(silent: cachedItems.isNotEmpty);
    } catch (e, st) {
      if (_isDisposed) return;
      debugPrint('CachedRepository[$boxName]: Initialization error: $e');
      _subject.add(
        _subject.value.withError(e, 'Initialization failed: $e'),
      );
      onFetchError(e, st);
    }
  }

  Future<void> _fetchRemote({required bool silent}) async {
    if (_isDisposed) return;
    _lastRefreshAttempt = DateTime.now();

    try {
      if (!silent && !_isDisposed) {
        _subject.add(_subject.value.copyWith(isLoading: true, clearError: true));
      }

      final items = await fetchFromRemote();

      // Check if disposed during fetch
      if (_isDisposed) return;

      final cacheData = transformForCache(items);
      final displayData = transformForDisplay(items);

      // Save to cache
      await _storage.saveAll(cacheData);

      // Emit to stream
      if (!_isDisposed) {
        _subject.add(_subject.value.withNetworkData(displayData));
      }
    } catch (e, st) {
      if (_isDisposed) return;
      debugPrint('CachedRepository[$boxName]: Fetch error: $e');
      _subject.add(
        _subject.value.withError(e, 'Network request failed: $e'),
      );
      onFetchError(e, st);
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('CachedRepository[$boxName] has been disposed');
    }
  }
}

/// Extension for single-item repositories.
///
/// Use this when caching a single item instead of a list.
extension SingleItemRepository<T, ID> on CachedRepository<T, ID> {
  /// Stream of the first (or only) item.
  Stream<CacheState<T?>> get singleItemStream {
    return stream.map((state) {
      final singleData = state.data?.isNotEmpty == true ? state.data!.first : null;
      return CacheState<T?>(
        data: singleData,
        lastUpdated: state.lastUpdated,
        isLoading: state.isLoading,
        source: state.source,
        error: state.error,
        errorMessage: state.errorMessage,
      );
    });
  }
}
