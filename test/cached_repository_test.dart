import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_dual_cache/flutter_dual_cache.dart';

// Test model
class TestItem {
  final String id;
  final String name;

  TestItem({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory TestItem.fromJson(Map<String, dynamic> json) {
    return TestItem(id: json['id'] as String, name: json['name'] as String);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestItem && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);
}

// Mock API
class MockApi extends Mock {
  Future<List<TestItem>> fetchItems();
}

// Concrete repository for testing
class TestRepository extends CachedRepository<TestItem, String> {
  final MockApi api;

  TestRepository(this.api)
      : super(
          boxName: 'test_items_${DateTime.now().millisecondsSinceEpoch}',
          config: const CacheConfig(
            autoInitialize: false,
            backgroundRefreshThrottleSeconds: 60,
          ),
        );

  @override
  Future<List<TestItem>> fetchFromRemote() => api.fetchItems();

  @override
  Map<String, dynamic> toJson(TestItem item) => item.toJson();

  @override
  TestItem fromJson(Map<String, dynamic> json) => TestItem.fromJson(json);

  @override
  String getId(TestItem item) => item.id;
}

void main() {
  setUpAll(() async {
    // Initialize Hive for testing
    Hive.init('./test_hive');
  });

  group('CacheState', () {
    test('initial state should have correct defaults', () {
      const state = CacheState<List<String>>();

      expect(state.data, isNull);
      expect(state.lastUpdated, isNull);
      expect(state.isLoading, isFalse);
      expect(state.source, CacheSource.none);
      expect(state.hasData, isFalse);
      expect(state.hasError, isFalse);
    });

    test('loading state should be correct', () {
      const state = CacheState<List<String>>.loading();

      expect(state.isLoading, isTrue);
      expect(state.source, CacheSource.none);
    });

    test('withCacheData should set correct properties', () {
      const initial = CacheState<List<String>>();
      final syncTime = DateTime.now();
      final state = initial.withCacheData(['a', 'b'], syncTime);

      expect(state.data, ['a', 'b']);
      expect(state.lastUpdated, syncTime);
      expect(state.source, CacheSource.cache);
      expect(state.isLoading, isTrue); // Still loading network
      expect(state.isFromCache, isTrue);
    });

    test('withNetworkData should set correct properties', () {
      const initial = CacheState<List<String>>();
      final state = initial.withNetworkData(['x', 'y']);

      expect(state.data, ['x', 'y']);
      expect(state.lastUpdated, isNotNull);
      expect(state.source, CacheSource.network);
      expect(state.isLoading, isFalse);
      expect(state.isFromNetwork, isTrue);
    });

    test('withError should set error state', () {
      const initial = CacheState<List<String>>();
      final error = Exception('test error');
      final state = initial.withError(error, 'Error message');

      expect(state.hasError, isTrue);
      expect(state.error, error);
      expect(state.errorMessage, 'Error message');
      expect(state.isLoading, isFalse);
    });

    test('isStale should return true when lastUpdated is null', () {
      const state = CacheState<List<String>>();
      expect(state.isStale, isTrue);
    });

    test('isStale should respect config ttl', () {
      final recentState = CacheState<List<String>>(
        lastUpdated: DateTime.now(),
      );
      final oldState = CacheState<List<String>>(
        lastUpdated: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      expect(recentState.isStale, isFalse);
      expect(oldState.isStale, isTrue);
    });
  });

  group('CacheConfig', () {
    test('default values should be correct', () {
      const config = CacheConfig();

      expect(config.ttlMinutes, 5);
      expect(config.backgroundRefreshThrottleSeconds, 30);
      expect(config.autoInitialize, isTrue);
    });

    test('ttlDuration should return correct duration', () {
      const config = CacheConfig(ttlMinutes: 10);
      expect(config.ttlDuration, const Duration(minutes: 10));
    });

    test('copyWith should work correctly', () {
      const config = CacheConfig();
      final newConfig = config.copyWith(ttlMinutes: 15);

      expect(newConfig.ttlMinutes, 15);
      expect(newConfig.backgroundRefreshThrottleSeconds, 30); // unchanged
    });
  });

  group('CachedRepository', () {
    late MockApi mockApi;
    late TestRepository repository;

    setUp(() {
      mockApi = MockApi();
    });

    tearDown(() async {
      await repository.dispose();
    });

    test('should emit loading state initially', () async {
      when(() => mockApi.fetchItems()).thenAnswer(
        (_) async => [TestItem(id: '1', name: 'Test')],
      );

      repository = TestRepository(mockApi);

      expect(repository.currentState.isLoading, isTrue);
    });

    test('should fetch from remote on initialize', () async {
      final items = [
        TestItem(id: '1', name: 'Item 1'),
        TestItem(id: '2', name: 'Item 2'),
      ];

      when(() => mockApi.fetchItems()).thenAnswer((_) async => items);

      repository = TestRepository(mockApi);
      await repository.initialize();

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      expect(repository.currentState.hasData, isTrue);
      expect(repository.currentState.data, items);
      expect(repository.currentState.source, CacheSource.network);
      verify(() => mockApi.fetchItems()).called(1);
    });

    test('should emit error state on fetch failure', () async {
      when(() => mockApi.fetchItems()).thenThrow(Exception('Network error'));

      repository = TestRepository(mockApi);
      await repository.initialize();

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      expect(repository.currentState.hasError, isTrue);
      expect(repository.currentState.isLoading, isFalse);
    });

    test('refresh should fetch new data', () async {
      when(() => mockApi.fetchItems()).thenAnswer(
        (_) async => [TestItem(id: '1', name: 'Initial')],
      );

      repository = TestRepository(mockApi);
      await repository.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Update mock for refresh
      when(() => mockApi.fetchItems()).thenAnswer(
        (_) async => [TestItem(id: '1', name: 'Refreshed')],
      );

      await repository.refresh();

      expect(repository.currentState.data?.first.name, 'Refreshed');
      verify(() => mockApi.fetchItems()).called(2);
    });

    test('silentRefresh should respect throttle', () async {
      when(() => mockApi.fetchItems()).thenAnswer(
        (_) async => [TestItem(id: '1', name: 'Test')],
      );

      repository = TestRepository(mockApi);
      await repository.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Multiple rapid silent refreshes should be throttled
      // Note: initialize() sets _lastRefreshAttempt, so subsequent silentRefresh
      // calls within the throttle window should be skipped
      await repository.silentRefresh();
      await repository.silentRefresh();
      await repository.silentRefresh();

      // Should only have called once (init), all silentRefresh calls are throttled
      verify(() => mockApi.fetchItems()).called(1);
    });

    test('stream should emit state changes', () async {
      final items = [TestItem(id: '1', name: 'Test')];
      when(() => mockApi.fetchItems()).thenAnswer((_) async => items);

      repository = TestRepository(mockApi);

      final states = <CacheState<List<TestItem>>>[];
      repository.stream.listen(states.add);

      await repository.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Should have emitted: initial loading, then network data
      expect(states.length, greaterThanOrEqualTo(2));
      expect(states.first.isLoading, isTrue);
      expect(states.last.hasData, isTrue);
    });

    test('invalidate should clear cache and reload', () async {
      when(() => mockApi.fetchItems()).thenAnswer(
        (_) async => [TestItem(id: '1', name: 'Test')],
      );

      repository = TestRepository(mockApi);
      await repository.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      await repository.invalidate();
      await Future.delayed(const Duration(milliseconds: 100));

      // Should have fetched twice
      verify(() => mockApi.fetchItems()).called(2);
    });

    test('dispose should close stream', () async {
      when(() => mockApi.fetchItems()).thenAnswer(
        (_) async => [TestItem(id: '1', name: 'Test')],
      );

      repository = TestRepository(mockApi);
      await repository.initialize();
      await repository.dispose();

      expect(
        () => repository.refresh(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
