# Flutter Dual Cache

A reusable Flutter repository module implementing **Stale-While-Revalidate** dual-track caching strategy with Hive storage.

## Features

- **Dual-Track Caching**: Instantly display cached data, then update with fresh network data
- **Framework Agnostic**: Returns `Stream<CacheState<T>>`, works with any state management (Riverpod, Bloc, Provider, etc.)
- **Hive Storage**: Fast, efficient local caching using Hive
- **Extensible**: Easy to subclass and customize with hooks
- **Configurable**: TTL, throttle, and other cache behaviors
- **Type Safe**: Full generic support with strongly typed entities

## Installation

### As Git Dependency

```yaml
# pubspec.yaml
dependencies:
  flutter_dual_cache:
    git:
      url: https://github.com/your-org/flutter_dual_cache.git
      ref: main
```

### As Local Package

```yaml
# pubspec.yaml
dependencies:
  flutter_dual_cache:
    path: ../packages/flutter_dual_cache
```

## Quick Start

### 1. Initialize Hive

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(MyApp());
}
```

### 2. Create a Repository

```dart
import 'package:flutter_dual_cache/flutter_dual_cache.dart';

class TaskRepository extends CachedRepository<Task, String> {
  final ApiClient _apiClient;

  TaskRepository(this._apiClient) : super(boxName: 'tasks_cache');

  @override
  Future<List<Task>> fetchFromRemote() => _apiClient.getTasks();

  @override
  Map<String, dynamic> toJson(Task item) => item.toJson();

  @override
  Task fromJson(Map<String, dynamic> json) => Task.fromJson(json);

  @override
  String getId(Task item) => item.id;
}
```

### 3. Use in UI

```dart
class TaskListPage extends StatelessWidget {
  final TaskRepository repository;

  const TaskListPage({required this.repository});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CacheState<List<Task>>>(
      stream: repository.stream,
      builder: (context, snapshot) {
        final state = snapshot.data;

        // Show loading indicator
        if (state == null || (state.isLoading && !state.hasData)) {
          return const Center(child: CircularProgressIndicator());
        }

        // Show error (with cached data if available)
        if (state.hasError && !state.hasData) {
          return Center(child: Text('Error: ${state.errorMessage}'));
        }

        // Show data with optional loading overlay
        return Stack(
          children: [
            ListView.builder(
              itemCount: state.data!.length,
              itemBuilder: (_, i) => TaskTile(task: state.data![i]),
            ),
            if (state.isLoading)
              const Positioned(
                top: 8,
                right: 8,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        );
      },
    );
  }
}
```

## Integration Examples

### With Riverpod

```dart
// providers.dart
final taskRepositoryProvider = Provider((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TaskRepository(apiClient);
});

final taskStreamProvider = StreamProvider((ref) {
  return ref.watch(taskRepositoryProvider).stream;
});

// task_page.dart
class TaskPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskState = ref.watch(taskStreamProvider);

    return taskState.when(
      data: (state) {
        if (!state.hasData) return const LoadingWidget();
        return TaskList(tasks: state.data!);
      },
      loading: () => const LoadingWidget(),
      error: (e, _) => ErrorWidget(message: e.toString()),
    );
  }
}
```

### With Bloc

```dart
class TaskBloc extends Bloc<TaskEvent, TaskState> {
  final TaskRepository _repository;
  StreamSubscription? _subscription;

  TaskBloc(this._repository) : super(TaskInitial()) {
    on<TaskStarted>(_onStarted);
    on<TaskRefreshed>(_onRefreshed);
    on<_TaskDataChanged>(_onDataChanged);
  }

  void _onStarted(TaskStarted event, Emitter emit) {
    _subscription = _repository.stream.listen(
      (state) => add(_TaskDataChanged(state)),
    );
  }

  void _onDataChanged(_TaskDataChanged event, Emitter emit) {
    final cacheState = event.state;
    if (cacheState.hasData) {
      emit(TaskLoaded(cacheState.data!));
    } else if (cacheState.hasError) {
      emit(TaskError(cacheState.errorMessage!));
    }
  }

  Future<void> _onRefreshed(TaskRefreshed event, Emitter emit) async {
    await _repository.refresh();
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
```

## Configuration

```dart
class TaskRepository extends CachedRepository<Task, String> {
  TaskRepository(ApiClient api) : super(
    boxName: 'tasks_cache',
    config: const CacheConfig(
      ttlMinutes: 10,                      // Cache TTL (default: 5)
      backgroundRefreshThrottleSeconds: 60, // Throttle (default: 30)
      autoInitialize: true,                // Auto-init (default: true)
    ),
  );
  // ...
}
```

## Customization Hooks

```dart
class TaskRepository extends CachedRepository<Task, String> {
  // ...

  @override
  List<Task> transformForCache(List<Task> data) {
    // Filter before caching (e.g., remove deleted items)
    return data.where((t) => !t.isDeleted).toList();
  }

  @override
  List<Task> transformForDisplay(List<Task> data) {
    // Filter/sort before displaying (e.g., hide archived)
    return data.where((t) => t.status != 'archived').toList();
  }

  @override
  void onFetchError(Object error, StackTrace stackTrace) {
    // Custom error handling/logging
    analytics.logError('TaskFetch', error, stackTrace);
  }
}
```

## API Reference

### CachedRepository Methods

| Method | Description |
|--------|-------------|
| `stream` | Stream of `CacheState` for UI binding |
| `currentState` | Current state snapshot |
| `refresh()` | Force refresh from network (shows loading) |
| `silentRefresh()` | Background refresh (no loading indicator) |
| `invalidate()` | Clear cache and reload |
| `getById(id)` | Get single item from cache |
| `dispose()` | Clean up resources |

### CacheState Properties

| Property | Type | Description |
|----------|------|-------------|
| `data` | `T?` | The cached data |
| `isLoading` | `bool` | Loading indicator |
| `source` | `CacheSource` | `cache`, `network`, or `none` |
| `lastUpdated` | `DateTime?` | Last sync timestamp |
| `hasData` | `bool` | Whether data is available |
| `hasError` | `bool` | Whether error occurred |
| `errorMessage` | `String?` | Error description |
| `isStale` | `bool` | Whether cache is expired |

## Data Flow

```
┌────────────────────────────────────────────────┐
│              CachedRepository                  │
├────────────────────────────────────────────────┤
│                                                │
│   1. init()                                    │
│      │                                         │
│      ├──▶ Read from Hive ──▶ Emit (cache)     │
│      │                                         │
│      └──▶ Fetch from API ──▶ Save to Hive     │
│                           └──▶ Emit (network)  │
│                                                │
│   2. refresh()                                 │
│      │                                         │
│      └──▶ Fetch from API ──▶ Save to Hive     │
│                           └──▶ Emit (network)  │
│                                                │
│   3. silentRefresh() (throttled)               │
│      │                                         │
│      └──▶ Same as refresh, no loading state   │
│                                                │
└────────────────────────────────────────────────┘
```

## Testing

```bash
cd packages/flutter_dual_cache
flutter test
```

## License

MIT
