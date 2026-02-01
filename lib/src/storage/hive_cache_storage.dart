import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/cache_config.dart';

/// A generic Hive-based cache storage implementation.
///
/// This class provides local caching functionality using Hive as the underlying
/// storage engine. It handles serialization/deserialization of data and manages
/// sync timestamps.
///
/// Type parameters:
/// - [T]: The type of data to cache
/// - [ID]: The type of the unique identifier for each item
class HiveCacheStorage<T, ID> {
  /// Name of the Hive box for this storage.
  final String boxName;

  /// Function to deserialize JSON to model.
  final T Function(Map<String, dynamic> json) fromJson;

  /// Function to serialize model to JSON.
  final Map<String, dynamic> Function(T item) toJson;

  /// Function to get the unique ID from an item.
  final ID Function(T item) getId;

  /// Cache configuration.
  final CacheConfig config;

  Box<Map>? _box;

  HiveCacheStorage({
    required this.boxName,
    required this.fromJson,
    required this.toJson,
    required this.getId,
    this.config = CacheConfig.defaultConfig,
  });

  /// Whether the storage has been initialized.
  bool get isInitialized => _box?.isOpen ?? false;

  /// Initialize the Hive box.
  ///
  /// Must be called before any other operations.
  /// Safe to call multiple times.
  Future<void> initialize() async {
    if (_box?.isOpen ?? false) return;

    try {
      _box = await Hive.openBox<Map>(boxName);
    } catch (e) {
      debugPrint('HiveCacheStorage: Failed to open box $boxName: $e');
      rethrow;
    }
  }

  /// Ensure the box is initialized before operations.
  void _ensureInitialized() {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'HiveCacheStorage not initialized. Call initialize() first.',
      );
    }
  }

  /// Get all cached items.
  Future<List<T>> getAll() async {
    _ensureInitialized();

    final List<T> items = [];

    for (final key in _box!.keys) {
      // Skip metadata keys
      if (key == config.lastSyncKey) continue;

      final data = _box!.get(key);
      if (data != null) {
        try {
          final item = fromJson(Map<String, dynamic>.from(data));
          items.add(item);
        } catch (e) {
          debugPrint('HiveCacheStorage: Failed to parse item $key: $e');
        }
      }
    }

    return items;
  }

  /// Get a single item by ID.
  Future<T?> getById(ID id) async {
    _ensureInitialized();

    final data = _box!.get(id.toString());
    if (data == null) return null;

    try {
      return fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('HiveCacheStorage: Failed to parse item $id: $e');
      return null;
    }
  }

  /// Save all items to cache, replacing existing data.
  Future<void> saveAll(List<T> items) async {
    _ensureInitialized();

    // Clear old data (except metadata)
    final keysToDelete =
        _box!.keys.where((k) => k != config.lastSyncKey).toList();
    await _box!.deleteAll(keysToDelete);

    // Write new data
    for (final item in items) {
      final id = getId(item).toString();
      await _box!.put(id, toJson(item));
    }

    await _updateSyncTime();
  }

  /// Save a single item.
  Future<void> save(T item) async {
    _ensureInitialized();

    final id = getId(item).toString();
    await _box!.put(id, toJson(item));
  }

  /// Delete a single item by ID.
  Future<void> delete(ID id) async {
    _ensureInitialized();
    await _box!.delete(id.toString());
  }

  /// Clear all cached data.
  Future<void> clear() async {
    _ensureInitialized();
    await _box!.clear();
  }

  /// Get the last sync timestamp.
  DateTime? get lastSyncTime {
    if (_box == null || !_box!.isOpen) return null;

    final timestamp = _box!.get(config.lastSyncKey)?['timestamp'];
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }

  /// Check if the cache is stale.
  bool get isStale {
    final lastSync = lastSyncTime;
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync) > config.ttlDuration;
  }

  /// Check if the cache has any data.
  Future<bool> get hasData async {
    _ensureInitialized();
    return _box!.keys.any((k) => k != config.lastSyncKey);
  }

  /// Update the sync timestamp to now.
  Future<void> _updateSyncTime() async {
    await _box!.put(config.lastSyncKey, {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Close the Hive box.
  Future<void> dispose() async {
    await _box?.close();
    _box = null;
  }
}
