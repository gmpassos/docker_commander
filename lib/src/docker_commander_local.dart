import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_host.dart';

final _LOG = Logger('docker_commander/io');

/// [DockerHost] Implementation for Local Docker machine host.
class DockerHostLocal extends DockerHost {
  String _dockerBinaryPath;

  DockerHostLocal({String dockerBinaryPath})
      : _dockerBinaryPath = isNotEmptyString(dockerBinaryPath, trim: true)
            ? dockerBinaryPath
            : null;

  @override
  Future<bool> initialize() async {
    _dockerBinaryPath ??= await DockerHostLocal.resolveDockerBinaryPath();
    return true;
  }

  /// The Docker binary path.
  String get dockerBinaryPath {
    if (_dockerBinaryPath == null) throw StateError('Null _dockerBinaryPath');
    return _dockerBinaryPath;
  }

  /// Resolves the full path of the Docker binary.
  /// If fails to resolve, returns `docker`.
  static Future<String> resolveDockerBinaryPath() async {
    var processResult = await Process.run('which', <String>['docker'],
        stdoutEncoding: systemEncoding);

    if (processResult.exitCode == 0) {
      var output = processResult.stdout as String;
      output ??= '';
      output = output.trim();

      if (output.isNotEmpty) {
        return output;
      }
    }

    return 'docker';
  }

  @override
  Future<bool> checkDaemon() async {
    var process = Process.run(dockerBinaryPath, <String>['ps']);
    var result = await process;
    return result.exitCode == 0;
  }

  @override
  Future<String> getContainerIDByName(String name) async {
    var cmdArgs = <String>['ps', '-aqf', 'name=$name'];

    _LOG.info(
        'getContainerIDByName[CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process =
        Process.run(dockerBinaryPath, cmdArgs, stdoutEncoding: systemEncoding);

    var result = await process;
    var id = result.stdout.toString().trim();
    return id;
  }

  @override
  Future<DockerRunner> run(
    String imageName, {
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
  }) async {
    outputAsLines ??= true;

    ports = DockerHost.normalizeMappedPorts(ports);

    var image = DockerHost.resolveImage(imageName, version);

    var instanceID = DockerProcess.incrementInstanceID();

    if (isEmptyString(containerName, trim: true)) {
      containerName = 'docker_commander-$session-$instanceID';
    }

    outputReadyType ??=
        _resolveOutputReadyType(stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var cmdArgs = <String>['run', '--name', containerName];

    if (ports != null) {
      for (var pair in ports) {
        cmdArgs.add('-p');
        cmdArgs.add(pair);
      }
    }

    if (isNotEmptyString(network, trim: true)) {
      cmdArgs.add('--net');
      cmdArgs.add(network.trim());
    }

    if (isNotEmptyString(hostname, trim: true)) {
      cmdArgs.add('-h');
      cmdArgs.add(hostname.trim());
    }

    environment?.forEach((k, v) {
      cmdArgs.add('-e');
      cmdArgs.add('$k=$v');
    });

    File idFile;
    if (cleanContainer ?? true) {
      cmdArgs.add('--rm');

      idFile = _createTemporaryFile('cidfile');

      cmdArgs.add('--cidfile');
      cmdArgs.add(idFile.path);
    }

    cmdArgs.add(image);

    if (imageArgs != null) {
      cmdArgs.addAll(imageArgs);
    }

    _LOG.info('run[CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process = await Process.start(dockerBinaryPath, cmdArgs);

    var runner = DockerRunnerLocal(
        this,
        instanceID,
        containerName,
        process,
        idFile,
        ports,
        outputAsLines,
        outputLimit,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType);

    _runners[instanceID] = runner;
    _processes[instanceID] = runner;

    await runner.initialize();

    return runner;
  }

  OutputReadyType _resolveOutputReadyType(
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

  final Map<int, DockerProcess> _processes = {};

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
    var instanceID = DockerProcess.incrementInstanceID();

    outputReadyType ??=
        _resolveOutputReadyType(stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var cmdArgs = ['exec', containerName, command, ...?args];
    _LOG.info('exec[CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process = await Process.start(dockerBinaryPath, cmdArgs);

    var dockerProcess = DockerProcessLocal(
        this,
        instanceID,
        containerName,
        process,
        outputAsLines,
        outputLimit,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType);

    _processes[instanceID] = dockerProcess;

    await dockerProcess.initialize();

    return dockerProcess;
  }

  @override
  Future<bool> stopByName(String name, {Duration timeout}) async {
    if (isEmptyString(name)) return false;

    var time = timeout != null ? timeout.inSeconds : 15;
    if (time < 1) time = 1;

    var process = Process.run(
        dockerBinaryPath, <String>['stop', '--time', '$time', name]);
    var result = await process;
    return result.exitCode == 0;
  }

  final Map<int, DockerRunnerLocal> _runners = {};

  @override
  List<int> getRunnersInstanceIDs() => _runners.keys.toList();

  @override
  List<String> getRunnersNames() =>
      _runners.values.map((r) => r.containerName).toList();

  @override
  DockerRunnerLocal getRunnerByInstanceID(int instanceID) =>
      _runners[instanceID];

  @override
  DockerRunner getRunnerByName(String name) => _runners.values
      .firstWhere((r) => r.containerName == name, orElse: () => null);

  Directory _temporaryDirectory;

  /// Returns the temporary directory for this instance.
  Directory get temporaryDirectory {
    _temporaryDirectory ??= _createTemporaryDirectory();
    return _temporaryDirectory;
  }

  Directory _createTemporaryDirectory() {
    var systemTemp = Directory.systemTemp;
    return systemTemp.createTempSync('docker_commander_temp-$session');
  }

  void _clearTemporaryDirectory() {
    if (_temporaryDirectory == null) return;

    var files =
        _temporaryDirectory.listSync(recursive: true, followLinks: false);

    for (var file in files) {
      try {
        file.deleteSync(recursive: true);
      }
      // ignore: empty_catches
      catch (ignore) {}
    }
  }

  int _tempFileCount = 0;

  File _createTemporaryFile([String prefix]) {
    if (isEmptyString(prefix, trim: true)) {
      prefix = 'temp-';
    }

    var time = DateTime.now().millisecondsSinceEpoch;
    var id = ++_tempFileCount;

    var file = File('${temporaryDirectory.path}/$prefix-$time-$id.tmp');
    return file;
  }

  /// Closes this instances.
  /// Clears the [temporaryDirectory] directory if necessary.
  @override
  Future<void> close() async {
    _clearTemporaryDirectory();
  }

  @override
  String toString() {
    return 'DockerHostLocal{dockerBinaryPath: $_dockerBinaryPath}';
  }
}

class DockerRunnerLocal extends DockerProcessLocal implements DockerRunner {
  /// An optional [File] that contains the container ID.
  final File idFile;
  final List<String> _ports;

  DockerRunnerLocal(
      DockerHostLocal dockerHost,
      int instanceID,
      String containerName,
      Process process,
      this.idFile,
      this._ports,
      bool outputAsLines,
      int outputLimit,
      OutputReadyFunction stdoutReadyFunction,
      OutputReadyFunction stderrReadyFunction,
      OutputReadyType outputReadyType)
      : super(
            dockerHost,
            instanceID,
            containerName,
            process,
            outputAsLines,
            outputLimit,
            stdoutReadyFunction,
            stderrReadyFunction,
            outputReadyType);

  @override
  void initialize() async {
    await super.initialize();

    if (idFile != null) {
      _id = idFile.readAsStringSync().trim();
    } else {
      _id = await dockerHost.getContainerIDByName(containerName);
    }
  }

  String _id;

  @override
  String get id => _id;

  @override
  List<String> get ports => List.unmodifiable(_ports ?? []);

  @override
  Future<bool> stop({Duration timeout}) =>
      dockerHost.stopByInstanceID(instanceID, timeout: timeout);
}

class DockerProcessLocal extends DockerProcess {
  final Process process;

  final bool outputAsLines;
  final int _outputLimit;

  final OutputReadyFunction _stdoutReadyFunction;
  final OutputReadyFunction _stderrReadyFunction;
  final OutputReadyType outputReadyType;

  DockerProcessLocal(
      DockerHostLocal dockerHost,
      int instanceID,
      String containerName,
      this.process,
      this.outputAsLines,
      this._outputLimit,
      this._stdoutReadyFunction,
      this._stderrReadyFunction,
      this.outputReadyType)
      : super(dockerHost, instanceID, containerName);

  final Completer<int> _exitCompleter = Completer();

  void initialize() async {
    // ignore: unawaited_futures
    process.exitCode.then(_setExitCode);

    var anyOutputReadyCompleter = Completer<bool>();

    setupStdout(_buildOutputStream(
        process.stdout, _stdoutReadyFunction, anyOutputReadyCompleter));
    setupStderr(_buildOutputStream(
        process.stderr, _stderrReadyFunction, anyOutputReadyCompleter));

    await waitReady();
  }

  void _setExitCode(int exitCode) {
    _exitCode = exitCode;
    _exitCompleter.complete(exitCode);
    this.stdout.getOutputStream().markReady();
    this.stderr.getOutputStream().markReady();
  }

  OutputStream _buildOutputStream(
      Stream<List<int>> stdout,
      OutputReadyFunction outputReadyFunction,
      Completer<bool> anyOutputReadyCompleter) {
    if (outputAsLines) {
      var outputStream = OutputStream<String>(
        systemEncoding,
        true,
        _outputLimit ?? 1000,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      stdout
          .transform(systemEncoding.decoder)
          .listen((line) => outputStream.add(line));

      return outputStream;
    } else {
      var outputStream = OutputStream<int>(
        systemEncoding,
        false,
        _outputLimit ?? 1024 * 128,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      stdout.listen((b) => outputStream.addAll(b));

      return outputStream;
    }
  }

  @override
  Future<bool> waitReady() async {
    if (isReady) return true;

    switch (outputReadyType) {
      case OutputReadyType.STDOUT:
        return this.stdout.waitReady();
      case OutputReadyType.STDERR:
        return this.stderr.waitReady();
      case OutputReadyType.ANY:
        return this.stdout.waitAnyOutputReady();
      default:
        return this.stdout.waitReady();
    }
  }

  @override
  bool get isReady {
    switch (outputReadyType) {
      case OutputReadyType.STDOUT:
        return this.stdout.isReady;
      case OutputReadyType.STDERR:
        return this.stderr.isReady;
      case OutputReadyType.ANY:
        return this.stdout.isReady || this.stderr.isReady;
      default:
        return this.stdout.isReady;
    }
  }

  @override
  bool get isRunning => _exitCode == null;

  int _exitCode;

  @override
  int get exitCode => _exitCode;

  @override
  Future<int> waitExit() async {
    if (_exitCode != null) return _exitCode;
    var code = await _exitCompleter.future;
    _exitCode = code;
    return _exitCode;
  }
}
