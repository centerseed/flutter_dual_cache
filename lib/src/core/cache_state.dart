import 'cache_config.dart';

/// Indicates the source of the data.
enum CacheSource {
  /// Data loaded from local cache.
  cache,

  /// Data fetched from remote API.
  network,

  /// No data source (initial state).
  none,
}

/// Encapsulates the state of cached data with metadata.
///
/// This class provides a unified way to track:
/// - The actual data
/// - Whether data is loading
/// - The source of the data (cache vs network)
/// - When the data was last updated
/// - Any errors that occurred
class CacheState<T> {
  /// The cached data, null if not yet loaded.
  final T? data;

  /// Timestamp of when the data was last updated.
  final DateTime? lastUpdated;

  /// Whether a network request is currently in progress.
  final bool isLoading;

  /// The source of the current data.
  final CacheSource source;

  /// Error object if the last operation failed.
  final Object? error;

  /// Error message for display purposes.
  final String? errorMessage;

  const CacheState({
    this.data,
    this.lastUpdated,
    this.isLoading = false,
    this.source = CacheSource.none,
    this.error,
    this.errorMessage,
  });

  /// Initial loading state.
  const CacheState.loading()
      : data = null,
        lastUpdated = null,
        isLoading = true,
        source = CacheSource.none,
        error = null,
        errorMessage = null;

  /// Check if the cache is stale based on the provided config.
  bool isStaleWith(CacheConfig config) {
    if (lastUpdated == null) return true;
    return DateTime.now().difference(lastUpdated!) > config.ttlDuration;
  }

  /// Check if the cache is stale using default TTL (5 minutes).
  bool get isStale => isStaleWith(CacheConfig.defaultConfig);

  /// Whether data is available.
  bool get hasData => data != null;

  /// Whether an error occurred.
  bool get hasError => error != null || errorMessage != null;

  /// Whether data came from cache.
  bool get isFromCache => source == CacheSource.cache;

  /// Whether data came from network.
  bool get isFromNetwork => source == CacheSource.network;

  /// Create a copy with updated fields.
  CacheState<T> copyWith({
    T? data,
    DateTime? lastUpdated,
    bool? isLoading,
    CacheSource? source,
    Object? error,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CacheState<T>(
      data: data ?? this.data,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isLoading: isLoading ?? this.isLoading,
      source: source ?? this.source,
      error: clearError ? null : (error ?? this.error),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Create a state with data from cache.
  CacheState<T> withCacheData(T data, DateTime? syncTime) {
    return copyWith(
      data: data,
      lastUpdated: syncTime,
      source: CacheSource.cache,
      isLoading: true, // Still loading network data
      clearError: true,
    );
  }

  /// Create a state with data from network.
  CacheState<T> withNetworkData(T data) {
    return copyWith(
      data: data,
      lastUpdated: DateTime.now(),
      source: CacheSource.network,
      isLoading: false,
      clearError: true,
    );
  }

  /// Create a state with an error.
  CacheState<T> withError(Object error, [String? message]) {
    return copyWith(
      isLoading: false,
      error: error,
      errorMessage: message ?? error.toString(),
    );
  }

  @override
  String toString() {
    return 'CacheState(hasData: $hasData, isLoading: $isLoading, source: $source, '
        'lastUpdated: $lastUpdated, hasError: $hasError)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheState<T> &&
        other.data == data &&
        other.lastUpdated == lastUpdated &&
        other.isLoading == isLoading &&
        other.source == source &&
        other.error == error &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(
      data,
      lastUpdated,
      isLoading,
      source,
      error,
      errorMessage,
    );
  }
}
