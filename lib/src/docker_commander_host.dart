import 'dart:async';
import 'dart:convert';

import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_commands.dart';

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
  Future<String> getContainerIDByName(String name);

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
      default:
        return stdout.isReady;
    }
  }

  /// Returns [true] if this containers is running.
  bool get isRunning;

  /// The exist code, returned by [waitExit], or null if still running.
  int get exitCode;

  /// Waits this container to naturally exit.
  Future<int> waitExit({int desiredExitCode});

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

  /// Returns all the output as bytes.
  List<int> get asBytes => _outputStream.asBytes;

  /// Returns all the output as [String].
  String get asString => _outputStream.asString;

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

  /// Number of removed entries, due [_limit].
  int get entriesRemoved => _outputStream.entriesRemoved;

  /// Returns a [List] of entries, from [offset] or [realOffset].
  List getEntries({int offset, int realOffset}) =>
      _outputStream.getEntries(offset: offset, realOffset: realOffset);

  /// Calls [dockerProcess.waitExit].
  Future<int> waitExit() => dockerProcess.waitExit();

  /// Calls [dockerProcess.exitCode].
  int get exitCode => dockerProcess.exitCode;

  @override
  String toString() => asString;
}

typedef OutputReadyFunction = bool Function(
    OutputStream outputStream, dynamic data);

/// Indicates which output should be ready.
enum OutputReadyType { STDOUT, STDERR, ANY }

/// Handles the output stream of a Docker container.
class OutputStream<T> {
  final Encoding _encoding;
  final bool lines;

  /// The limit of entries.
  int _limit;

  /// The functions that determines if this output is ready.
  /// Called for each output entry.
  final OutputReadyFunction outputReadyFunction;

  final Completer<bool> anyOutputReadyCompleter;

  OutputStream(this._encoding, this.lines, this._limit,
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

  /// Current length of [_data] buffer.
  int get entriesLength => _data.length;

  /// Number of removed entries, due [_limit].
  int get entriesRemoved => _dataRemoved;

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

    if (_limit > 0) {
      while (_data.length > _limit) {
        _data.removeAt(0);
        ++_dataRemoved;
      }
    }

    _notifyWaitingData();
  }

  /// Adds all [entries] to the [_data] buffer.
  void addAll(Iterable<T> entries) {
    _data.addAll(entries);

    if (outputReadyFunction(this, entries)) {
      markReady();
    }

    if (_limit > 0) {
      var rm = _data.length - _limit;
      if (rm > 0) {
        _data.removeRange(0, rm);
        _dataRemoved += rm;
      }
    }

    _notifyWaitingData();
  }

  final List<Completer<bool>> _waitingData = [];

  void _notifyWaitingData() {
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
    if (lines) {
      return utf8.encode(asString);
    } else {
      return List.unmodifiable(_data as List<int>);
    }
  }

  /// Converts and returns [_data] entries as [String].
  String get asString {
    if (lines) {
      return _data.join('\n');
    } else {
      return _encoding.decode(_data as List<int>);
    }
  }

  /// Converts and returns [_data] entries as lines [List<String>].
  List<String> get asLines {
    if (lines) {
      return List.unmodifiable(_data as List<String>);
    } else {
      return asString.split(RegExp(r'\r?\n'));
    }
  }
}
