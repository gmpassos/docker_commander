import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:docker_commander/docker_commander.dart';
import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_commands.dart';
import 'docker_commander_host.dart';

final _LOG = Logger('docker_commander/io');

class ContainerInfosLocal extends ContainerInfos {
  final File? idFile;

  ContainerInfosLocal(
      String containerName,
      String? image,
      this.idFile,
      List<String>? ports,
      String? containerNetwork,
      String? containerHostname,
      List<String>? args)
      : super(containerName, null, image, ports, containerNetwork,
            containerHostname, args);
}

/// [DockerHost] Implementation for Local Docker machine host.
class DockerHostLocal extends DockerHost {
  String? _dockerBinaryPath;

  DockerHostLocal({String? dockerBinaryPath})
      : _dockerBinaryPath = isNotEmptyString(dockerBinaryPath, trim: true)
            ? dockerBinaryPath
            : null;

  DockerCommander? _dockerCommander;

  @override
  DockerCommander get dockerCommander => _dockerCommander!;

  @override
  bool get isInitialized => _dockerCommander != null;

  @override
  Future<bool> initialize(DockerCommander dockerCommander) async {
    if (isInitialized) return true;

    _dockerCommander = dockerCommander;
    _dockerBinaryPath ??= await DockerHostLocal.resolveDockerBinaryPath();
    return true;
  }

  /// The Docker binary path.
  String? get dockerBinaryPath {
    if (_dockerBinaryPath == null) throw StateError('Null _dockerBinaryPath');
    return _dockerBinaryPath;
  }

  /// Resolves the full path of the Docker binary.
  /// If fails to resolve, returns `docker`.
  static Future<String> resolveDockerBinaryPath() async {
    late final String findCmd;
    if (Platform.isWindows) {
      findCmd = 'where';
    } else {
      findCmd = 'which';
    }

    var processResult = await Process.run(findCmd, <String>['docker'],
        stdoutEncoding: systemEncoding);

    if (processResult.exitCode == 0) {
      var output = processResult.stdout as String?;
      output ??= '';
      output = output.trim();

      if (output.isNotEmpty) {
        if (Platform.isWindows) {
          output = output
              .split('\n')
              .where((element) => element.endsWith('exe'))
              .first
              .replaceAll(RegExp(r'/'), r'\'); // replace file separator
        }
        return output;
      }
    }

    return 'docker';
  }

  @override
  Future<bool> checkDaemon() async {
    _LOG.info('Check Docker Daemon: $dockerBinaryPath info');

    var process = Process.run(dockerBinaryPath!, <String>['info']);
    var result = await process;

    var ok = result.exitCode == 0;

    if (!ok) {
      _LOG.warning('Error checking Docker Daemon:');
      _LOG.warning(result.stdout);
    }

    return ok;
  }

  @override
  ContainerInfosLocal buildContainerArgs(
    String cmd,
    String imageName,
    String? version,
    String containerName,
    List<String>? ports,
    String? network,
    String? hostname,
    Map<String, String>? environment,
    Map<String, String>? volumes,
    bool cleanContainer,
    String? healthCmd,
    Duration? healthInterval,
    int? healthRetries,
    Duration? healthStartPeriod,
    Duration? healthTimeout,
    String? restart, {
    bool addCIDFile = false,
  }) {
    var containerInfos = super.buildContainerArgs(
      cmd,
      imageName,
      version,
      containerName,
      ports,
      network,
      hostname,
      environment,
      volumes,
      cleanContainer,
      healthCmd,
      healthInterval,
      healthRetries,
      healthStartPeriod,
      healthTimeout,
      restart,
    );

    var args = containerInfos.args!;
    // Last parameter is the image.
    // Remove to append more parameters, then add it in the end:
    args.removeLast();

    if (containerInfos.containerNetwork != null) {
      var networkHostsIPs =
          getNetworkRunnersHostnamesAndIPs(containerInfos.containerNetwork);

      for (var networkContainerName in networkHostsIPs.keys) {
        if (networkContainerName == containerName) continue;

        var hostMaps = networkHostsIPs[networkContainerName]!;

        for (var host in hostMaps.keys) {
          var ip = hostMaps[host];
          args.add('--add-host');
          args.add('$host:$ip');
        }
      }
    }

    File? idFile;
    if (addCIDFile) {
      idFile = _createTemporaryFile('cidfile');
      args.add('--cidfile');
      args.add(idFile.path);
    }

    args.add(containerInfos.image!);

    return ContainerInfosLocal(
      containerInfos.containerName,
      containerInfos.image,
      idFile,
      containerInfos.ports,
      containerInfos.containerNetwork,
      containerInfos.containerHostname,
      containerInfos.args,
    );
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
    if (isEmptyString(containerName, trim: true)) {
      return null;
    }

    var containerInfos = buildContainerArgs(
      'create',
      imageName,
      version,
      containerName,
      ports,
      network,
      hostname,
      environment,
      volumes,
      cleanContainer,
      healthCmd,
      healthInterval,
      healthRetries,
      healthStartPeriod,
      healthTimeout,
      restart,
      addCIDFile: true,
    );

    var cmdArgs = containerInfos.args!;

    _LOG.info('create[CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process = await Process.start(dockerBinaryPath!, cmdArgs);
    var exitCode = await process.exitCode;

    if (exitCode != 0) return null;

    containerInfos.id = await _readContainerID(
        containerInfos.containerName, containerInfos.idFile, process);

    return exitCode == 0 ? containerInfos : null;
  }

  Future<String?> _readContainerID(String containerName,
      [File? idFile, Process? process]) async {
    if (idFile != null) {
      var id = await _getContainerID(containerName, idFile);
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }

    if (process != null) {
      var output =
          await process.stdout.transform(systemEncoding.decoder).join();
      var id = output.trim();
      if (id.isNotEmpty) {
        return id;
      }
    } else if (idFile == null) {
      var id = await _getContainerID(containerName);
      return id != null && id.isNotEmpty ? id : null;
    }

    return null;
  }

  Future<String?> _getContainerID(String containerName, [File? idFile]) async {
    if (idFile != null) {
      var fileExists = await _waitFile(idFile);
      if (!fileExists) {
        _LOG.warning("ID file doesn't exists: $idFile");
      }
      try {
        var id = idFile.readAsStringSync().trim();
        if (id.isNotEmpty) {
          return id;
        }
      } catch (e, s) {
        if (fileExists) {
          _LOG.warning("Can't read ID File: $idFile", e, s);
        }
      }
    }

    var id = await getContainerIDByName(containerName);
    return id != null && id.isNotEmpty ? id : null;
  }

  Future<bool> _waitFile(File file, {Duration? timeout}) async {
    if (file.existsSync() && file.lengthSync() > 1) return true;

    timeout ??= Duration(minutes: 1);
    var init = DateTime.now().millisecondsSinceEpoch;

    var retry = 0;
    while (true) {
      var exists = file.existsSync() && file.lengthSync() > 1;
      if (exists) return true;

      var now = DateTime.now().millisecondsSinceEpoch;
      var elapsed = now - init;
      var remainingTime = timeout.inMilliseconds - elapsed;
      if (remainingTime < 0) return false;

      ++retry;
      var sleep = Math.min(1000, 10 * retry);

      await Future.delayed(Duration(milliseconds: sleep));
    }
  }

  @override
  Future<DockerRunner> run(
    String imageName, {
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
    bool? outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  }) async {
    outputAsLines ??= true;

    outputReadyType ??= DockerHost.resolveOutputReadyType(
        stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var instanceID = DockerProcess.incrementInstanceID();

    if (isEmptyString(containerName, trim: true)) {
      containerName = 'docker_commander-$session-$instanceID';
    }

    var containerInfos = buildContainerArgs(
      'run',
      imageName,
      version,
      containerName!,
      ports,
      network,
      hostname,
      environment,
      volumes,
      cleanContainer,
      healthCmd,
      healthInterval,
      healthRetries,
      healthStartPeriod,
      healthTimeout,
      restart,
      addCIDFile: true,
    );

    var cmdArgs = containerInfos.args!;

    if (imageArgs != null) {
      cmdArgs.addAll(imageArgs);
    }

    _LOG.info('run[CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process = await Process.start(dockerBinaryPath!, cmdArgs);

    var containerNetwork = containerInfos.containerNetwork;

    var runner = DockerRunnerLocal(
        this,
        instanceID,
        containerInfos.containerName,
        containerInfos.image,
        process,
        containerInfos.idFile,
        containerInfos.ports,
        containerNetwork,
        containerInfos.containerHostname,
        outputAsLines,
        outputLimit,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType);

    _runners[instanceID] = runner;
    _processes[instanceID] = runner;

    var ok = await _initializeAndWaitReady(runner, () async {
      if (containerNetwork != null) {
        await _configureContainerNetwork(containerNetwork, runner);
      }
    });

    if (ok) {
      _LOG.info('Runner[$ok]: $runner');
    }

    return runner;
  }

  Future<void> _configureContainerNetwork(
      String network, DockerRunnerLocal runner) async {
    if (isEmptyString(network)) return;
    var runnersHostsAndIPs = getNetworkRunnersHostnamesAndIPs(network);

    var oks =
        await DockerCMD.addContainersHostMapping(this, runnersHostsAndIPs);

    var someFail = oks.values.contains('false');

    if (someFail) {
      _LOG.warning(
          'Error configuring containers host mapping> $runnersHostsAndIPs');
    }
  }

  @override
  Future<DockerProcess?> exec(
    String containerName,
    String command,
    List<String> args, {
    bool? outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  }) async {
    if (isContainerARunner(containerName)) {
      if (!isContainerRunnerRunning(containerName)) return null;
    } else {
      var running = await isContainerRunning(containerName);
      if (!running) return null;
    }

    var instanceID = DockerProcess.incrementInstanceID();

    outputReadyType ??= DockerHost.resolveOutputReadyType(
        stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var cmdArgs = ['exec', containerName, command, ...args];
    _LOG.info('docker exec [CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process = await Process.start(dockerBinaryPath!, cmdArgs);

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

    var ok = await _initializeAndWaitReady(dockerProcess);
    if (ok) {
      _LOG.info('Exec[$ok]: $dockerProcess');
    }

    return dockerProcess;
  }

  Future<bool> _initializeAndWaitReady(DockerProcessLocal dockerProcess,
      [Function()? onInitialize]) async {
    var ok = await dockerProcess.initialize();

    if (!ok) {
      _LOG.warning('Initialization issue for $dockerProcess');
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
      _LOG.warning('Ready issue for $dockerProcess');
      return false;
    }

    return ok;
  }

  @override
  Future<DockerProcess> command(
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  }) async {
    var instanceID = DockerProcess.incrementInstanceID();

    outputReadyType ??= DockerHost.resolveOutputReadyType(
        stdoutReadyFunction, stderrReadyFunction);

    stdoutReadyFunction ??= (outputStream, data) => true;
    stderrReadyFunction ??= (outputStream, data) => true;

    var cmdArgs = [command, ...args];
    _LOG.info('docker command [CMD]>\t$dockerBinaryPath ${cmdArgs.join(' ')}');

    var process = await Process.start(dockerBinaryPath!, cmdArgs);

    var dockerProcess = DockerProcessLocal(
        this,
        instanceID,
        '',
        process,
        outputAsLines,
        outputLimit,
        stdoutReadyFunction,
        stderrReadyFunction,
        outputReadyType);

    _processes[instanceID] = dockerProcess;

    var ok = await _initializeAndWaitReady(dockerProcess);
    if (ok) {
      _LOG.info('Command[$ok]: $dockerProcess');
    }

    return dockerProcess;
  }

  @override
  Future<bool> stopByName(String name, {Duration? timeout}) async {
    if (isEmptyString(name)) return false;

    var time = timeout != null ? timeout.inSeconds : 15;
    if (time < 1) time = 1;

    var process = Process.run(
        dockerBinaryPath!, <String>['stop', '--time', '$time', name]);
    var result = await process;
    return result.exitCode == 0;
  }

  static final Duration EXITED_PROCESS_EXPIRE_TIME =
      Duration(minutes: 1, seconds: 15);

  final Map<int, DockerProcessLocal> _processes = {};

  void _notifyProcessExited(DockerProcessLocal dockerProcess) {
    _cleanupExitedProcesses();
  }

  void _cleanupExitedProcesses() {
    DockerHost.cleanupExitedProcessesImpl(
        EXITED_PROCESS_EXPIRE_TIME, _processes);
  }

  final Map<int, DockerRunnerLocal> _runners = {};

  @override
  bool isContainerARunner(String containerName) =>
      getRunnerByName(containerName) != null;

  @override
  bool isContainerRunnerRunning(String containerName) =>
      getRunnerByName(containerName)?.isRunning ?? false;

  List<String> getRunnersIPs() =>
      _runners.values.map((e) => e.ip).whereType<String>().toList();

  List<String> getNetworkRunnersIPs(String network) => _runners.values
      .where((e) => e.network == network)
      .map((e) => e.ip)
      .whereType<String>()
      .toList();

  List<String> getNetworkRunnersHostnames(String network) => _runners.values
      .where((e) => e.network == network)
      .map((e) => e.hostname)
      .whereType<String>()
      .toList();

  List<String> getNetworkRunnersNames(String network) => _runners.values
      .where((e) => e.network == network)
      .map((e) => e.containerName)
      .toList();

  Map<String?, String?> getNetworkRunnersIPsAndHostnames(String network) =>
      Map.fromEntries(_runners.values
          .where((e) => e.network == network)
          .map((e) => MapEntry(e.ip, e.hostname)));

  Map<String, Map<String, String>> getNetworkRunnersHostnamesAndIPs(
          String? network) =>
      Map.fromEntries(_runners.values
          .where(
              (r) => r.network == network && r.hostname != null && r.ip != null)
          .map((r) => MapEntry(r.containerName, {r.hostname!: r.ip!})));

  @override
  List<int> getRunnersInstanceIDs() => _runners.keys.toList();

  @override
  List<String> getRunnersNames() => _runners.values
      .map((r) => r.containerName)
      .where((n) => n.isNotEmpty)
      .toList();

  @override
  DockerRunnerLocal? getRunnerByInstanceID(int? instanceID) =>
      _runners[instanceID!];

  @override
  DockerRunner? getRunnerByName(String name) =>
      _runners.values.firstWhereOrNull((r) => r.containerName == name);

  @override
  DockerProcessLocal? getProcessByInstanceID(int? instanceID) =>
      _processes[instanceID!];

  DockerCommanderFormulaRepository? _formulaRepository;

  DockerCommanderFormulaRepository get formulaRepository {
    _formulaRepository ??= DockerCommanderFormulaRepositoryStandard();
    return _formulaRepository!;
  }

  set formulaRepository(DockerCommanderFormulaRepository value) {
    _formulaRepository = value;
  }

  @override
  Future<List<String>> listFormulasNames() async {
    var list = await formulaRepository.listFormulasNames();
    return list;
  }

  final Map<String, DockerCommanderFormula> _formulasInstances =
      <String, DockerCommanderFormula>{};

  Future<DockerCommanderFormula?> _getFormula(String formulaName) async {
    var formula = _formulasInstances[formulaName];
    if (formula != null) return formula;

    var formulaSource = await formulaRepository.getFormulaSource(formulaName);
    if (formulaSource == null) {
      return null;
    }

    formula = formulaSource.toFormula();
    formula.setup(dockerCommander: dockerCommander);

    _formulasInstances[formulaName] = formula;
    return formula;
  }

  @override
  Future<String?> getFormulaClassName(String formulaName) async {
    var formula = await _getFormula(formulaName);
    if (formula == null) {
      return null;
    }
    return formula.getFormulaClassName();
  }

  @override
  Future<Map<String, Object>> getFormulaFields(String formulaName) async {
    var formula = await _getFormula(formulaName);
    if (formula == null) {
      return <String, Object>{};
    }
    var fields = formula.getFields();
    return fields;
  }

  @override
  Future<List<String>> listFormulasFunctions(String formulaName) async {
    var formula = await _getFormula(formulaName);
    if (formula == null) {
      return <String>[];
    }
    return formula.getFunctions();
  }

  @override
  Future<dynamic> formulaExec(String formulaName, String functionName,
      [List? arguments, Map<String, dynamic>? fields]) async {
    var formula = await _getFormula(formulaName);
    if (formula == null) {
      return false;
    }

    var result = await formula.exec(functionName, arguments, fields);
    return result;
  }

  Directory? _temporaryDirectory;

  /// Returns the temporary directory for this instance.
  Directory? get temporaryDirectory {
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
        _temporaryDirectory!.listSync(recursive: true, followLinks: false);

    for (var file in files) {
      try {
        file.deleteSync(recursive: true);
      }
      // ignore: empty_catches
      catch (ignore) {}
    }
  }

  int _tempFileCount = 0;

  File _createTemporaryFile([String? prefix]) {
    if (isEmptyString(prefix, trim: true)) {
      prefix = 'temp-';
    }

    var time = DateTime.now().millisecondsSinceEpoch;
    var id = ++_tempFileCount;

    var file = File('${temporaryDirectory!.path}/$prefix-$time-$id.tmp');
    return file;
  }

  /// Closes this instances.
  /// Clears the [temporaryDirectory] directory if necessary.
  @override
  Future<void> close() async {
    _clearTemporaryDirectory();
    await _deleteTempFiles();
  }

  @override
  String toString() {
    return 'DockerHostLocal{dockerBinaryPath: $_dockerBinaryPath}';
  }

  final Set<String> _tempFiles = {};

  Future<void> _deleteTempFiles() async {
    var waitAll = Future.wait(
        _tempFiles.map((path) => File(path)).map((f) => f.delete()));
    await waitAll;
  }

  @override
  Future<String> createTempFile(String content) async {
    var file = _createTemporaryFile('temp');

    if (content.isNotEmpty) {
      await file.writeAsString(content, flush: true);
    }

    _tempFiles.add(file.path);
    return file.path;
  }

  @override
  Future<bool> deleteTempFile(String filePath) async {
    if (_tempFiles.contains(filePath)) {
      _tempFiles.remove(filePath);
      await File(filePath).delete();
      return true;
    }
    return false;
  }
}

class DockerRunnerLocal extends DockerProcessLocal implements DockerRunner {
  @override
  final String? image;

  /// An optional [File] that contains the container ID.
  final File? idFile;

  final List<String>? _ports;

  final String? network;
  final String? hostname;

  DockerRunnerLocal(
      DockerHostLocal dockerHost,
      int instanceID,
      String containerName,
      this.image,
      Process process,
      this.idFile,
      this._ports,
      this.network,
      this.hostname,
      bool outputAsLines,
      int? outputLimit,
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

  String? _id;

  @override
  String? get id => _id;

  String? _ip;

  String? get ip => _ip;

  @override
  Future<bool> initialize() async {
    var ok = await super.initialize();

    _id = await dockerHost._getContainerID(containerName, idFile);

    _ip = await DockerCMD.getContainerIP(dockerHost, id);

    return ok;
  }

  @override
  List<String> get ports => List.unmodifiable(_ports ?? []);

  @override
  Future<bool> stop({Duration? timeout}) =>
      dockerHost.stopByInstanceID(instanceID, timeout: timeout);

  @override
  String toString() {
    return 'DockerRunnerLocal{id: $id, image: $image, containerName: $containerName}';
  }
}

class DockerProcessLocal extends DockerProcess {
  final Process process;

  final bool? outputAsLines;
  final int? _outputLimit;

  final OutputReadyFunction _stdoutReadyFunction;
  final OutputReadyFunction _stderrReadyFunction;
  final OutputReadyType _outputReadyType;

  DockerProcessLocal(
      DockerHostLocal dockerHost,
      int instanceID,
      String containerName,
      this.process,
      this.outputAsLines,
      this._outputLimit,
      this._stdoutReadyFunction,
      this._stderrReadyFunction,
      this._outputReadyType)
      : super(dockerHost, instanceID, containerName);

  @override
  DockerHostLocal get dockerHost => super.dockerHost as DockerHostLocal;

  final Completer<int?> _exitCompleter = Completer();

  Future<bool> initialize() async {
    // ignore: unawaited_futures
    process.exitCode.then(_setExitCode);

    var anyOutputReadyCompleter = Completer<bool>();

    setupStdout(_buildOutputStream(
        process.stdout, _stdoutReadyFunction, anyOutputReadyCompleter));
    setupStderr(_buildOutputStream(
        process.stderr, _stderrReadyFunction, anyOutputReadyCompleter));
    setupOutputReadyType(_outputReadyType);

    return true;
  }

  void _setExitCode(int exitCode) {
    if (_exitCode != null) return;
    _LOG.info('EXIT_CODE[instanceID: $instanceID]: $exitCode');

    _exitCode = exitCode;
    _exitTime = DateTime.now();

    _exitCompleter.complete(exitCode);

    this.stdout?.getOutputStream().markReady();
    this.stderr?.getOutputStream().markReady();

    // Schedule dispose:
    Future.delayed(Duration(seconds: 30), () => dispose());

    dockerHost._notifyProcessExited(this);
  }

  OutputStream _buildOutputStream(
      Stream<List<int>> stdout,
      OutputReadyFunction outputReadyFunction,
      Completer<bool> anyOutputReadyCompleter) {
    if (outputAsLines!) {
      var outputStream = OutputStream<String>(
        systemEncoding,
        true,
        _outputLimit ?? 1000,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      var listenSubscription = stdout
          .transform(systemEncoding.decoder)
          .listen((s) => outputStream.add(s));

      outputStream.onDispose.listen((_) {
        try {
          listenSubscription.cancel();
        }
        // ignore: empty_catches
        catch (ignore) {}
      });

      return outputStream;
    } else {
      var outputStream = OutputStream<int>(
        systemEncoding,
        false,
        _outputLimit ?? 1024 * 128,
        outputReadyFunction,
        anyOutputReadyCompleter,
      );

      var listenSubscription = stdout.listen((b) => outputStream.addAll(b));

      outputStream.onDispose.listen((_) {
        try {
          listenSubscription.cancel();
        }
        // ignore: empty_catches
        catch (ignore) {}
      });

      return outputStream;
    }
  }

  @override
  Future<bool> waitReady() async {
    if (isReady) return true;

    switch (outputReadyType) {
      case OutputReadyType.STDOUT:
        return this.stdout!.waitReady();
      case OutputReadyType.STDERR:
        return this.stderr!.waitReady();
      case OutputReadyType.ANY:
        return this.stdout!.waitAnyOutputReady();
      case OutputReadyType.STARTS_READY:
        return true;
      default:
        return this.stdout!.waitReady();
    }
  }

  @override
  bool get isReady {
    switch (outputReadyType) {
      case OutputReadyType.STDOUT:
        return this.stdout!.isReady;
      case OutputReadyType.STDERR:
        return this.stderr!.isReady;
      case OutputReadyType.ANY:
        return this.stdout!.isReady || this.stderr!.isReady;
      case OutputReadyType.STARTS_READY:
        return true;
      default:
        return this.stdout!.isReady;
    }
  }

  @override
  bool get isRunning => _exitCode == null;

  int? _exitCode;
  DateTime? _exitTime;

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

    int? code;
    if (timeout != null) {
      code =
          await _exitCompleter.future.timeout(timeout, onTimeout: () => null);
    } else {
      code = await _exitCompleter.future;
    }

    assert(code == null || code == _exitCode);

    return _exitCode;
  }
}
