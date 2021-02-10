import 'package:docker_commander/src/docker_commander_host.dart';

class DockerCommander {
  final DockerHost dockerHost;

  DockerCommander(this.dockerHost);

  int _initialized = 0;

  Future<bool> initialize() async {
    if (_initialized > 0) return _initialized == 1;
    var hostOk = await dockerHost.initialize();
    var ok = hostOk;
    _initialized = ok ? 1 : 2;
    return ok;
  }

  bool get isInitialized => _initialized > 0;

  bool get isSuccessfullyInitialized => _initialized == 1;

  void ensureInitialized() async {
    if (!isInitialized) {
      await initialize();
    }
  }

  DateTime _lastDaemonCheck;

  DateTime get lastDaemonCheck => _lastDaemonCheck;

  void checkDaemon() async {
    await ensureInitialized();

    if (!(await isDaemonRunning())) {
      throw StateError('Docker Daemon not running. DockerHost: $dockerHost');
    }

    _lastDaemonCheck = DateTime.now();
  }

  Future<bool> isDaemonRunning() async {
    return dockerHost.checkDaemon();
  }

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

  Future<void> close() async {
    return dockerHost.close();
  }

  @override
  String toString() {
    return 'DockerCommander{dockerHost: $dockerHost, lastDaemonCheck: $lastDaemonCheck}';
  }
}

class DockerContainer {
  final DockerRunner runner;

  DockerContainer(this.runner);

  int get instanceID => runner.instanceID;

  String get name => runner.name;

  String get id => runner.id;

  Future<bool> waitReady() => runner.waitReady();

  Future<int> waitExit() => runner.waitExit();

  Output get stdout => runner.stdout;

  Output get stderr => runner.stderr;

  @override
  String toString() {
    return 'DockerContainer{runner: $runner}';
  }
}
