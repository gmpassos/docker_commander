import 'dart:async';
import 'dart:convert';

import 'package:docker_commander/docker_commander.dart';
import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_commands.dart';

final _LOG = Logger('docker_commander/host');

/// Basic infos of a Container.
class ContainerInfos {
  final String containerName;
  String id;
  final String image;
  final List<String> ports;
  final String containerNetwork;
  final String containerHostname;
  List<String> args;

  ContainerInfos(this.containerName, this.id, this.image, this.ports,
      this.containerNetwork, this.containerHostname,
      [this.args]);

  @override
  String toString() {
    return 'ContainerInfos{containerName: $containerName, id: $id; image: $image, ports: $ports, containerNetwork: $containerNetwork, containerHostname: $containerHostname}';
  }
}

/// Base class for Docker Swarm infos.
class SwarmInfos {
  final String nodeID;
  final String managerToken;
  final String workerToken;
  final String advertiseAddress;

  SwarmInfos(
      this.nodeID, this.managerToken, this.workerToken, this.advertiseAddress);

  @override
  String toString() {
    return 'SwarmInfos{nodeID: $nodeID, managerToken: $managerToken, workerToken: $workerToken, advertiseAddress: $advertiseAddress}';
  }
}

/// Base class for a Docker Service.
class Service {
  final DockerHost dockerHost;

  final String serviceName;
  String id;
  final String image;
  final List<String> ports;
  final String containerNetwork;
  final String containerHostname;
  List<String> args;

  Service(this.dockerHost, this.serviceName, this.id, this.image, this.ports,
      this.containerNetwork, this.containerHostname,
      [this.args]);

  /// Returns a list of [ServiceTaskInfos] of this service.
  Future<List<ServiceTaskInfos>> listTasks() =>
      dockerHost.listServiceTasks(serviceName);

  /// Removes this service from Swarm cluster.
  Future<bool> remove() => dockerHost.removeService(serviceName);

  @override
  String toString() {
    return 'ServiceInfos{containerName: $serviceName, id: $id; image: $image, ports: $ports, containerNetwork: $containerNetwork, containerHostname: $containerHostname}';
  }

  /// Opens this Service logs.
  Future<DockerProcess> openLogs(String serviceNameOrTask) =>
      dockerHost.openServiceLogs(serviceNameOrTask);

  /// Returns this Service logs as [String].
  Future<String> catLogs({
    String taskName,
    int taskNumber,
    bool stderr = false,
    Pattern waitDataMatcher,
    Duration waitDataTimeout,
    bool waitExit = false,
    int desiredExitCode,
  }) {
    var name = isNotEmptyString(taskName) ? taskName : serviceName;

    if (taskNumber != null && taskNumber > 0) {
      name = '$serviceName.$taskNumber';
    }

    return dockerHost.catServiceLogs(name,
        stderr: stderr,
        waitDataMatcher: waitDataMatcher,
        waitDataTimeout: waitDataTimeout,
        waitExit: waitExit,
        desiredExitCode: desiredExitCode);
  }
}

/// Service Task infos.
class ServiceTaskInfos {
  final String id;
  final String name;
  final String serviceName;
  final String image;
  final String node;
  final String desiredState;
  final String currentState;
  final String ports;
  final String error;

  ServiceTaskInfos(
    this.id,
    this.name,
    this.serviceName,
    this.image,
    this.node,
    this.desiredState,
    this.currentState,
    this.ports,
    this.error,
  );

  bool get isCurrentlyRunning =>
      (currentState ?? '').toLowerCase().contains('running');

  @override
  String toString() {
    return 'ServiceTaskInfos{id: $id, name: $name, serviceName: $serviceName, image: $image, node: $node, desiredState: $desiredState, currentState: $currentState, ports: $ports, error: $error}';
  }
}

/// Base class for Docker machine host.
abstract class DockerHost extends DockerCMDExecutor {
  final int session;

  DockerHost() : session = DateTime.now().millisecondsSinceEpoch;

  /// Initializes instance.
  Future<bool> initialize();

  static List<String> normalizeMappedPorts(List<String> ports) {
    if (ports == null) return null;
    var ports2 = ports
        .where((e) => isNotEmptyString(e, trim: true))
        .map((e) => e.trim())
        .toList();

    var portsSet = ports2.map((pair) {
      var parts = pair.split(':');
      var p1 = parseInt(parts[0]);
      var p2 = parts.length > 1 ? parseInt(parts[1], p1) : p1;
      return '$p1:$p2';
    }).toSet();

    return portsSet.isNotEmpty ? portsSet.toList() : null;
  }

  static OutputReadyType resolveOutputReadyType(
      OutputReadyFunction stdoutReadyFunction,
      OutputReadyFunction stderrReadyFunction) {
    var outputReadyType = OutputReadyType.STDOUT;

    if ((stdoutReadyFunction != null && stderrReadyFunction != null) ||
        (stdoutReadyFunction == null && stderrReadyFunction == null)) {
      outputReadyType = OutputReadyType.ANY;
    } else if (stdoutReadyFunction != null) {
      outputReadyType = OutputReadyType.STDOUT;
    } else if (stderrReadyFunction != null) {
      outputReadyType = OutputReadyType.STDERR;
    }
    return outputReadyType;
  }

  /// Creates a Docker containers with [image] and optional [version].
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
  });

  /// Removes a container by [containerNameOrID].
  Future<bool> removeContainer(String containerNameOrID) =>
      DockerCMD.removeContainer(this, containerNameOrID);

  /// Starts a container by [containerNameOrID].
  Future<bool> startContainer(String containerNameOrID) =>
      DockerCMD.startContainer(this, containerNameOrID);

  /// Runs a Docker containers with [image] and optional [version].
  Future<DockerRunner> run(
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
    OutputReadyType outputReadyType,
  });

  /// Executes a [command] inside [containerName] with [args].
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
  });

  /// Executes an arbitrary Docker [command] with [args].
  @override
  Future<DockerProcess> command(
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int outputLimit,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
    OutputReadyType outputReadyType,
  });

  ContainerInfos buildContainerArgs(
    String cmd,
    String imageName,
    String version,
    String containerName,
    List<String> ports,
    String network,
    String hostname,
    Map<String, String> environment,
    Map<String, String> volumes,
    bool cleanContainer,
  ) {
    var image = DockerHost.resolveImage(imageName, version);

    ports = DockerHost.normalizeMappedPorts(ports);

    var args = <String>[
      if (isNotEmptyString(cmd)) cmd,
      '--name',
      containerName,
    ];

    if (cleanContainer ?? true) {
      args.add('--rm');
    }

    if (ports != null) {
      for (var pair in ports) {
        args.add('-p');
        args.add(pair);
      }
    }

    String containerNetwork;

    if (isNotEmptyString(network, trim: true)) {
      containerNetwork = network.trim();
      args.add('--net');
      args.add(containerNetwork);
    }

    String containerHostname;

    if (isNotEmptyString(hostname, trim: true)) {
      containerHostname = hostname.trim();
      args.add('-h');
      args.add(containerHostname);
    }

    volumes?.forEach((k, v) {
      if (isNotEmptyString(k) && isNotEmptyString(k)) {
        args.add('-v');
        args.add('$k:$v');
      }
    });

    environment?.forEach((k, v) {
      if (isNotEmptyString(k)) {
        args.add('-e');
        args.add('$k=$v');
      }
    });

    args.add(image);

    return ContainerInfos(containerName, null, image, ports, containerNetwork,
        containerHostname, args);
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
    if (isEmptyString(serviceName, trim: true)) {
      return null;
    }

    var containerInfos = buildContainerArgs(
      'create',
      imageName,
      version,
      serviceName,
      ports,
      network,
      hostname,
      environment,
      volumes,
      false,
    );

    var cmdArgs = containerInfos.args;

    cmdArgs.removeLast();

    if (replicas != null && replicas > 1) {
      cmdArgs.add('--replicas');
      cmdArgs.add('$replicas');
    }

    cmdArgs.add(containerInfos.image);

    _LOG.info('Service create[CMD]>\t${cmdArgs.join(' ')}');

    var process = await command('service', cmdArgs);

    var exitCodeOK = await process.waitExitAndConfirm(0);
    if (!exitCodeOK) return null;

    var id = await getServiceIDByName(containerInfos.containerName);

    return Service(
        this,
        containerInfos.containerName,
        id,
        containerInfos.image,
        containerInfos.ports,
        containerInfos.containerNetwork,
        containerInfos.containerHostname);
  }

  /// Opens a Container logs, by [containerNameOrID].
  Future<DockerProcess> openContainerLogs(String containerNameOrID) =>
      DockerCMD.openContainerLogs(this, containerNameOrID);

  /// Opens a Service logs, by [serviceNameOrTask].
  Future<DockerProcess> openServiceLogs(String serviceNameOrTask) =>
      DockerCMD.openServiceLogs(this, serviceNameOrTask);

  /// Returns the Container logs as [String].
  Future<String> catContainerLogs(
    String containerNameOrID, {
    bool stderr = false,
    Pattern waitDataMatcher,
    Duration waitDataTimeout,
    bool waitExit = false,
    int desiredExitCode,
  }) =>
      DockerCMD.catContainerLogs(this, containerNameOrID,
          stderr: stderr,
          waitDataMatcher: waitDataMatcher,
          waitDataTimeout: waitDataTimeout,
          waitExit: waitExit,
          desiredExitCode: desiredExitCode);

  /// Returns a Service logs as [String].
  Future<String> catServiceLogs(
    String containerNameOrID, {
    bool stderr = false,
    Pattern waitDataMatcher,
    Duration waitDataTimeout,
    bool waitExit = false,
    int desiredExitCode,
  }) =>
      DockerCMD.catServiceLogs(this, containerNameOrID,
          stderr: stderr,
          waitDataMatcher: waitDataMatcher,
          waitDataTimeout: waitDataTimeout,
          waitExit: waitExit,
          desiredExitCode: desiredExitCode);

  /// Returns a [List<int>] of [DockerRunner] `instanceID`.
  List<int> getRunnersInstanceIDs();

  /// Returns a [List<String>] of [DockerRunner] `name`.
  List<String> getRunnersNames();

  /// Returns a [DockerRunner] with [instanceID].
  DockerRunner getRunnerByInstanceID(int instanceID);

  /// Returns a [DockerRunner] with [name].
  DockerRunner getRunnerByName(String name);

  /// Returns a [DockerProcess] with [instanceID].
  DockerProcess getProcessByInstanceID(int instanceID);

  /// Stops a container by [instanceID].
  Future<bool> stopByInstanceID(int instanceID, {Duration timeout}) async {
    var runner = getRunnerByInstanceID(instanceID);
    if (runner == null) return false;
    return stopByName(runner.containerName, timeout: timeout);
  }

  /// Stops a container by [name].
  Future<bool> stopByName(String name, {Duration timeout});

  /// Stops all [DockerRunner] returned by [getRunnersInstanceIDs].
  Future<void> stopRunners() async {
    var instancesIDs = getRunnersInstanceIDs();

    for (var instanceID in instancesIDs) {
      await stopByInstanceID(instanceID);
    }
  }

  /// Checks if Docker daemon is running.
  Future<bool> checkDaemon();

  /// Returns a Docker container ID with [name].
  Future<String> getContainerIDByName(String name) =>
      DockerCMD.getContainerIDByName(this, name);

  /// Returns a Docker service ID with [name].
  Future<String> getServiceIDByName(String name) =>
      DockerCMD.getServiceIDByName(this, name);

  /// Returns a list of [ServiceTaskInfos] of a service by [serviceName].
  Future<List<ServiceTaskInfos>> listServiceTasks(String name) =>
      DockerCMD.listServiceTasks(this, name);

  /// Removes a service from the Swarm cluster by [name].
  Future<bool> removeService(String name) =>
      DockerCMD.removeService(this, name);

  static void cleanupExitedProcessesImpl(
      Duration exitedProcessExpireTime, Map<int, DockerProcess> _processes) {
    var expireTime = exitedProcessExpireTime.inMilliseconds;
    var now = DateTime.now().millisecondsSinceEpoch;

    for (var instanceID in _processes.keys.toList()) {
      var process = _processes[instanceID];
      assert(process.instanceID == instanceID);

      var exitTime = process.exitTime;
      if (exitTime == null) continue;

      assert(process.exitCode != null);

      var exitElapsedTime = now - exitTime.millisecondsSinceEpoch;

      if (exitElapsedTime > expireTime) {
        _processes.remove(instanceID);
      }
    }
  }

  /// Resolves a Docker image, composed by [imageName] and [version].
  static String resolveImage(String imageName, [String version]) {
    var image = imageName.trim();

    if (isNotEmptyString(version, trim: true)) {
      version = version.trim();
      var idx = image.lastIndexOf(':');
      if (idx > 0) {
        image = image.substring(0, idx);
      }
      image += ':$version';
    }

    return image;
  }

  /// Closes this instance, cleaning any resource.
  Future<void> close();
}

/// Represents a Docker container running.
abstract class DockerRunner extends DockerProcess {
  DockerRunner(DockerHost dockerHost, int instanceID, String containerName)
      : super(dockerHost, instanceID, containerName);

  /// The ID of this container.
  String get id;

  /// The image:version of this container.
  String get image;

  /// Returns the mapped ports.
  List<String> get ports;

  /// Stops this container.
  Future<bool> stop({Duration timeout}) =>
      dockerHost.stopByInstanceID(instanceID, timeout: timeout);

  @override
  String toString() {
    return 'DockerRunner{id: $id, instanceID: $instanceID, containerName: $containerName, ready: $isReady, dockerHost: $dockerHost}';
  }
}

abstract class DockerProcess {
  static int _instanceIDCounter = 0;

  static int incrementInstanceID() => ++_instanceIDCounter;

  /// [DockerHost] where this container is running.
  final DockerHost dockerHost;

  /// The internal instanceID in [DockerCommander].
  final int instanceID;

  /// The name of the associated container.
  final String containerName;

  DockerProcess(this.dockerHost, this.instanceID, this.containerName);

  static final int DEFAULT_OUTPUT_LIMIT = 1000;

  Output _stdout;

  Output _stderr;

  OutputReadyType _outputReadyType;

  /// The STDOUT of this container.
  Output get stdout => _stdout;

  /// The STDERR of this container.
  Output get stderr => _stderr;

  /// The ready output behavior.
  OutputReadyType get outputReadyType => _outputReadyType;

  void setupStdout(OutputStream outputStream) {
    _stdout = Output(this, outputStream);
  }

  void setupStderr(OutputStream outputStream) {
    _stderr = Output(this, outputStream);
  }

  void setupOutputReadyType(OutputReadyType outputReadyType) {
    _outputReadyType = outputReadyType;
  }

  /// Waits this container to start and be ready.
  Future<bool> waitReady() async {
    if (isReady) return true;

    switch (outputReadyType) {
      case OutputReadyType.STDOUT:
        return stdout.waitReady();
      case OutputReadyType.STDERR:
        return stderr.waitReady();
      case OutputReadyType.ANY:
        return stdout.waitAnyOutputReady();
      case OutputReadyType.STARTS_READY:
        return true;
      default:
        return stdout.waitReady();
    }
  }

  /// Returns [true] if this container is started and ready.
  bool get isReady {
    switch (outputReadyType) {
      case OutputReadyType.STDOUT:
        return stdout.isReady;
      case OutputReadyType.STDERR:
        return stderr.isReady;
      case OutputReadyType.ANY:
        return stdout.isReady || stderr.isReady;
      case OutputReadyType.STARTS_READY:
        return true;
      default:
        return stdout.isReady;
    }
  }

  /// Returns [true] if this containers is running.
  bool get isRunning;

  /// The exist code, returned by [waitExit], or null if still running.
  int get exitCode;

  /// Returns the time of exit. Computed when [exitCode] is set.
  DateTime get exitTime;

  /// If [exitCode] is defined, returns the elapsed time from [exitTime].
  Duration get exitElapsedTime {
    var exitTime = this.exitTime;
    if (exitTime == null) return null;
    var elapsedTime =
        DateTime.now().millisecondsSinceEpoch - exitTime.millisecondsSinceEpoch;
    return Duration(milliseconds: elapsedTime);
  }

  /// Returns [true] if [exitCode] is defined (process exited).
  bool get isFinished => exitCode != null;

  /// Waits this container to naturally exit.
  Future<int> waitExit({int desiredExitCode, Duration timeout});

  /// Waits this container to naturally exit.
  Future<bool> waitExitAndConfirm(int desiredExitCode) async {
    var exitCode = await waitExit(desiredExitCode: desiredExitCode);
    return exitCode != null;
  }

  /// Calls [waitExit] and returns [stdout]
  Future<Output> waitStdout({int desiredExitCode}) async {
    var exitCode = await waitExit(desiredExitCode: desiredExitCode);
    return exitCode != null ? stdout : null;
  }

  /// Calls [waitExit] and returns [stderr]
  Future<Output> waitStderr({int desiredExitCode}) async {
    var exitCode = await waitExit(desiredExitCode: desiredExitCode);
    return exitCode != null ? stderr : null;
  }

  void dispose() {
    stdout.dispose();
    stderr.dispose();
  }

  @override
  String toString() {
    return 'DockerProcess{instanceID: $instanceID, ready: $isReady, dockerHost: $dockerHost}';
  }
}

/// Output wrapper of a Docker container.
class Output {
  final DockerProcess dockerProcess;
  final OutputStream _outputStream;

  Output(this.dockerProcess, this._outputStream);

  OutputStream getOutputStream() => _outputStream;

  /// Waits with a [timeout] for new data.
  Future<bool> waitData({Duration timeout}) =>
      _outputStream.waitData(timeout: timeout);

  /// Waits for [dataMatcher] with a [timeout].
  Future<bool> waitForDataMatch(Pattern dataMatcher, {Duration timeout}) =>
      _outputStream.waitForDataMatch(dataMatcher, timeout: timeout);

  /// On data event listener.
  EventStream<dynamic> get onData => _outputStream.onData;

  /// Returns all the output as bytes.
  List<int> get asBytes => _outputStream.asBytes;

  /// Returns all the output as [String].
  String get asString => _outputStream.asString;

  /// Sames as [asString], but with optional parameters [entriesRealOffset] and [contentRealOffset].
  String asStringFrom({int entriesRealOffset, int contentRealOffset}) =>
      _outputStream.asStringFrom(
          entriesRealOffset: entriesRealOffset,
          contentRealOffset: contentRealOffset);

  /// Returns all the output as lines (List<String>).
  List<String> get asLines => _outputStream.asLines;

  /// Returns [true] if output is ready, based in
  /// the associated [OutputReadyFunction].
  bool get isReady => _outputStream.isReady;

  /// Waits the output to be ready.
  Future<bool> waitReady() => _outputStream.waitReady();

  /// Waits STDOUT or STDERR to be ready.
  Future<bool> waitAnyOutputReady() => _outputStream.waitAnyOutputReady();

  /// Current length of [_data] buffer.
  int get entriesLength => _outputStream.entriesLength;

  /// Number of removed entries, due [limit].
  int get entriesRemoved => _outputStream.entriesRemoved;

  /// Size of removed content, due [limit].
  int get contentRemoved => _outputStream.contentRemoved;

  /// Returns the size of the buffered content.
  int get bufferedContentSize => _outputStream.bufferedContentSize;

  /// Limit of buffered entries.
  int get limit => _outputStream.limit;

  /// Returns a [List] of entries, from [offset] or [realOffset].
  List getEntries({int offset, int realOffset}) =>
      _outputStream.getEntries(offset: offset, realOffset: realOffset);

  /// Calls [dockerProcess.waitExit].
  Future<int> waitExit() => dockerProcess.waitExit();

  /// Calls [dockerProcess.exitCode].
  int get exitCode => dockerProcess.exitCode;

  void dispose() {
    _outputStream.dispose();
  }

  @override
  String toString() => asString;
}

typedef OutputReadyFunction = bool Function(
    OutputStream outputStream, dynamic data);

/// Indicates which output should be ready.
enum OutputReadyType { STDOUT, STDERR, ANY, STARTS_READY }

/// Handles the output stream of a Docker container.
class OutputStream<T> {
  final Encoding _encoding;
  final bool stringData;

  /// The limit of entries.
  int _limit;

  /// The functions that determines if this output is ready.
  /// Called for each output entry.
  final OutputReadyFunction outputReadyFunction;

  final Completer<bool> anyOutputReadyCompleter;

  OutputStream(this._encoding, this.stringData, this._limit,
      this.outputReadyFunction, this.anyOutputReadyCompleter);

  bool _ready = false;
  final Completer<bool> _readyCompleter = Completer();

  bool get isReady => _ready;

  Future<bool> waitReady() async {
    if (isReady) {
      return true;
    }
    return await _readyCompleter.future;
  }

  Future<bool> waitAnyOutputReady() async {
    if (isReady || anyOutputReadyCompleter.isCompleted) {
      return true;
    }
    return await anyOutputReadyCompleter.future;
  }

  /// Mars this output as ready.
  void markReady() {
    _ready = true;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete(true);
    }

    if (!anyOutputReadyCompleter.isCompleted) {
      anyOutputReadyCompleter.complete(true);
    }
  }

  int get limit => _limit;

  set limit(int value) {
    _limit = value ?? 0;
  }

  /// The data buffer;
  final List<T> _data = <T>[];

  int _dataRemoved = 0;
  int _contentRemoved = 0;

  /// Current length of [_data] buffer.
  int get entriesLength => _data.length;

  /// Number of removed entries, due [_limit].
  int get entriesRemoved => _dataRemoved;

  /// Size of removed content, due [_limit].
  ///
  /// - If is [stringData], [_data] will consider removed length of String entries.
  /// - If is NOT [stringData], [_data] will return the same value as [entriesRemoved].
  int get contentRemoved => _contentRemoved;

  /// Returns the size of the buffered content.
  int get bufferedContentSize => _computeDataContentSize(_data);

  /// Returns a [List] of entries, from [offset] or [realOffset].
  List<T> getEntries({int offset, int realOffset}) {
    if (realOffset != null) {
      offset = realOffset - _dataRemoved;
    }

    offset ??= 0;

    if (offset < 0) {
      offset = 0;
    }

    return offset == 0 ? List.unmodifiable(_data) : _data.sublist(offset);
  }

  /// Adds an [entry] to the [_data] buffer.
  void add(T entry) {
    _data.add(entry);

    if (outputReadyFunction(this, entry)) {
      markReady();
    }

    _checkDataLimit();

    _notifyWaitingData(entry);
  }

  /// Adds all [entries] to the [_data] buffer.
  void addAll(Iterable<T> entries) {
    _data.addAll(entries);

    if (outputReadyFunction(this, entries)) {
      markReady();
    }

    _checkDataLimit();

    _notifyWaitingData(entries);
  }

  void _checkDataLimit() {
    if (_limit > 0) {
      if (stringData) {
        while (_data.length > _limit) {
          var content = _data.removeAt(0);
          ++_dataRemoved;
          _contentRemoved += (content as String).length;
        }
      } else {
        while (_data.length > _limit) {
          _data.removeAt(0);
          ++_dataRemoved;
          ++_contentRemoved;
        }
      }
    }
  }

  int _computeDataContentSize(List<T> data) {
    if (stringData) {
      var total = 0;
      for (var s in data.cast<String>()) {
        total += s.length;
      }
      return total;
    } else {
      return data.length;
    }
  }

  /// On data event listener.
  final EventStream<dynamic> onData = EventStream();

  final List<Completer<bool>> _waitingData = [];

  void _notifyWaitingData(dynamic data) {
    onData.add(data);

    if (_waitingData.isEmpty) return;

    for (var completer in _waitingData) {
      if (!completer.isCompleted) {
        completer.complete(true);
      }
    }

    _waitingData.clear();
  }

  /// Waits with a [timeout] for new data.
  Future<bool> waitData({Duration timeout}) {
    // If disposed, new data won't arrive:
    if (isDisposed) return Future.value(false);

    timeout ??= Duration(seconds: 1);

    var completer = Completer<bool>();

    completer.future.timeout(timeout, onTimeout: () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      return false;
    });

    _waitingData.add(completer);
    return completer.future;
  }

  /// Waits for [dataMatcher] with a [timeout].
  Future<bool> waitForDataMatch(Pattern dataMatcher, {Duration timeout}) async {
    if (asString.contains(dataMatcher)) {
      return true;
    }

    timeout ??= Duration(seconds: 1);
    var waitTimeout = timeout;

    var init = DateTime.now().millisecondsSinceEpoch;

    while (true) {
      var receivedData = await waitData(timeout: waitTimeout);

      if (receivedData) {
        var match = asString.contains(dataMatcher);
        if (match) return true;
      }

      var now = DateTime.now().millisecondsSinceEpoch;
      var elapsedTime = now - init;
      var remainingTime = timeout.inMilliseconds - elapsedTime;

      if (remainingTime < 1) break;

      waitTimeout = Duration(milliseconds: remainingTime);
    }

    return false;
  }

  /// Converts and returns [_data] entries as bytes.
  List<int> get asBytes {
    if (stringData) {
      return utf8.encode(asString);
    } else {
      return List.unmodifiable(_data as List<int>);
    }
  }

  /// Converts and returns [_data] entries as [String].
  String get asString => _dataToString(_data);

  String _dataToString(List<T> data) {
    if (stringData) {
      return data.join();
    } else {
      return _encoding.decode(data as List<int>);
    }
  }

  /// Same as [asString], but resolves [entriesRealOffset] and [contentRealOffset].
  ///
  /// [entriesRealOffset] is an offset of all past entries (will considere [entriesRemoved]).
  /// [contentRealOffset]
  String asStringFrom({int entriesRealOffset, int contentRealOffset}) {
    if ((entriesRealOffset == null || entriesRealOffset < 0) &&
        (contentRealOffset == null || contentRealOffset < 0)) {
      return asString;
    }

    var contentOffset = 0;
    if (contentRealOffset != null && contentRealOffset >= 0) {
      contentOffset = contentRealOffset - _contentRemoved;
    }

    String s;
    if (entriesRealOffset != null && entriesRealOffset >= 0) {
      var entriesOffset = entriesRealOffset - entriesRemoved;

      if (entriesOffset <= 0) {
        s = asString;
        if (contentOffset > 0) {
          s = s.substring(Math.min(contentOffset, s.length));
        }
      } else if (entriesOffset >= _data.length) {
        s = '';
      } else {
        var data1 = _data.sublist(0, entriesOffset);
        var prevContentSize = _computeDataContentSize(data1);
        contentOffset = Math.max(0, contentOffset - prevContentSize);

        var data2 = _data.sublist(entriesOffset);
        s = _dataToString(data2);

        if (contentOffset > 0) {
          s = s.substring(Math.min(contentOffset, s.length));
        }
      }
    } else {
      s = asString;

      if (contentOffset > 0) {
        s = s.substring(Math.min(contentOffset, s.length));
      }
    }

    return s;
  }

  /// Converts and returns [_data] entries as lines [List<String>].
  List<String> get asLines => asString.split(RegExp(r'\r?\n'));

  EventStream<OutputStream<T>> onDispose = EventStream();

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onDispose.add(this);
  }
}
