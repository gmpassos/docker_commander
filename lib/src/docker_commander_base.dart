import 'package:docker_commander/src/docker_commander_host.dart';

/// The Docker manager.
class DockerCommander {
  /// Docker machine host.
  final DockerHost dockerHost;

  DockerCommander(this.dockerHost);

  int _initialized = 0;

  /// Initializes instance.
  Future<bool> initialize() async {
    if (_initialized > 0) return _initialized == 1;
    var hostOk = await dockerHost.initialize();
    var ok = hostOk;
    _initialized = ok ? 1 : 2;
    return ok;
  }

  /// Returns [true] if is initialized, even if is initialized with errors.
  bool get isInitialized => _initialized > 0;

  /// Returns [true] if is successfully initialized.
  bool get isSuccessfullyInitialized => _initialized == 1;

  /// Ensures that this instance is initialized.
  Future<void> ensureInitialized() async {
    if (!isInitialized) {
      await initialize();
    }
  }

  DateTime _lastDaemonCheck;

  /// Returns the last [DateTime] that Docker daemon was checked.
  DateTime get lastDaemonCheck => _lastDaemonCheck;

  /// Checks if Docker daemon is accessible.
  void checkDaemon() async {
    await ensureInitialized();

    if (!(await isDaemonRunning())) {
      throw StateError('Docker Daemon not running. DockerHost: $dockerHost');
    }

    _lastDaemonCheck = DateTime.now();
  }

  /// Returns [true] if Docker daemon is accessible.
  Future<bool> isDaemonRunning() async {
    return dockerHost.checkDaemon();
  }

  /// Runs a Docker container, using [image] and optional [verion].
  Future<DockerContainer> run(
    String image, {
    String version,
    String name,
    bool cleanContainer = true,
    bool outputAsLines = true,
    int outputLimit,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
  }) async {
    await ensureInitialized();

    var run = await dockerHost.run(
      image,
      version: version,
      name: name,
      cleanContainer: cleanContainer,
      outputAsLines: outputAsLines,
      outputLimit: outputLimit,
      stdoutReadyFunction: stdoutReadyFunction,
      stderrReadyFunction: stderrReadyFunction,
    );

    return DockerContainer(run);
  }

  /// Closes this instances, and internal [dockerHost].
  Future<void> close() async {
    return dockerHost.close();
  }

  @override
  String toString() {
    return 'DockerCommander{dockerHost: $dockerHost, lastDaemonCheck: $lastDaemonCheck}';
  }
}

/// A Docker container being executed.
class DockerContainer {
  final DockerRunner runner;

  DockerContainer(this.runner);

  /// Dart instance ID.
  int get instanceID => runner.instanceID;

  /// Name of the Docker container.
  String get name => runner.name;

  /// ID of the Docker container.
  String get id => runner.id;

  /// Waits for the container, ensuring that is started.
  Future<bool> waitReady() => runner.waitReady();

  /// Waits container to exit. Returns the process exit code.
  Future<int> waitExit() => runner.waitExit();

  /// The `STDOUT` of the container.
  Output get stdout => runner.stdout;

  /// The `STDERR` of the container.
  Output get stderr => runner.stderr;

  @override
  String toString() {
    return 'DockerContainer{runner: $runner}';
  }
}
