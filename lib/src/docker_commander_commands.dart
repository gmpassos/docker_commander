import 'package:collection/collection.dart' show IterableExtension;
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_host.dart';

abstract class DockerCMDExecutor {
  /// The default timeout to wait data in STDOUT/STDERR outputs.
  Duration get defaultOutputTime => Duration(seconds: 2);

  /// Returns [true] [containerName] has a [DockerRunner].
  bool isContainerARunner(String containerName);

  /// Returns [true] if [DockerRunner] of [containerName] is running.
  bool isContainerRunnerRunning(String containerName);

  /// Returns if [containerName] is running (checks at Docker Daemon).
  Future<bool> isContainerRunning(String containerName) async {
    var runningContainers = await DockerCMD.psContainerNames(this);
    if (runningContainers == null) return false;
    return runningContainers.contains(containerName);
  }

  /// Executes a Docker [command] with [args]
  Future<DockerProcess?> command(
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  });

  /// Executes a [command] inside this container with [args]
  /// Only executes if [isContainerRunnerRunning] [containerName] returns true.
  Future<DockerProcess?> exec(
    String containerName,
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int? outputLimit,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
    OutputReadyType? outputReadyType,
  });

  /// Calls [exec] than [waitExit].
  Future<int?> execAndWaitExit(
      String containerName, String command, List<String> args,
      {int? desiredExitCode}) async {
    var process = await exec(containerName, command, args);
    if (process == null) return null;
    return process.waitExit(desiredExitCode: desiredExitCode);
  }

  /// Calls [exec] than [waitExit].
  Future<bool> execAnConfirmExit(String containerName, String command,
      List<String> args, int desiredExitCode) async {
    var exitCode = await execAndWaitExit(containerName, command, args,
        desiredExitCode: desiredExitCode);
    return exitCode != null;
  }

  /// Calls [exec] than [waitStdout].
  Future<Output?> execAndWaitStdout(
      String containerName, String command, List<String> args,
      {int? desiredExitCode}) async {
    var process = await exec(containerName, command, args);
    if (process == null) return null;
    return process.waitStdout(desiredExitCode: desiredExitCode);
  }

  /// Calls [exec] than [waitStderr].
  Future<Output?> execAndWaitStderr(
      String containerName, String command, List<String> args,
      {int? desiredExitCode}) async {
    var process = await exec(containerName, command, args);
    if (process == null) return null;
    return process.waitStderr(desiredExitCode: desiredExitCode);
  }

  /// Calls [execAndWaitStdoutAsString] and returns [Output.asString].
  Future<String?> execAndWaitStdoutAsString(
      String containerName, String command, List<String> args,
      {bool trim = false, int? desiredExitCode, Pattern? dataMatcher}) async {
    var output = await execAndWaitStdout(containerName, command, args,
        desiredExitCode: desiredExitCode);
    return _waitOutputAsString(output, trim, dataMatcher);
  }

  /// Calls [execAndWaitStderrAsString] and returns [Output.asString].
  Future<String?> execAndWaitStderrAsString(
      String containerName, String command, List<String> args,
      {bool trim = false, int? desiredExitCode, Pattern? dataMatcher}) async {
    var output = await execAndWaitStderr(containerName, command, args,
        desiredExitCode: desiredExitCode);
    return _waitOutputAsString(output, trim, dataMatcher);
  }

  Future<String?> _waitOutputAsString(Output? output, bool trim,
      [Pattern? dataMatcher]) async {
    if (output == null) return null;
    dataMatcher ??= RegExp(r'.');
    await output.waitForDataMatch(dataMatcher);
    var s = output.asString;
    if (trim) {
      s = s.trim();
    }
    return s;
  }

  final Map<String, Map<String, String>> _whichCache = {};

  /// Call POSIX `which` command.
  /// Calls [exec] with command `which` and args [commandName].
  /// Caches response than returns the executable path for [commandName].
  Future<String?> execWhich(String containerName, String commandName,
      {bool ignoreCache = false, String? def}) async {
    if (isEmptyString(containerName) || isEmptyString(commandName)) return null;

    if (isEmptyString(commandName, trim: true)) return null;

    commandName = commandName.trim();

    var containerCache =
        _whichCache.putIfAbsent(containerName, () => <String, String>{});
    String? cached;

    if (!ignoreCache) {
      cached = containerCache[commandName];
      if (cached != null) {
        return cached.isNotEmpty ? cached : def;
      }
    }

    var path = await execAndWaitStdoutAsString(
        containerName, 'which', [commandName],
        trim: true, desiredExitCode: 0, dataMatcher: commandName);
    path ??= '';

    containerCache[commandName] = path;

    return path.isNotEmpty ? path : def;
  }

  /// Creates a temporary file.
  Future<String?> createTempFile(String content);

  /// Deletes a temporary [filePath].
  Future<bool> deleteTempFile(String filePath);
}

abstract class DockerCMD {
  /// Returns the container ID by [name].
  static Future<String?> getContainerIDByName(
      DockerCMDExecutor executor, String? name) async {
    if (isEmptyString(name)) return null;

    var process = await executor.command('ps', ['-aqf', 'name=$name']);
    if (process == null) return null;

    var ok = await process.waitExitAndConfirm(0);
    if (!ok) return null;

    var stdout = process.stdout!;
    var dataOK = await stdout.waitForDataMatch(RegExp(r'\w+'),
        timeout: executor.defaultOutputTime);
    if (!dataOK) return null;

    var id = stdout.asString.trim();
    return id;
  }

  /// Returns the container ID by [name].
  static Future<String?> getServiceIDByName(
      DockerCMDExecutor executor, String name) async {
    if (isEmptyString(name)) return null;

    var process = await executor
        .command('service', ['ls', '-f', 'name=$name', '--format', '{{.ID}}']);
    if (process == null) return null;
    var ok = await process.waitExitAndConfirm(0);
    if (!ok) return null;

    var stdout = process.stdout!;
    var dataOK = await stdout.waitForDataMatch(RegExp(r'\w+'),
        timeout: executor.defaultOutputTime);
    if (!dataOK) return null;

    var id = stdout.asString.trim();
    return id;
  }

  /// Returns the container IP by [name].
  static Future<String?> getContainerIP(
      DockerCMDExecutor executor, String? name) async {
    if (isEmptyString(name)) return null;

    var process = await executor.command('container', ['inspect', name!]);
    if (process == null) return null;
    var exitOK = await process.waitExitAndConfirm(0);
    if (!exitOK) return null;

    await process.stdout!.waitForDataMatch('IPAddress');
    var json = process.stdout!.asString;
    if (isEmptyString(json, trim: true)) return null;

    var inspect = parseJSON(json);

    var list = inspect is List ? inspect : [];
    var networkSettings = list
        .whereType<Map>()
        .where((e) => e.containsKey('NetworkSettings'))
        .map((e) => e['NetworkSettings'])
        .whereType<Map>()
        .firstWhereOrNull((e) => e.containsKey('IPAddress'));

    var ip = networkSettings != null ? networkSettings['IPAddress'] : null;

    if (isEmptyString(ip, trim: true)) {
      var networks = networkSettings!['Networks'] as Map;

      var network = networks.values.firstWhere(
          (e) => isNotEmptyString(e['IPAddress']),
          orElse: () => null);
      ip = network != null ? network['IPAddress'] : null;
    }

    return ip;
  }

  static Future<Map<String, bool>> addContainersHostMapping(
      DockerCMDExecutor executor,
      Map<String, Map<String, String?>> containersHostMapping) async {
    var allHostMapping = <String, String?>{};
    for (var hostMapping in containersHostMapping.values) {
      allHostMapping.addAll(hostMapping);
    }

    var oks = <String, bool>{};

    for (var containerName in containersHostMapping.keys) {
      var hostMapping = containersHostMapping[containerName]!;
      var allHostMapping2 = Map<String, String>.from(allHostMapping);

      for (var containerHost in hostMapping.keys) {
        allHostMapping2.remove(containerHost);
      }

      if (allHostMapping2.isEmpty) {
        oks[containerName] = true;
        break;
      }

      var ok = await addContainerHostMapping(
          executor, containerName, allHostMapping2);
      oks[containerName] = ok;
    }

    return oks;
  }

  static Future<bool> addContainerHostMapping(DockerCMDExecutor executor,
      String containerName, Map<String, String> hostIPMapping) async {
    if (isEmptyString(containerName) || hostIPMapping.isEmpty) {
      return false;
    }

    var mappedIPHosts = await getContainerHostsMapped(executor, containerName);

    hostIPMapping.removeWhere((host, ip) => mappedIPHosts.containsKey(ip));
    if (hostIPMapping.isEmpty) return true;

    var hostMap =
        '\n#### docker_commander host mapping:\n${hostIPMapping.entries.map((e) {
      var host = e.key;
      var ip = e.value;
      return '$ip\t$host';
    }).join('\n')}\n####\n';

    return appendFileContent(executor, containerName, '/etc/hosts', hostMap,
        sudo: true);
  }

  /// Returns the current mapped IPs and hosts at `/etc/hosts`.
  static Future<Map<String, List<String>>> getContainerHostsMapped(
      DockerCMDExecutor executor, String containerName) async {
    var hosts = await execCat(executor, containerName, '/etc/hosts');
    var hostsMapped = parseHostsFile(hosts);
    return hostsMapped;
  }

  /// parses a `/etc/hosts` file to IPs and mapped hosts.
  static Map<String, List<String>> parseHostsFile(String? hosts) {
    if (isEmptyString(hosts, trim: true)) return <String, List<String>>{};

    var entries = hosts!
        .split(RegExp(r'[\r\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .map((e) => e.trim().replaceFirst(RegExp(r'#.*'), '').trim())
        .where((e) => e.isNotEmpty)
        .map((e) => e.split(RegExp(r'\s+')))
        .where((e) => e.length > 1)
        .map((e) => MapEntry(e[0], e.sublist(1)));

    var hostsMapped = Map<String, List<String>>.fromEntries(entries);
    return hostsMapped;
  }

  /// Call POSIX `cat` command.
  /// Calls [exec] with command `cat` and args [filePath].
  /// Returns the executable path for [filePath].
  static Future<String?> execCat(
      DockerCMDExecutor executor, String containerName, String filePath,
      {bool trim = false}) async {
    var catBin =
        await executor.execWhich(containerName, 'cat', def: '/bin/cat');
    if (catBin == null) return null;
    var content = await executor.execAndWaitStdoutAsString(
        containerName, catBin, [filePath],
        trim: trim, desiredExitCode: 0);
    return content;
  }

  /// Call POSIX `whoami` command.
  /// Calls [exec] with command `whoami` and returns current user.
  static Future<String?> execWhoami(
      DockerCMDExecutor executor, String containerName) async {
    var whoamiBin = await executor.execWhich(containerName, 'whoami',
        def: '/usr/bin/whoami');
    if (whoamiBin == null) return null;
    var user = await executor.execAndWaitStdoutAsString(
        containerName, whoamiBin, [],
        trim: true, desiredExitCode: 0);
    return user;
  }

  /// Executes a shell [script]. Tries to use `bash` or `sh`.
  /// Note that [script] should be inline, without line breaks (`\n`) or comments (`#`).
  static Future<DockerProcess?> execShell(
      DockerCMDExecutor executor, String containerName, String script,
      {bool sudo = false}) async {
    if (isEmptyString(containerName) || isEmptyString(script, trim: true)) {
      return null;
    }

    var bin = await executor.execWhich(containerName, 'bash');

    if (isEmptyString(bin)) {
      bin = await executor.execWhich(containerName, 'sh', def: '/bin/sh');
    }

    if (bin == null) return null;

    script = inlineShellScript(script);

    if (sudo) {
      var sudoBin =
          await executor.execWhich(containerName, 'sudo', def: '/bin/sudo');
      if (sudoBin == null) return null;
      return executor.exec(containerName, sudoBin, [bin, '-c', script]);
    } else {
      return executor.exec(containerName, bin, ['-c', script]);
    }
  }

  /// Normalizes [script] to a inline script, without line-breaks.
  static String inlineShellScript(String script) {
    script =
        script.replaceAll(RegExp(r'#+[^\r\n]*[\r\n]+', multiLine: false), '\n');

    script = script.replaceAll(
        RegExp(r'[ \t]*[\r\n]+[ \t]*', multiLine: false), '\n');

    script = script.replaceAll(RegExp(r'\n+', multiLine: false), '\n');

    script = script.trim();

    script =
        script.replaceAll(RegExp(r'(?:\s*;\s*)?\n+', multiLine: false), ' ; ');

    return script;
  }

  /// Save the file [containerFilePath] with [content], inside [containerName].
  static Future<bool> putFileContent(DockerCMDExecutor executor,
      String containerName, String containerFilePath, String content,
      {bool sudo = false, bool append = false}) async {
    if (isEmptyString(containerName)) return false;

    var base64Bin = await executor.execWhich(containerName, 'base64',
        def: '/usr/bin/base64');

    var base64 = Base64.encode(content);

    var teeParam = append ? '-a' : '';

    var script =
        'echo "$base64" | $base64Bin --decode | tee $teeParam $containerFilePath > /dev/null ';

    var shell = await execShell(executor, containerName, script);
    if (shell == null) return false;

    var ok = await shell.waitExitAndConfirm(0);
    return ok;
  }

  /// Append to the file [filePath] with [content], inside [containerName].
  static Future<bool> appendFileContent(DockerCMDExecutor executor,
      String containerName, String filePath, String content,
      {bool sudo = false}) async {
    return putFileContent(executor, containerName, filePath, content,
        sudo: sudo, append: true);
  }

  /// Uses Docker `cp` to copy [content] to [containerFilePath] inside [containerName].
  ///
  /// See also [putFileContent], that can perform the operation using
  /// container user and `sudo`.
  static Future<bool> copyFileContentToContainer(
      DockerCMDExecutor executor,
      String containerName,
      String content,
      bool append,
      String containerFilePath) async {
    var tempFilePath = await executor.createTempFile(content);
    if (tempFilePath == null) return false;
    var ok = await copyFileToContainer(
        executor, containerName, tempFilePath, containerFilePath);
    await executor.deleteTempFile(tempFilePath);

    return ok;
  }

  /// Copy a host file, at [hostFilePath], inside a container,
  /// of name [containerName], with internal file path [containerFilePath].
  static Future<bool> copyFileToContainer(
      DockerCMDExecutor executor,
      String containerName,
      String hostFilePath,
      String containerFilePath) async {
    if (isEmptyString(containerName) ||
        isEmptyString(containerFilePath) ||
        isEmptyString(hostFilePath)) {
      return false;
    }

    var cmd = await executor
        .command('cp', [hostFilePath, '$containerName:$containerFilePath']);
    if (cmd == null) return false;
    return cmd.waitExitAndConfirm(0);
  }

  /// Copy a file inside a container, of name [containerName] and path [containerFilePath],
  /// to the host machine, at [hostFilePath].
  static Future<bool> copyFileFromContainer(
      DockerCMDExecutor executor,
      String containerName,
      String containerFilePath,
      String hostFilePath) async {
    if (isEmptyString(containerName) ||
        isEmptyString(containerFilePath) ||
        isEmptyString(hostFilePath)) {
      return false;
    }

    var cmd = await executor
        .command('cp', ['$containerName:$containerFilePath', hostFilePath]);
    if (cmd == null) return false;
    return cmd.waitExitAndConfirm(0);
  }

  /// Executes Docker command `docker ps --format "{{.Names}}"`
  static Future<List<String>?> psContainerNames(DockerCMDExecutor executor,
      {bool all = true}) async {
    var process = await executor.command('ps', [
      if (all) '-a',
      '--format',
      '{{.Names}}',
    ]);
    if (process == null) return null;
    var exitCode = await process.waitExit();
    if (exitCode != 0) return null;
    var stdout = process.stdout!;
    await stdout.waitForDataMatch(RegExp(r'\w'), timeout: Duration(seconds: 1));
    var output = stdout.asString;
    if (output.isEmpty) return <String>[];
    var names =
        output.replaceAll(RegExp(r'\s+'), ' ').trim().split(RegExp(r'\s+'));
    return names;
  }

  /// Creates a Docker network with [networkName].
  static Future<String?> createNetwork(
      DockerCMDExecutor executor, String? networkName) async {
    if (isEmptyString(networkName, trim: true)) return null;
    networkName = networkName!.trim();

    var process = await executor.command('network', ['create', networkName]);
    if (process == null) return null;

    var exitCode = await process.waitExit();
    return exitCode == 0 ? networkName : null;
  }

  /// Removes a Docker network with [networkName].
  static Future<bool> removeNetwork(
      DockerCMDExecutor executor, String? networkName) async {
    if (isEmptyString(networkName, trim: true)) return false;
    networkName = networkName!.trim();
    var process = await executor.command('network', ['rm', networkName]);
    if (process == null) return false;
    var exitCode = await process.waitExit();
    return exitCode == 0;
  }

  /// Removes a container by [containerNameOrID].
  static Future<bool> removeContainer(
      DockerCMDExecutor executor, String containerNameOrID,
      {bool force = false}) async {
    if (isEmptyString(containerNameOrID)) return false;
    var process =
        await executor.command('rm', [if (force) '--force', containerNameOrID]);
    if (process == null) return false;
    return process.waitExitAndConfirm(0);
  }

  /// Starts a container by [containerNameOrID].
  static Future<bool> startContainer(
      DockerCMDExecutor executor, String? containerNameOrID) async {
    if (isEmptyString(containerNameOrID)) return false;
    var process = await executor.command('start', [containerNameOrID!]);
    if (process == null) return false;
    return process.waitExitAndConfirm(0);
  }

  /// Initialize swarm mode.
  static Future<SwarmInfos?> swarmInit(DockerCMDExecutor executor,
      {String? advertiseAddress, String? listenAddress}) async {
    var args = ['init'];

    if (isNotEmptyString(advertiseAddress)) {
      args.add('--advertise-addr');
      args.add(advertiseAddress!);
    }

    if (isNotEmptyString(listenAddress)) {
      args.add('--listen-addr');
      args.add(listenAddress!);
    }

    var cmd = await executor.command('swarm', args);
    if (cmd == null) return null;

    var ok = await cmd.waitExitAndConfirm(0);
    if (!ok) return null;

    var stdout = cmd.stdout!;
    var dataOK = await stdout.waitForDataMatch(RegExp(r'-token'));
    if (!dataOK) return null;

    var output = stdout.asString;

    var swarmInfosWorker = await _parseSwarmInfos(executor, output, true);

    var swarmInfosManager = await _getSwarmJoinToken(executor, false);
    if (swarmInfosManager == null) return null;

    return SwarmInfos(swarmInfosManager.nodeID, swarmInfosManager.managerToken,
        swarmInfosWorker.workerToken, swarmInfosManager.advertiseAddress);
  }

  /// Returns a [SwarmInfos]. Only if in Swarm mode.
  static Future<SwarmInfos?> getSwarmInfos(DockerCMDExecutor executor) async {
    var swarmInfosManager = await _getSwarmJoinToken(executor, false);
    if (swarmInfosManager == null) return null;
    var swarmInfosWorker = await _getSwarmJoinToken(executor, true);
    if (swarmInfosWorker == null) return null;

    return SwarmInfos(swarmInfosManager.nodeID, swarmInfosManager.managerToken,
        swarmInfosWorker.workerToken, swarmInfosManager.advertiseAddress);
  }

  /// Returns the Swarm join token, for manager or [worker].
  static Future<SwarmInfos?> _getSwarmJoinToken(
      DockerCMDExecutor executor, bool worker) async {
    var type = worker ? 'worker' : 'manager';
    var cmd = await executor.command('swarm', ['join-token', type]);
    if (cmd == null) return null;
    var ok = await cmd.waitExitAndConfirm(0);
    if (!ok) return null;

    var stdout = cmd.stdout!;
    var dataOK = await stdout.waitForDataMatch(RegExp(r'-token'));
    if (!dataOK) return null;

    var output = stdout.asString;

    return await _parseSwarmInfos(executor, output, worker);
  }

  static Future<SwarmInfos> _parseSwarmInfos(
      DockerCMDExecutor executor, String output, bool worker) async {
    // Output example:
    // docker swarm join --token SWMTKN-1-1ziutumyd8sw7tkpi698tygcpdezmm7nsr3maehkcijiermv1z-9ng8kp24g7zi168egu2xshfve 192.168.65.3:2377'

    var token = RegExp(r'-token\s+(\S+)\s').allMatches(output).first.group(1);
    var address = RegExp(r'\s([\w.]{4,}:\d+)\s', multiLine: false)
        .allMatches(output)
        .first
        .group(1);

    var nodeID = await swarmSelfNodeID(executor);

    var managerToken = worker ? null : token;
    var workerToken = worker ? token : null;

    return SwarmInfos(nodeID, managerToken, workerToken, address);
  }

  /// Leaves a swarm mode.
  static Future<bool> swarmLeave(DockerCMDExecutor executor,
      {bool force = false}) async {
    var args = ['leave'];

    if (force) {
      args.add('--force');
    }

    var cmd = await executor.command('swarm', args);
    if (cmd == null) return false;
    return cmd.waitExitAndConfirm(0);
  }

  /// Returns the node ID of the current Docker Daemon the swarm cluster.
  static Future<String?> swarmSelfNodeID(DockerCMDExecutor executor) async {
    var cmd =
        await executor.command('node', ['ls', '--format', '{{.ID}}:{{.Self}}']);
    if (cmd == null) return null;
    var ok = await cmd.waitExitAndConfirm(0);
    if (!ok) return null;

    var stdout = cmd.stdout!;
    var dataOK = await stdout.waitForDataMatch(RegExp(r'\w+'),
        timeout: executor.defaultOutputTime);
    if (!dataOK) return null;

    var output = stdout.asString.trim();
    var ids = output.split(RegExp(r'\s+'));

    var myID = ids.firstWhereOrNull((l) => l.contains(':true'));
    if (myID == null) return null;

    myID = myID.split(':true')[0];
    return myID;
  }

  /// Returns a list of services names.
  static Future<List<String>?> listServicesNames(
      DockerCMDExecutor executor) async {
    var cmd =
        await executor.command('service', ['ls', '--format', '{{.Name}}']);
    if (cmd == null) return null;
    var cmdOK = await cmd.waitExitAndConfirm(0);
    if (!cmdOK) return null;

    var stdout = cmd.stdout!;
    var dataOK = await stdout.waitForDataMatch(RegExp(r'\w'),
        timeout: executor.defaultOutputTime);
    if (!dataOK) return null;

    var lines = stdout.asString
        .trim()
        .split(RegExp(r'[\r\n]+'))
        .where((s) => s.isNotEmpty)
        .toList();

    return lines;
  }

  /// Returns a list of [ServiceTaskInfos] of a service by [serviceName].
  static Future<List<ServiceTaskInfos>?> listServiceTasks(
      DockerCMDExecutor executor, String serviceName) async {
    var d = ';!-!;';
    var cmd = await executor.command('service', [
      'ps',
      '--format',
      '{{.ID}}$d{{.Name}}$d{{.Image}}$d{{.Node}}$d{{.DesiredState}}$d{{.CurrentState}}$d{{.Ports}}$d{{.Error}}$d',
      serviceName
    ]);
    if (cmd == null) return null;
    var cmdOK = await cmd.waitExitAndConfirm(0);
    if (!cmdOK) return null;

    var stdout = cmd.stdout!;
    var dataOK =
        await stdout.waitForDataMatch(d, timeout: executor.defaultOutputTime);
    if (!dataOK) return null;

    var lines = stdout.asString.trim().split(RegExp(r'[\r\n]+'));

    var tasks = lines.map((l) {
      var parts = l.split(d);

      var id = parts[0];
      var name = parts[1];
      var image = parts[2];
      var node = parts[3];
      var desiredState = parts[4];
      var currentState = parts[5];
      var ports = parts[6];
      var error = parts[7];

      return ServiceTaskInfos(id, name, serviceName, image, node, desiredState,
          currentState, ports, error);
    }).toList();

    return tasks;
  }

  /// Removes a service from the Swarm cluster by [serviceName].
  static Future<bool> removeService(
      DockerCMDExecutor executor, String serviceName) async {
    var cmd = await executor.command('service', ['rm', serviceName]);
    if (cmd == null) return false;
    var cmdOK = await cmd.waitExitAndConfirm(0);
    return cmdOK;
  }

  /// Opens a Container logs, by [containerNameOrID]:
  static Future<DockerProcess?> openContainerLogs(
          DockerCMDExecutor executor, String containerNameOrID,
          {bool follow = true}) =>
      executor.command(
        'logs',
        [
          containerNameOrID,
          if (follow) '-f',
        ],
        outputReadyType: OutputReadyType.startsReady,
      );

  /// Opens a Service logs, by [serviceNameOrTask]:
  static Future<DockerProcess?> openServiceLogs(
          DockerCMDExecutor executor, String serviceNameOrTask,
          {bool follow = true}) =>
      executor.command(
          'service',
          [
            'logs',
            serviceNameOrTask,
            if (follow) '-f',
          ],
          outputReadyType: OutputReadyType.startsReady);

  /// Returns the Container logs as [String].
  static Future<String?> catContainerLogs(
    DockerCMDExecutor executor,
    String containerNameOrID, {
    bool stderr = false,
    Pattern? waitDataMatcher,
    Duration? waitDataTimeout,
    bool waitExit = false,
    int? desiredExitCode,
    bool follow = false,
  }) async {
    var logs =
        await openContainerLogs(executor, containerNameOrID, follow: follow);
    return await _waitLogs(waitExit, logs, desiredExitCode, stderr,
        waitDataMatcher, waitDataTimeout);
  }

  /// Returns a Service logs as [String].
  static Future<String?> catServiceLogs(
    DockerCMDExecutor executor,
    String containerNameOrID, {
    bool stderr = false,
    Pattern? waitDataMatcher,
    Duration? waitDataTimeout,
    bool waitExit = false,
    int? desiredExitCode,
    bool follow = false,
  }) async {
    var logs =
        await openServiceLogs(executor, containerNameOrID, follow: follow);
    return await _waitLogs(waitExit, logs, desiredExitCode, stderr,
        waitDataMatcher, waitDataTimeout);
  }

  static Future<String?> _waitLogs(
      bool waitExit,
      DockerProcess? logs,
      int? desiredExitCode,
      bool stderr,
      Pattern? waitDataMatcher,
      Duration? waitDataTimeout) async {
    if (waitExit) {
      var waitExit = logs?.waitExit(desiredExitCode: desiredExitCode);
      if (waitExit == null) return null;
    }

    var stdout = (stderr) ? logs!.stderr : logs!.stdout;

    try {
      if (waitDataMatcher != null) {
        waitDataTimeout ??= Duration(seconds: 15);
        var dataOK = await stdout!
            .waitForDataMatch(waitDataMatcher, timeout: waitDataTimeout);
        if (dataOK) {
          return stdout.asString;
        } else {
          return null;
        }
      } else {
        waitDataTimeout ??= Duration(milliseconds: 100);
        var dataOK = await stdout!.waitData(timeout: waitDataTimeout);
        if (dataOK) {
          return stdout.asString;
        } else {
          return null;
        }
      }
    } finally {
      logs.dispose();
    }
  }
}
