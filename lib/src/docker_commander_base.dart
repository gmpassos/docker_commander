import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_host.dart';

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
    List<String> imageArgs,
    String containerName,
    List<String> ports,
    String network,
    String hostname,
    Map<String, String> environment,
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
      imageArgs: imageArgs,
      containerName: containerName,
      ports: ports,
      network: network,
      hostname: hostname,
      environment: environment,
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
    try {
      return dockerHost.close();
    }
    // ignore: empty_catches
    catch (e) {}
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
  String get name => runner.containerName;

  /// ID of the Docker container.
  String get id => runner.id;

  /// Waits for the container, ensuring that is started.
  Future<bool> waitReady() => runner.waitReady();

  /// Waits container to exit. Returns the process exit code.
  Future<int> waitExit() => runner.waitExit();

  /// Returns [true] if this container is started and ready.
  bool get isReady => runner.isReady;

  /// Returns [true] if this containers is running.
  bool get isRunning => runner.isRunning;

  /// Executes a [command] inside this container with [args]
  /// (if [isRunning] or returns null).
  Future<DockerProcess> exec(String command, List<String> args) {
    if (!isRunning) {
      return null;
    }
    return runner.dockerHost.exec(name, command, args);
  }

  /// Calls [exec] than [waitExit].
  Future<int> execAndWaitExit(String command, List<String> args) async {
    var process = await exec(command, args);
    return process.waitExit();
  }

  /// Calls [exec] than [waitStdout].
  Future<Output> execAndWaitStdout(String command, List<String> args) async {
    var process = await exec(command, args);
    return process.waitStdout();
  }

  /// Calls [exec] than [waitStderr].
  Future<Output> execAndWaitStderr(String command, List<String> args) async {
    var process = await exec(command, args);
    return process.waitStderr();
  }

  /// Calls [execAndWaitStdoutAsString] and returns [Output.asString].
  Future<String> execAndWaitStdoutAsString(String command, List<String> args,
      {bool trim = false}) async {
    var output = await execAndWaitStdout(command, args);
    if (output == null) return null;
    var s = output.asString;
    if (trim ?? false) {
      s = s.trim();
    }
    return s;
  }

  /// Calls [execAndWaitStderrAsString] and returns [Output.asString].
  Future<String> execAndWaitStderrAsString(String command, List<String> args,
      {bool trim = false}) async {
    var output = await execAndWaitStderr(command, args);
    if (output == null) return null;
    var s = output.asString;
    if (trim ?? false) {
      s = s.trim();
    }
    return s;
  }

  final Map<String, String> _whichCache = {};

  /// Call POSIX `which` command.
  /// Calls [exec] with command `which` and args [commandName].
  /// Caches response than returns the executable path for [commandName].
  Future<String> execWhich(String commandName, {bool ignoreCache}) async {
    ignoreCache ??= false;

    var cached = !ignoreCache ? _whichCache[commandName] : null;
    if (cached != null) {
      return cached.isNotEmpty ? cached : null;
    }

    var path =
        await execAndWaitStdoutAsString('which', [commandName], trim: true);
    path ??= '';

    _whichCache[commandName] = path;
    return path.isNotEmpty ? path : null;
  }

  /// Call POSIX `cat` command.
  /// Calls [exec] with command `cat` and args [filePath].
  /// Returns the executable path for [filePath].
  Future<String> execCat(String filePath, {bool trim = false}) async {
    var catBin = await execWhich('cat');
    catBin ??= '/bin/cat';
    var content =
        await execAndWaitStdoutAsString(catBin, [filePath], trim: trim);
    return content;
  }

  /// Stops this container.
  Future<bool> stop({Duration timeout}) => runner.stop(timeout: timeout);

  /// The `STDOUT` of the container.
  Output get stdout => runner.stdout;

  /// The `STDERR` of the container.
  Output get stderr => runner.stderr;

  /// List of mapped ports.
  List<String> get ports => runner.ports;

  /// List of mapped ports as [Pair<int>].
  List<Pair<int>> get portsAsPair => ports?.map((e) {
        var parts = e.split(':');
        return Pair(parseInt(parts[0]), parseInt(parts[1]));
      })?.toList();

  /// List of host ports.
  List<int> get hostPorts => portsAsPair?.map((e) => e.a)?.toList();

  /// List of container ports.
  List<int> get containerPorts => portsAsPair?.map((e) => e.b)?.toList();

  @override
  String toString() {
    return 'DockerContainer{runner: $runner}';
  }
}
