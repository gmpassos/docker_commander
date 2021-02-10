import 'dart:io';

import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_host.dart';

final _LOG = Logger('docker_commander/io');

class DockerHostLocal extends DockerHost {
  String _dockerBinaryPath;

  DockerHostLocal({String dockerBinaryPath})
      : _dockerBinaryPath = isNotEmptyString(dockerBinaryPath, trim: true)
            ? dockerBinaryPath
            : null;

  @override
  Future<bool> initialize() async {
    _dockerBinaryPath ??= await resolveDockerBinaryPath();
    return true;
  }

  String get dockerBinaryPath {
    if (_dockerBinaryPath == null) throw StateError('Null _dockerBinaryPath');
    return _dockerBinaryPath;
  }

  Future<String> resolveDockerBinaryPath() async {
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
  Future<DockerRunner> run(String imageName,
      {String version,
      String name,
      bool cleanContainer = true,
      bool outputAsLines = true,
      int outputLimit,
      OutputReadyFunction stdoutReadyFunction,
      OutputReadyFunction stderrReadyFunction}) async {
    outputAsLines ??= true;

    var image = resolveImage(imageName, version);

    var instanceID = DockerRunner.incrementInstanceID();

    if (isEmptyString(name, trim: true)) {
      name = 'docker_commander-$session-$instanceID';
    }

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var cmdArgs = <String>['run', '--name', name];

    File idFile;
    if (cleanContainer ?? true) {
      cmdArgs.add('--rm');

      idFile = _createTemporaryFile('cidfile');

      cmdArgs.add('--cidfile');
      cmdArgs.add(idFile.path);
    }

    cmdArgs.add(image);

    _LOG.info('run[CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process = await Process.start(dockerBinaryPath, cmdArgs);

    var runner = DockerRunnerLocal(this, instanceID, name, process, idFile,
        outputAsLines, outputLimit, stdoutReadyFunction, stderrReadyFunction);

    await runner.initialize();

    return runner;
  }

  Directory _temporaryDirectory;

  Directory get temporaryDirectory {
    _temporaryDirectory ??= _createTemporaryDirectory();
    return _temporaryDirectory;
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

  Directory _createTemporaryDirectory() {
    var systemTemp = Directory.systemTemp;
    return systemTemp.createTempSync('docker_commander_temp-$session');
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

  @override
  Future<void> close() async {
    _clearTemporaryDirectory();
  }

  @override
  String toString() {
    return 'DockerHostLocal{dockerBinaryPath: $_dockerBinaryPath}';
  }
}

class DockerRunnerLocal extends DockerRunner {
  final Process process;
  final File idFile;
  final bool outputAsLines;

  final int _outputLimit;

  final OutputReadyFunction _stdoutReadyFunction;
  final OutputReadyFunction _stderrReadyFunction;

  DockerRunnerLocal(
      DockerHostLocal dockerHost,
      int instanceID,
      String name,
      this.process,
      this.idFile,
      this.outputAsLines,
      this._outputLimit,
      this._stdoutReadyFunction,
      this._stderrReadyFunction)
      : super(dockerHost, instanceID, name);

  void initialize() async {
    setupStdout(_buildOutputStream(process.stdout, _stdoutReadyFunction));
    setupStderr(_buildOutputStream(process.stderr, _stderrReadyFunction));

    await waitReady();

    if (idFile != null) {
      _id = idFile.readAsStringSync().trim();
    } else {
      _id = await dockerHost.getContainerIDByName(name);
    }
  }

  OutputStream _buildOutputStream(
      Stream<List<int>> stdout, OutputReadyFunction outputReadyFunction) {
    if (outputAsLines) {
      var outputStream =
          OutputStream<String>(true, _outputLimit ?? 1000, outputReadyFunction);
      stdout.transform(systemEncoding.decoder).listen((line) {
        if (outputReadyFunction(outputStream, line)) {
          outputStream.markReady();
        }
        outputStream.add(line);
      });
      return outputStream;
    } else {
      var outputStream = OutputStream<int>(
          false, _outputLimit ?? 1024 * 128, outputReadyFunction);
      stdout.listen((b) {
        if (outputReadyFunction(outputStream, b)) {
          outputStream.markReady();
        }
        outputStream.addAll(b);
      });
      return outputStream;
    }
  }

  String _id;

  @override
  String get id => _id;

  @override
  Future<bool> waitReady() async {
    if (isReady) return true;
    return this.stdout.waitReady();
  }

  @override
  bool get isReady => this.stdout.isReady || this.stderr.isReady;

  @override
  Future<int> waitExit() async => process.exitCode;
}
