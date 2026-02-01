/// Configuration for cache behavior.
class CacheConfig {
  /// Time-to-live for cached data in minutes.
  /// After this duration, cached data is considered stale.
  final int ttlMinutes;

  /// Throttle duration for background refresh in seconds.
  /// Prevents too frequent refresh calls.
  final int backgroundRefreshThrottleSeconds;

  /// Key used to store last sync timestamp in Hive.
  final String lastSyncKey;

  /// Whether to automatically initialize on repository creation.
  final bool autoInitialize;

  const CacheConfig({
    this.ttlMinutes = 5,
    this.backgroundRefreshThrottleSeconds = 30,
    this.lastSyncKey = '_metadata_last_sync',
    this.autoInitialize = true,
  });

  /// Default configuration instance.
  static const CacheConfig defaultConfig = CacheConfig();

  /// Duration representation of TTL.
  Duration get ttlDuration => Duration(minutes: ttlMinutes);

  /// Duration representation of throttle.
  Duration get throttleDuration =>
      Duration(seconds: backgroundRefreshThrottleSeconds);

  CacheConfig copyWith({
    int? ttlMinutes,
    int? backgroundRefreshThrottleSeconds,
    String? lastSyncKey,
    bool? autoInitialize,
  }) {
    return CacheConfig(
      ttlMinutes: ttlMinutes ?? this.ttlMinutes,
      backgroundRefreshThrottleSeconds:
          backgroundRefreshThrottleSeconds ?? this.backgroundRefreshThrottleSeconds,
      lastSyncKey: lastSyncKey ?? this.lastSyncKey,
      autoInitialize: autoInitialize ?? this.autoInitialize,
    );
  }
}
