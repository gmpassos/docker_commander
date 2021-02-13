import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_host.dart';

final _LOG = Logger('docker_commander/remote');

class DockerHostRemote extends DockerHost {
  final String serverHost;

  final int serverPort;

  final bool secure;

  final String username;

  final String password;

  final String token;

  HttpClient _httpClient;

  DockerHostRemote(
    this.serverHost,
    this.serverPort, {
    bool secure = false,
    this.username,
    this.password,
    this.token,
  }) : secure = secure ?? false {
    _httpClient = HttpClient(baseURL)
      ..autoChangeAuthorizationToBearerToken('X-Access-Token')
      ..authorization = Authorization.fromProvider(_authenticate);
  }

  String get baseURL {
    var scheme = secure ? 'https' : 'http';
    return '$scheme://$serverHost:$serverPort/';
  }

  Future<Credential> _authenticate(
      HttpClient client, HttpError lastError) async {
    var client = HttpClient(baseURL);

    Credential credential;

    if (isNotEmptyString(token)) {
      credential = BearerCredential(token);
    } else if (isNotEmptyString(username)) {
      credential = BasicCredential(username, password);
    }

    var response = await client.getJSON('/auth', authorization: credential);
    if (response == null) return null;

    return BearerCredential.fromJSONToken(response);
  }

  @override
  Future<bool> initialize() async {
    var ok = await _httpClient.getJSON('initialize') as bool;
    return ok;
  }

  @override
  Future<bool> checkDaemon() async {
    var ok = await _httpClient.getJSON('check_daemon') as bool;
    return ok;
  }

  @override
  Future<void> close() async {
    var ok = await _httpClient.getJSON('close') as bool;
    ok ??= false;

    if (!ok) {
      _LOG.severe("Server operation 'close' returned: $ok");
    }
  }

  @override
  Future<String> getContainerIDByName(String name) async {
    if (isEmptyString(name, trim: true)) return null;
    var id = await _httpClient.getJSON('id_by_name', parameters: {'name': name})
        as String;
    return id;
  }

  @override
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
  }) async {
    cleanContainer ??= true;
    outputAsLines ??= true;

    ports = DockerHost.normalizeMappedPorts(ports);

    var imageArgsEncoded = (imageArgs != null && imageArgs.isNotEmpty)
        ? encodeJSON(imageArgs)
        : null;

    var response = await _httpClient.getJSON('run', parameters: {
      'image': image,
      'version': version,
      'imageArgs': imageArgsEncoded,
      'name': containerName,
      'ports': ports?.join(','),
      'network': network,
      'hostname': hostname,
      'environment': encodeQueryString(environment),
      'cleanContainer': '$cleanContainer',
      'outputAsLines': '$outputAsLines',
      'outputLimit': '$outputLimit',
    }) as Map;

    var instanceID = response['instanceID'] as int;
    containerName = response['name'] as String;
    var id = response['id'] as String;

    outputReadyType ??= DockerHost.resolveOutputReadyType(
        stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var runner = DockerRunnerRemote(
        this,
        instanceID,
        containerName,
        ports,
        outputLimit,
        outputAsLines,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType,
        id);

    _runners[instanceID] = runner;

    await runner.initialize();

    return runner;
  }

  final Map<int, DockerRunnerRemote> _processes = {};

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
    outputAsLines ??= true;

    var argsEncoded =
        (args != null && args.isNotEmpty) ? encodeJSON(args) : null;

    var response = await _httpClient.getJSON('exec', parameters: {
      'cmd': command,
      'args': argsEncoded,
      'name': containerName,
      'outputAsLines': '$outputAsLines',
      'outputLimit': '$outputLimit',
    }) as Map;

    var instanceID = response['instanceID'] as int;
    containerName = response['name'] as String;

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

    await dockerProcess.initialize();

    return dockerProcess;
  }

  Future<OutputSync> runnerGetOutput(
      int instanceID, int realOffset, bool stderr) async {
    var response = await _httpClient.getJSON(stderr ? 'stderr' : 'stdout',
        parameters: {'instanceID': '$instanceID', 'realOffset': '$realOffset'});
    if (response == null) return null;

    var running = parseBool(response['running'], false);

    if (!running) {
      return OutputSync.notRunning();
    }

    var length = parseInt(response['length']);
    var removed = parseInt(response['removed']);
    var entries = response['entries'] as List;

    return OutputSync(length, removed, entries);
  }

  final Map<int, DockerRunnerRemote> _runners = {};

  @override
  List<int> getRunnersInstanceIDs() => _runners.keys.toList();

  @override
  List<String> getRunnersNames() =>
      _runners.values.map((r) => r.containerName).toList();

  @override
  DockerRunnerRemote getRunnerByInstanceID(int instanceID) =>
      _runners[instanceID];

  @override
  DockerRunner getRunnerByName(String name) => _runners.values
      .firstWhere((r) => r.containerName == name, orElse: () => null);

  @override
  Future<bool> stopByName(String name, {Duration timeout}) async {
    var ok = await _httpClient.getJSON('runner_stop', parameters: {
      'name': '$name',
      if (timeout != null) 'timeout': '${timeout.inSeconds}',
    }) as bool;
    return ok;
  }

  Future<bool> runnerWaitReady(int instanceID) async {
    var ok = await _httpClient.getJSON('runner_wait_ready',
        parameters: {'instanceID': '$instanceID'}) as bool;
    return ok;
  }

  Future<int> runnerWaitExit(int instanceID) async {
    var code = await _httpClient.getJSON('runner_wait_exit',
        parameters: {'instanceID': '$instanceID'}) as int;
    return code;
  }

  @override
  String toString() {
    return 'DockerHostRemote{serverHost: $serverHost, serverPort: $serverPort, secure: $secure, username: $username}';
  }
}

class DockerRunnerRemote extends DockerProcessRemote implements DockerRunner {
  @override
  final String id;
  final List<String> _ports;

  DockerRunnerRemote(
      DockerHostRemote dockerHostRemote,
      int instanceID,
      String name,
      this._ports,
      int outputLimit,
      bool outputAsLines,
      OutputReadyFunction stdoutReadyFunction,
      OutputReadyFunction stderrReadyFunction,
      OutputReadyType outputReadyType,
      this.id)
      : super(dockerHostRemote, instanceID, name, outputLimit, outputAsLines,
            stdoutReadyFunction, stderrReadyFunction, outputReadyType);

  @override
  List<String> get ports => List.unmodifiable(_ports ?? []);

  @override
  Future<bool> stop({Duration timeout}) =>
      dockerHost.stopByInstanceID(instanceID, timeout: timeout);
}

class DockerProcessRemote extends DockerProcess {
  final int outputLimit;
  final bool outputAsLines;

  final OutputReadyFunction _stdoutReadyFunction;
  final OutputReadyFunction _stderrReadyFunction;
  final OutputReadyType _outputReadyType;

  DockerProcessRemote(
    DockerHostRemote dockerHostRemote,
    int instanceID,
    String name,
    this.outputLimit,
    this.outputAsLines,
    this._stdoutReadyFunction,
    this._stderrReadyFunction,
    this._outputReadyType,
  ) : super(dockerHostRemote, instanceID, name);

  void initialize() async {
    var anyOutputReadyCompleter = Completer<bool>();

    setupStdout(_buildOutputStream(
        false, _stdoutReadyFunction, anyOutputReadyCompleter));
    setupStderr(_buildOutputStream(
        true, _stderrReadyFunction, anyOutputReadyCompleter));
    setupOutputReadyType(_outputReadyType);
  }

  OutputStream _buildOutputStream(
      bool stderr,
      OutputReadyFunction outputReadyFunction,
      Completer<bool> anyOutputReadyCompleter) {
    if (outputAsLines) {
      var outputStream = OutputStream<String>(
        utf8,
        true,
        outputLimit ?? 1000,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      OutputClient(dockerHost, this, stderr, outputStream, (entries) {
        for (var e in entries) {
          outputStream.add(e);
        }
      }).start();

      return outputStream;
    } else {
      var outputStream = OutputStream<int>(
        utf8,
        false,
        outputLimit ?? 1024 * 128,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      OutputClient(dockerHost, this, stderr, outputStream, (entries) {
        outputStream.addAll(entries.cast());
      }).start();

      return outputStream;
    }
  }

  @override
  DockerHostRemote get dockerHost => super.dockerHost as DockerHostRemote;

  @override
  bool get isRunning => _exitCode == null;

  int _exitCode;

  void _setExitCode(int exitCode) {
    if (_exitCode != null) return;
    _exitCode = exitCode;
    stdout.getOutputStream().markReady();
    stderr.getOutputStream().markReady();
  }

  @override
  int get exitCode => _exitCode;

  @override
  Future<int> waitExit() async {
    if (_exitCode != null) return _exitCode;

    var code = await dockerHost.runnerWaitExit(instanceID);
    _setExitCode(code);

    return _exitCode;
  }
}

class OutputSync {
  final bool running;

  final int length;

  final int removed;

  final List entries;

  OutputSync(this.length, this.removed, this.entries) : running = true;

  OutputSync.notRunning()
      : running = false,
        length = null,
        removed = null,
        entries = null;
}

class OutputClient {
  final DockerHostRemote hostRemote;

  final DockerRunnerRemote runner;

  final bool stderr;

  final OutputStream outputStream;

  final void Function(List entries) entryAdder;

  OutputClient(this.hostRemote, this.runner, this.stderr, this.outputStream,
      this.entryAdder);

  int get realOffset =>
      outputStream.entriesRemoved + outputStream.entriesLength;

  bool _running = true;

  int _errorCount = 0;

  Future<bool> sync() async {
    OutputSync outputSync;
    try {
      outputSync = await hostRemote.runnerGetOutput(
          runner.instanceID, realOffset, stderr);
      _errorCount = 0;
    } catch (e) {
      if (_errorCount++ >= 3 || !runner.isRunning) {
        _running = false;
      }
      if (runner.isRunning) {
        _LOG.warning('Error synching output: $runner', e);
      }
      return false;
    }

    if (outputSync == null) return false;

    if (!outputSync.running) {
      _running = false;
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

    while (_running) {
      var withData = await sync();

      if (!withData) {
        ++noDataCounter;
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
}
