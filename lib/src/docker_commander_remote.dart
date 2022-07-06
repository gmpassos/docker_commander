import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_host.dart';

final _log = Logger('docker_commander/remote');

class DockerHostRemote extends DockerHost {
  final String serverHost;

  final int? serverPort;

  final bool secure;

  final String? username;

  final String? password;

  final String? token;

  late HttpClient _httpClient;

  DockerHostRemote(
    this.serverHost,
    this.serverPort, {
    this.secure = false,
    this.username,
    this.password,
    this.token,
  }) {
    _httpClient = HttpClient(baseURL)
      ..autoChangeAuthorizationToBearerToken('X-Access-Token')
      ..authorization = Authorization.fromProvider(_authenticate);
  }

  /// The default timeout to wait data in STDOUT/STDERR outputs.
  @override
  Duration get defaultOutputTime => Duration(seconds: 10);

  String get baseURL {
    var scheme = secure ? 'https' : 'http';
    return '$scheme://$serverHost:$serverPort/';
  }

  Future<Credential?> _authenticate(
      HttpClient client, HttpError? lastError) async {
    var client = HttpClient(baseURL);

    Credential? credential;

    if (isNotEmptyString(token)) {
      credential = BearerCredential(token!);
    } else if (isNotEmptyString(username)) {
      credential = BasicCredential(username!, password!);
    }

    var response = await client.getJSON('/auth', authorization: credential);
    if (response == null) return null;

    return BearerCredential.fromJSONToken(response);
  }

  DockerCommander? _dockerCommander;

  @override
  DockerCommander get dockerCommander => _dockerCommander!;

  @override
  bool get isInitialized => _dockerCommander != null;

  @override
  Future<bool> initialize(DockerCommander dockerCommander) async {
    if (isInitialized) return true;

    _dockerCommander = dockerCommander;
    var ok = await _httpClient.getJSON('initialize') as bool?;
    return ok ?? false;
  }

  @override
  Future<bool> checkDaemon() async {
    var ok = await _httpClient.getJSON('check_daemon') as bool?;
    return ok ?? false;
  }

  @override
  Future<void> close() async {
    var ok = await _httpClient.getJSON('close') as bool?;
    ok ??= false;

    if (!ok) {
      _log.severe("Server operation 'close' returned: $ok");
    }
  }

  @override
  Future<String?> getContainerIDByName(String? name) async {
    if (isEmptyString(name, trim: true)) return null;
    var id = await _httpClient
        .getJSON('id_by_name', parameters: {'name': name!}) as String?;
    return id;
  }

  @override
  Future<ContainerInfos?> createContainer(
    String containerName,
    String imageName, {
    String? version,
    List<String>? ports,
    String? network,
    String? hostname,
    Map<String, String>? environment,
    Map<String, String>? volumes,
    bool cleanContainer = false,
    String? healthCmd,
    Duration? healthInterval,
    int? healthRetries,
    Duration? healthStartPeriod,
    Duration? healthTimeout,
    String? restart,
  }) async {
    ports = DockerHost.normalizeMappedPorts(ports);

    var response = await _httpClient.getJSON('create', parameters: {
      'image': imageName,
      if (version != null) 'version': version,
      'name': containerName,
      if (ports != null) 'ports': ports.join(','),
      if (network != null) 'network': network,
      if (hostname != null) 'hostname': hostname,
      if (environment != null) 'environment': encodeQueryString(environment),
      if (volumes != null) 'volumes': encodeQueryString(volumes),
      'cleanContainer': '$cleanContainer',
      if (healthCmd != null) 'healthCmd': healthCmd,
      if (healthInterval != null)
        'healthInterval': '${healthInterval.inMilliseconds}',
      if (healthRetries != null) 'healthRetries': '$healthRetries',
      if (healthStartPeriod != null)
        'healthStartPeriod': '${healthStartPeriod.inMilliseconds}',
      if (healthTimeout != null)
        'healthTimeout': '${healthTimeout.inMilliseconds}',
      if (restart != null) 'restart': restart,
    }) as Map?;

    if (response == null) return null;

    containerName = response['containerName'] as String;
    var id = response['id'] as String?;
    var image = response['image'] as String?;
    var portsList = response['ports'] as List?;
    network = response['network'] as String?;
    hostname = response['hostname'] as String?;

    ports = portsList?.cast<String>().toList();

    return ContainerInfos(containerName, id, image, ports, network, hostname);
  }

  @override
  Future<DockerRunner?> run(
    String image, {
    String? version,
    List<String>? imageArgs,
    String? containerName,
    List<String>? ports,
    String? network,
    String? hostname,
    Map<String, String>? environment,
    Map<String, String>? volumes,
    bool cleanContainer = true,
    String? healthCmd,
    Duration? healthInterval,
    int? healthRetries,
    Duration? healthStartPeriod,
    Duration? healthTimeout,
    String? restart,
    bool outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  }) async {
    ports = DockerHost.normalizeMappedPorts(ports);

    var imageArgsEncoded = (imageArgs != null && imageArgs.isNotEmpty)
        ? encodeJSON(imageArgs)
        : null;

    var response = await _httpClient.getJSON('run', parameters: {
      'image': image,
      if (version != null) 'version': version,
      if (imageArgsEncoded != null) 'imageArgs': imageArgsEncoded,
      if (containerName != null) 'name': containerName,
      if (ports != null) 'ports': ports.join(','),
      if (network != null) 'network': network,
      if (hostname != null) 'hostname': hostname,
      if (environment != null) 'environment': encodeQueryString(environment),
      if (volumes != null) 'volumes': encodeQueryString(volumes),
      'cleanContainer': '$cleanContainer',
      if (healthCmd != null) 'healthCmd': healthCmd,
      if (healthInterval != null)
        'healthInterval': '${healthInterval.inMilliseconds}',
      if (healthRetries != null) 'healthRetries': '$healthRetries',
      if (healthStartPeriod != null)
        'healthStartPeriod': '${healthStartPeriod.inMilliseconds}',
      if (healthTimeout != null)
        'healthTimeout': '${healthTimeout.inMilliseconds}',
      if (restart != null) 'restart': restart,
      'outputAsLines': '$outputAsLines',
      'outputLimit': '$outputLimit',
    }) as Map?;

    if (response == null) return null;

    var instanceID = response['instanceID'] as int;
    containerName = response['containerName'] as String?;
    var id = response['id'] as String?;

    outputReadyType ??= DockerHost.resolveOutputReadyType(
        stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var imageResolved = DockerHost.resolveImage(image, version);

    var runner = DockerRunnerRemote(
        this,
        instanceID,
        containerName!,
        imageResolved,
        ports,
        outputLimit,
        outputAsLines,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType,
        id);

    _runners[instanceID] = runner;

    var ok = await _initializeAndWaitReady(runner);

    if (ok) {
      _log.info('Runner[$ok]: $runner');
    }

    return runner;
  }

  Future<bool> _initializeAndWaitReady(DockerProcessRemote dockerProcess,
      [Function()? onInitialize]) async {
    var ok = await dockerProcess.initialize();

    if (!ok) {
      _log.warning('Initialization issue for $dockerProcess');
      return false;
    }

    if (onInitialize != null) {
      var ret = onInitialize();
      if (ret is Future) {
        await ret;
      }
    }

    var ready = await dockerProcess.waitReady();
    if (!ready) {
      _log.warning('Ready issue for $dockerProcess');
      return false;
    }

    return ok;
  }

  @override
  Future<DockerProcess?> exec(
    String containerName,
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  }) async {
    var argsEncoded = args.isNotEmpty ? encodeJSON(args) : null;

    var response = await _httpClient.getJSON('exec', parameters: {
      'cmd': command,
      if (argsEncoded != null) 'args': argsEncoded,
      'name': containerName,
      'outputAsLines': '$outputAsLines',
      'outputLimit': '$outputLimit',
    }) as Map?;

    if (response == null) return null;

    var instanceID = response['instanceID'] as int;
    containerName = response['containerName'] as String;

    outputReadyType ??= DockerHost.resolveOutputReadyType(
        stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var dockerProcess = DockerProcessRemote(
        this,
        instanceID,
        containerName,
        outputLimit,
        outputAsLines,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType);

    _processes[instanceID] = dockerProcess;

    var ok = await _initializeAndWaitReady(dockerProcess);

    if (ok) {
      _log.info('Exec[$ok]: $dockerProcess');
    }

    return dockerProcess;
  }

  @override
  Future<DockerProcess?> command(
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  }) async {
    var argsEncoded = args.isNotEmpty ? encodeJSON(args) : null;

    var response = await _httpClient.getJSON('command', parameters: {
      'cmd': command,
      if (argsEncoded != null) 'args': argsEncoded,
      'outputAsLines': '$outputAsLines',
      'outputLimit': '$outputLimit',
    }) as Map?;

    if (response == null) return null;

    var instanceID = response['instanceID'] as int;

    outputReadyType ??= DockerHost.resolveOutputReadyType(
        stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var dockerProcess = DockerProcessRemote(
        this,
        instanceID,
        '',
        outputLimit,
        outputAsLines,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType);

    _processes[instanceID] = dockerProcess;

    var ok = await _initializeAndWaitReady(dockerProcess);

    if (ok) {
      _log.info('Command[$ok]: $dockerProcess');
    }

    return dockerProcess;
  }

  Future<OutputSync?> processGetOutput(
      int instanceID, int realOffset, bool stderr) async {
    var outputType = stderr ? 'stderr' : 'stdout';
    var parameters = {'instanceID': '$instanceID', 'realOffset': '$realOffset'};

    var responseJSON =
        await _httpClient.getJSON(outputType, parameters: parameters);

    if (responseJSON == null) return null;

    var running = parseBool(responseJSON['running'], false)!;

    if (!running) {
      return OutputSync.notRunning();
    }

    var length = parseInt(responseJSON['length']);
    var removed = parseInt(responseJSON['removed']);
    var entries = responseJSON['entries'] as List?;
    var exitCode = parseInt(responseJSON['exit_code']);

    return OutputSync(length, removed, entries, exitCode);
  }

  static final Duration exitedProcessExpireTime =
      Duration(minutes: 2, seconds: 15);

  final Map<int, DockerProcessRemote> _processes = {};

  void _notifyProcessExited(DockerProcessRemote dockerProcess) {
    _cleanupExitedProcesses();
  }

  void _cleanupExitedProcesses() {
    DockerHost.cleanupExitedProcessesImpl(exitedProcessExpireTime, _processes);
  }

  final Map<int, DockerRunnerRemote> _runners = {};

  @override
  bool isContainerARunner(String containerName) =>
      getRunnerByName(containerName) != null;

  @override
  bool isContainerRunnerRunning(String containerName) =>
      getRunnerByName(containerName)?.isRunning ?? false;

  @override
  List<int> getRunnersInstanceIDs() => _runners.keys.toList();

  @override
  List<String> getRunnersNames() => _runners.values
      .map((r) => r.containerName)
      .where((n) => n.isNotEmpty)
      .toList();

  @override
  DockerRunnerRemote? getRunnerByInstanceID(int instanceID) =>
      _runners[instanceID];

  @override
  DockerRunner? getRunnerByName(String name) =>
      _runners.values.firstWhereOrNull((r) => r.containerName == name);

  @override
  DockerProcess? getProcessByInstanceID(int instanceID) =>
      _processes[instanceID];

  @override
  Future<bool> stopByName(String? name, {Duration? timeout}) async {
    var ok = await _httpClient.getJSON('stop', parameters: {
      'name': name ?? '',
      if (timeout != null) 'timeout': '${timeout.inSeconds}',
    }) as bool?;
    return ok!;
  }

  Future<bool> processWaitReady(int instanceID) async {
    var ok = await _httpClient.getJSON('wait_ready',
        parameters: {'instanceID': '$instanceID'}) as bool?;
    return ok!;
  }

  Future<int?> processWaitExit(int instanceID, [Duration? timeout]) async {
    var code = await _httpClient.getJSON('wait_exit', parameters: {
      'instanceID': '$instanceID',
      if (timeout != null) 'timeout': '${timeout.inMilliseconds}',
    }) as int?;
    return code;
  }

  @override
  Future<List<String>> listFormulasNames() async {
    var list = await _httpClient.getJSON('list-formulas') as List?;
    list ??= [];
    return list.cast<String>().toList();
  }

  @override
  Future<String?> getFormulaClassName(String formulaName) async {
    var className = await _httpClient.getJSON('get-formulas-class-name',
        parameters: {'formula': formulaName}) as String?;
    return className;
  }

  @override
  Future<Map<String, Object>> getFormulaFields(String formulaName) async {
    var map = await _httpClient.getJSON('get-formulas-fields',
        parameters: {'formula': formulaName}) as Map?;
    map ??= {};
    return map.map((key, value) => MapEntry('$key', value));
  }

  @override
  Future<List<String>> listFormulasFunctions(String formulaName) async {
    var list = await _httpClient.getJSON('list-formula-functions',
        parameters: {'formula': formulaName}) as List?;
    list ??= [];
    return list.cast<String>().toList();
  }

  @override
  Future<dynamic> formulaExec(String formulaName, String functionName,
      [List? arguments, Map<String, dynamic>? fields]) async {
    var argsEncoded =
        arguments != null && arguments.isNotEmpty ? encodeJSON(arguments) : '';

    var fieldsEncoded =
        fields != null && fields.isNotEmpty ? encodeJSON(fields) : '';

    var result = await _httpClient.getJSON('formula-exec', parameters: {
      'formula': formulaName,
      'function': functionName,
      'args': argsEncoded,
      'fields': fieldsEncoded,
    });

    return result;
  }

  @override
  String toString() {
    return 'DockerHostRemote{serverHost: $serverHost, serverPort: $serverPort, secure: $secure, username: $username}';
  }

  @override
  Future<String?> createTempFile(String content) async {
    return null;
  }

  @override
  Future<bool> deleteTempFile(String filePath) async {
    return false;
  }
}

class DockerRunnerRemote extends DockerProcessRemote implements DockerRunner {
  @override
  final String? id;

  @override
  final String image;

  final List<String>? _ports;

  DockerRunnerRemote(
      DockerHostRemote dockerHostRemote,
      int instanceID,
      String containerName,
      this.image,
      this._ports,
      int? outputLimit,
      bool outputAsLines,
      OutputReadyFunction stdoutReadyFunction,
      OutputReadyFunction stderrReadyFunction,
      OutputReadyType outputReadyType,
      this.id)
      : super(
            dockerHostRemote,
            instanceID,
            containerName,
            outputLimit,
            outputAsLines,
            stdoutReadyFunction,
            stderrReadyFunction,
            outputReadyType);

  @override
  List<String> get ports => List.unmodifiable(_ports ?? []);

  @override
  Future<bool> stop({Duration? timeout}) =>
      dockerHost.stopByInstanceID(instanceID, timeout: timeout);

  @override
  String toString() {
    return 'DockerRunnerRemote{id: $id, image: $image, containerName: $containerName}';
  }
}

class DockerProcessRemote extends DockerProcess {
  final int? outputLimit;
  final bool outputAsLines;

  final OutputReadyFunction _stdoutReadyFunction;
  final OutputReadyFunction _stderrReadyFunction;
  final OutputReadyType _outputReadyType;

  DockerProcessRemote(
    DockerHostRemote dockerHostRemote,
    int instanceID,
    String containerName,
    this.outputLimit,
    this.outputAsLines,
    this._stdoutReadyFunction,
    this._stderrReadyFunction,
    this._outputReadyType,
  ) : super(dockerHostRemote, instanceID, containerName);

  Future<bool> initialize() async {
    var anyOutputReadyCompleter = Completer<bool>();

    setupStdout(_buildOutputStream(OutputStreamType.stdout, false,
        _stdoutReadyFunction, anyOutputReadyCompleter));
    setupStderr(_buildOutputStream(OutputStreamType.stderr, true,
        _stderrReadyFunction, anyOutputReadyCompleter));
    setupOutputReadyType(_outputReadyType);

    return true;
  }

  OutputStream _buildOutputStream(
      OutputStreamType outputStreamType,
      bool stderr,
      OutputReadyFunction outputReadyFunction,
      Completer<bool> anyOutputReadyCompleter) {
    if (outputAsLines) {
      var outputStream = OutputStream<String>(
        outputStreamType,
        utf8,
        true,
        outputLimit ?? 1000,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      var outputClient =
          OutputClient(dockerHost, this, stderr, outputStream, (entries) {
        for (var e in entries) {
          outputStream.addLines(e);
        }
      });
      outputClient.start();

      outputStream.onDispose.listen((_) => outputClient.stop());

      return outputStream;
    } else {
      var outputStream = OutputStream<int>(
        outputStreamType,
        utf8,
        false,
        outputLimit ?? 1024 * 128,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      var outputClient =
          OutputClient(dockerHost, this, stderr, outputStream, (entries) {
        outputStream.addAll(entries.cast());
      });
      outputClient.start();

      outputStream.onDispose.listen((_) => outputClient.stop());

      return outputStream;
    }
  }

  @override
  DockerHostRemote get dockerHost => super.dockerHost as DockerHostRemote;

  @override
  bool get isRunning => _exitCode == null;

  int? _exitCode;
  DateTime? _exitTime;

  void _setExitCode(int? exitCode) {
    if (_exitCode != null) return;

    _exitCode = exitCode;
    _exitTime = DateTime.now();

    stdout!.getOutputStream().markReady();
    stderr!.getOutputStream().markReady();

    _log.info('EXIT_CODE[instanceID: $instanceID]: $exitCode');
    Future.delayed(Duration(seconds: 60), () => dispose());

    dockerHost._notifyProcessExited(this);
  }

  @override
  int? get exitCode => _exitCode;

  @override
  DateTime? get exitTime => _exitTime;

  @override
  Future<int?> waitExit({int? desiredExitCode, Duration? timeout}) async {
    var exitCode = await _waitExitImpl(timeout);
    if (desiredExitCode != null && exitCode != desiredExitCode) return null;
    return exitCode;
  }

  Future<int?> _waitExitImpl(Duration? timeout) async {
    if (_exitCode != null) return _exitCode;

    var code = await dockerHost.processWaitExit(instanceID, timeout);
    if (code != null) {
      _setExitCode(code);
    }

    return _exitCode;
  }
}

class OutputSync {
  final bool running;

  final int? length;

  final int? removed;

  final List? entries;

  final int? exitCode;

  OutputSync(this.length, this.removed, this.entries, this.exitCode)
      : running = true;

  OutputSync.notRunning()
      : running = false,
        length = null,
        removed = null,
        entries = null,
        exitCode = null;

  @override
  String toString() {
    return 'OutputSync{running: $running, length: $length, removed: $removed, entries: $entries, exitCode: $exitCode}';
  }
}

class OutputClient {
  final DockerHostRemote hostRemote;

  final DockerProcessRemote process;

  final bool stderr;

  final OutputStream outputStream;

  final void Function(List entries) entryAdder;

  OutputClient(this.hostRemote, this.process, this.stderr, this.outputStream,
      this.entryAdder);

  int get realOffset =>
      outputStream.entriesRemoved + outputStream.entriesLength;

  bool _running = true;

  int _errorCount = 0;

  Future<bool> sync() async {
    OutputSync? outputSync;
    try {
      outputSync = await hostRemote.processGetOutput(
          process.instanceID, realOffset, stderr);
      _errorCount = 0;
    } catch (e) {
      if (_errorCount++ >= 3 || !process.isRunning) {
        _running = false;
      }
      if (process.isRunning) {
        _log.warning('Error synching output: $process', e);
      }
      return false;
    }

    if (outputSync == null) return false;

    if (!outputSync.running) {
      _running = false;
    }

    if (outputSync.exitCode != null) {
      process._setExitCode(outputSync.exitCode);
    }

    var entries = outputSync.entries;

    if (entries != null) {
      entryAdder(entries);
      return entries.isNotEmpty;
    } else {
      return false;
    }
  }

  void _syncLoop() async {
    var noDataCounter = 0;
    var exitedCount = 0;

    while (_running) {
      var withData = await sync();

      if (!withData) {
        ++noDataCounter;

        if (process.isFinished && noDataCounter > 3) {
          exitedCount++;
          if (exitedCount > 3) {
            var exitElapsedTime = process.exitElapsedTime!;
            if (exitElapsedTime.inSeconds > 10) {
              stop();
              break;
            }
          }
        }

        var sleep = _resolveNoDataSleep(noDataCounter);

        await Future.delayed(Duration(milliseconds: sleep), () {});
      } else {
        noDataCounter = 0;
      }
    }
  }

  int _resolveNoDataSleep(int noDataCounter) {
    if (noDataCounter <= 1) {
      return 50;
    } else if (noDataCounter <= 100) {
      return (noDataCounter - 1) * 100;
    } else {
      return 10000;
    }
  }

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _syncLoop();
  }

  void stop() {
    _running = false;
  }
}
