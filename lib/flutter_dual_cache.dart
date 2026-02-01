/// A reusable Flutter repository module implementing Stale-While-Revalidate
/// dual-track caching strategy with Hive storage.
///
/// ## Features
///
/// - **Dual-Track Caching**: Instantly display cached data, then update with
///   fresh network data
/// - **Framework Agnostic**: Returns `Stream<CacheState<T>>`, works with any
///   state management solution
/// - **Hive Storage**: Fast, efficient local caching using Hive
/// - **Extensible**: Easy to subclass and customize
///
/// ## Quick Start
///
/// 1. Create a repository by extending [CachedRepository]:
///
/// ```dart
/// class TaskRepository extends CachedRepository<Task, String> {
///   final ApiClient _api;
///
///   TaskRepository(this._api) : super(boxName: 'tasks');
///
///   @override
///   Future<List<Task>> fetchFromRemote() => _api.getTasks();
///
///   @override
///   Map<String, dynamic> toJson(Task t) => t.toJson();
///
///   @override
///   Task fromJson(Map<String, dynamic> json) => Task.fromJson(json);
///
///   @override
///   String getId(Task t) => t.id;
/// }
/// ```
///
/// 2. Listen to the stream in your UI:
///
/// ```dart
/// StreamBuilder<CacheState<List<Task>>>(
///   stream: taskRepo.stream,
///   builder: (context, snapshot) {
///     final state = snapshot.data;
///     if (state?.hasData ?? false) {
///       return TaskList(tasks: state!.data!);
///     }
///     return LoadingIndicator();
///   },
/// )
/// ```
///
/// ## Initialization
///
/// Before using the repository, ensure Hive is initialized in your app:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Hive.initFlutter();
///   runApp(MyApp());
/// }
/// ```
library flutter_dual_cache;

// Core
export 'src/core/cache_config.dart';
export 'src/core/cache_state.dart';

// Storage
export 'src/storage/hive_cache_storage.dart';

// Repository
export 'src/repository/cached_repository.dart';
