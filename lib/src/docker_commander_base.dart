import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_commands.dart';
import 'docker_commander_host.dart';

/// The Docker manager.
class DockerCommander extends DockerCMDExecutor {
  static final String VERSION = '2.0.0';

  /// Docker machine host.
  final DockerHost dockerHost;

  DockerCommander(this.dockerHost);

  /// Returns [dockerHost.session]
  int get session => dockerHost.session;

  int _initialized = 0;

  /// Initializes instance.
  Future<bool> initialize() async {
    if (_initialized > 0) return _initialized == 1;
    var hostOk = await dockerHost.initialize();
    hostOk ??= false;
    _initialized = hostOk ? 1 : 2;
    return hostOk;
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
  Future<void> checkDaemon() async {
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

  /// Creates a Docker container with [containerName], [image] and optional [version].
  Future<ContainerInfos> createContainer(
    String containerName,
    String imageName, {
    String version,
    List<String> ports,
    String network,
    String hostname,
    Map<String, String> environment,
    Map<String, String> volumes,
    bool cleanContainer = false,
  }) async {
    await ensureInitialized();
    return dockerHost.createContainer(containerName, imageName,
        version: version,
        ports: ports,
        network: network,
        hostname: hostname,
        environment: environment,
        volumes: volumes,
        cleanContainer: cleanContainer);
  }

  /// Removes a container by [containerNameOrID].
  Future<bool> removeContainer(String containerNameOrID) =>
      dockerHost.removeContainer(containerNameOrID);

  /// Starts a container by [containerNameOrID].
  Future<bool> startContainer(String containerNameOrID) =>
      dockerHost.startContainer(containerNameOrID);

  /// Stops a container by [containerNameOrID] with an optional [timeout].
  Future<bool> stopContainer(String containerNameOrID, {Duration timeout}) =>
      dockerHost.stopByName(containerNameOrID, timeout: timeout);

  /// Runs a Docker container, using [image] and optional [version].
  Future<DockerContainer> run(
    String image, {
    String version,
    List<String> imageArgs,
    String containerName,
    List<String> ports,
    String network,
    String hostname,
    Map<String, String> environment,
    Map<String, String> volumes,
    bool cleanContainer = true,
    bool outputAsLines = true,
    int outputLimit,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
    DockerContainerInstantiator dockerContainerInstantiator,
  }) async {
    await ensureInitialized();

    var runner = await dockerHost.run(
      image,
      version: version,
      imageArgs: imageArgs,
      containerName: containerName,
      ports: ports,
      network: network,
      hostname: hostname,
      environment: environment,
      volumes: volumes,
      cleanContainer: cleanContainer,
      outputAsLines: outputAsLines,
      outputLimit: outputLimit,
      stdoutReadyFunction: stdoutReadyFunction,
      stderrReadyFunction: stderrReadyFunction,
    );

    DockerContainer dockerContainer;

    if (dockerContainerInstantiator != null) {
      dockerContainer = dockerContainerInstantiator(runner);
    }

    dockerContainer ??= DockerContainer(runner);

    return dockerContainer;
  }

  @override
  bool isContainerARunner(String containerName) =>
      dockerHost.isContainerARunner(containerName);

  @override
  bool isContainerRunnerRunning(String containerName) =>
      dockerHost.isContainerRunnerRunning(containerName);

  @override
  Future<DockerProcess> exec(
    String containerName,
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int outputLimit,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
    OutputReadyType outputReadyType,
  }) async {
    await ensureInitialized();
    return dockerHost.exec(containerName, command, args,
        outputAsLines: outputAsLines,
        outputLimit: outputLimit,
        stdoutReadyFunction: stdoutReadyFunction,
        stderrReadyFunction: stderrReadyFunction,
        outputReadyType: outputReadyType);
  }

  @override
  Future<DockerProcess> command(
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int outputLimit,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
    OutputReadyType outputReadyType,
  }) async {
    await ensureInitialized();
    return dockerHost.command(command, args,
        outputAsLines: outputAsLines,
        outputLimit: outputLimit,
        stdoutReadyFunction: stdoutReadyFunction,
        stderrReadyFunction: stderrReadyFunction,
        outputReadyType: outputReadyType);
  }

  /// Executes Docker command `docker ps --format "{{.Names}}"`
  Future<List<String>> psContainerNames({bool all = true}) async =>
      DockerCMD.psContainerNames(this, all: all);

  /// Returns a list of services names.
  Future<List<String>> listServicesNames() async =>
      DockerCMD.listServicesNames(this);

  /// Returns a list of [ServiceTaskInfos] of a service by [serviceName].
  Future<List<ServiceTaskInfos>> listServiceTasks(String serviceName) async =>
      DockerCMD.listServiceTasks(this, serviceName);

  /// Opens a Container logs, by [containerNameOrID].
  Future<DockerProcess> openContainerLogs(String containerNameOrID) =>
      dockerHost.openContainerLogs(containerNameOrID);

  /// Opens a Service logs, by [serviceNameOrTask].
  Future<DockerProcess> openServiceLogs(String serviceNameOrTask) =>
      dockerHost.openServiceLogs(serviceNameOrTask);

  int _networkCounter = 0;

  /// Creates a Docker network with [networkName].
  Future<String> createNetwork([String networkName]) {
    if (isEmptyString(networkName, trim: true)) {
      networkName =
          'docker_commander_network-${dockerHost.session}-${++_networkCounter}';
    }
    return DockerCMD.createNetwork(this, networkName);
  }

  /// Removes a Docker network with [networkName].
  Future<bool /*!*/ > removeNetwork(String networkName) =>
      DockerCMD.removeNetwork(this, networkName);

  /// Returns the container IP by [name].
  Future<String> getContainerIP(String name) async =>
      DockerCMD.getContainerIP(this, name);

  SwarmInfos _swarmInfos;

  /// Returns a [SwarmInfos]. Only if in Swarm mode.
  Future<SwarmInfos> getSwarmInfos() async {
    _swarmInfos ??= await DockerCMD.getSwarmInfos(this);
    return _swarmInfos;
  }

  /// Initialize swarm mode. Returns the secret key to join the cluster.
  Future<SwarmInfos> swarmInit(
      {String advertiseAddress, String listenAddress}) async {
    var swarmInfos = await DockerCMD.swarmInit(this,
        advertiseAddress: advertiseAddress, listenAddress: listenAddress);
    _swarmInfos = swarmInfos;
    return swarmInfos;
  }

  /// Leaves a swarm cluster.
  Future<bool> swarmLeave({bool force = false}) {
    _swarmInfos = null;
    return DockerCMD.swarmLeave(this, force: force);
  }

  /// Returns the node ID of the current Docker Daemon the swarm cluster.
  Future<String> swarmSelfNodeID() => DockerCMD.swarmSelfNodeID(this);

  /// Returns true if this Docker Daemon is in Swarm mode.
  Future<bool> isInSwarmMode() async {
    var myNodeID = await swarmSelfNodeID();
    return isNotEmptyString(myNodeID, trim: true);
  }

  /// Creates a Docker service with [serviceName], [image] and optional [version].
  /// Note that the Docker Daemon should be in Swarm mode.
  Future<Service> createService(
    String serviceName,
    String imageName, {
    String version,
    int replicas,
    List<String> ports,
    String network,
    String hostname,
    Map<String, String> environment,
    Map<String, String> volumes,
  }) async {
    await ensureInitialized();
    return dockerHost.createService(serviceName, imageName,
        version: version,
        replicas: replicas,
        ports: ports,
        network: network,
        hostname: hostname,
        environment: environment,
        volumes: volumes);
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
    return 'DockerCommander{dockerHost: $dockerHost, initialized: $isInitialized. lastDaemonCheck: $lastDaemonCheck}';
  }

  /// Creates a temporary file.
  @override
  Future<String> createTempFile(String content) =>
      dockerHost.createTempFile(content);

  /// Deletes a temporary [filePath].
  @override
  Future<bool> deleteTempFile(String filePath) =>
      dockerHost.deleteTempFile(filePath);
}

typedef DockerContainerInstantiator = DockerContainer Function(
    DockerRunner runner);

/// A Docker container being executed.
class DockerContainer {
  final DockerRunner /*!*/ runner;

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
  Future<DockerProcess> exec(
    String /*!*/ command,
    List<String> args, {
    bool outputAsLines = true,
    int outputLimit,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
    OutputReadyType outputReadyType,
  }) {
    if (!isRunning) {
      return null;
    }
    return runner.dockerHost.exec(name, command, args,
        outputAsLines: outputAsLines,
        outputLimit: outputLimit,
        stdoutReadyFunction: stdoutReadyFunction,
        stderrReadyFunction: stderrReadyFunction,
        outputReadyType: outputReadyType);
  }

  /// Calls [exec] than [waitExit].
  Future<int> execAndWaitExit(String command, List<String> args) async {
    var process = await exec(command, args);
    return process.waitExit();
  }

  /// Calls [exec] than [waitStdout].
  Future<Output> execAndWaitStdout(String command, List<String> args,
      {int desiredExitCode}) async {
    var process = await exec(command, args);
    return process.waitStdout(desiredExitCode: desiredExitCode);
  }

  /// Calls [exec] than [waitStderr].
  Future<Output> execAndWaitStderr(String command, List<String> args,
      {int desiredExitCode}) async {
    var process = await exec(command, args);
    return process.waitStderr(desiredExitCode: desiredExitCode);
  }

  /// Calls [execAndWaitStdoutAsString] and returns [Output.asString].
  Future<String> execAndWaitStdoutAsString(String command, List<String> args,
      {bool trim = false, int desiredExitCode}) async {
    var output = await execAndWaitStdout(command, args,
        desiredExitCode: desiredExitCode);
    return _waitOutputAsString(output, trim);
  }

  /// Calls [execAndWaitStderrAsString] and returns [Output.asString].
  Future<String> execAndWaitStderrAsString(String command, List<String> args,
      {bool trim = false, int desiredExitCode}) async {
    var output = await execAndWaitStderr(command, args,
        desiredExitCode: desiredExitCode);
    return _waitOutputAsString(output, trim);
  }

  String _waitOutputAsString(Output output, bool trim) {
    if (output == null) return null;
    var s = output.asString;
    if (trim ?? false) {
      s = s.trim();
    }
    return s;
  }

  /// Call POSIX `which` command.
  /// Calls [exec] with command `which` and args [commandName].
  /// Caches response than returns the executable path for [commandName].
  Future<String> execWhich(String commandName,
          {bool ignoreCache, String def}) async =>
      runner.dockerHost
          .execWhich(name, commandName, ignoreCache: ignoreCache, def: def);

  /// Call POSIX `cat` command.
  /// Calls [exec] with command `cat` and args [filePath].
  /// Returns the executable path for [filePath].
  Future<String> execCat(String filePath, {bool trim = false}) async {
    return DockerCMD.execCat(runner.dockerHost, name, filePath, trim: trim);
  }

  /// Executes a shell [script]. Tries to use `bash` or `sh`.
  /// Note that [script] should be inline, without line breaks (`\n`).
  Future<DockerProcess> execShell(String script, {bool sudo = false}) async =>
      DockerCMD.execShell(runner.dockerHost, name, script, sudo: sudo);

  /// Save the file [filePath] with [content], inside this container.
  Future<bool> putFileContent(String filePath, String content,
          {bool sudo = false, bool append = false}) async =>
      DockerCMD.putFileContent(runner.dockerHost, name, filePath, content,
          sudo: sudo, append: append);

  /// Append to the file [filePath] with [content], inside this container.
  Future<bool> appendFileContent(String filePath, String content,
          {bool sudo = false}) async =>
      DockerCMD.appendFileContent(runner.dockerHost, name, filePath, content,
          sudo: sudo);

  /// Copy a host file, at [hostFilePath], inside this container,
  /// with internal file path [containerFilePath].
  Future<bool> copyFileToContainer(
          String hostFilePath, String containerFilePath) =>
      DockerCMD.copyFileToContainer(
          runner.dockerHost, name, hostFilePath, containerFilePath);

  /// Copy a file inside this container, with path [containerFilePath],
  /// to the host machine, at [hostFilePath].
  Future<bool> copyFileFromContainer(
          String containerFilePath, String hostFilePath) =>
      DockerCMD.copyFileFromContainer(
          runner.dockerHost, name, containerFilePath, hostFilePath);

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

  /// Opens this Container logs:
  Future<DockerProcess> openLogs(String containerNameOrID) =>
      runner.dockerHost.openContainerLogs(name);

  /// Returns this Container logs as [String].
  Future<String> catLogs({
    bool stderr = false,
    Pattern waitDataMatcher,
    Duration waitDataTimeout,
    bool waitExit = false,
    int desiredExitCode,
    bool follow = false,
  }) =>
      runner.dockerHost.catContainerLogs(name,
          stderr: stderr,
          waitDataMatcher: waitDataMatcher,
          waitDataTimeout: waitDataTimeout,
          waitExit: waitExit,
          desiredExitCode: desiredExitCode,
          follow: follow);
}
