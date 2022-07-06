import 'dart:async';

import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_host.dart';

typedef ParameterProvider = Future<String> Function(
    String name, String? description);

typedef ConsoleOutput = Future<void> Function(String? line, bool output);

typedef FilterPortsProperties = FutureOr<List<String>?> Function(
    List<String>? ports);
typedef FilterVolumesProperties = FutureOr<Map<String, String>?> Function(
    Map<String, String>? volumesProps);
typedef FilterEnvironmentProperties = FutureOr<Map<String, String>?> Function(
    Map<String, String>? environmentProps);

class DockerCommanderConsole {
  final DockerCommander dockerCommander;
  final ParameterProvider parameterProvider;
  final ConsoleOutput consoleOutput;

  DockerCommanderConsole(
      this.dockerCommander, this.parameterProvider, this.consoleOutput);

  Future<bool> executeCommand(String line) async {
    var cmd = ConsoleCMD.parse(line);
    if (cmd == null) return false;
    return executeConsoleCMD(cmd);
  }

  Future<void> showHelp() async {
    await _printLineToConsole();
    await _printToConsole('HELP:');
    await _printToConsole('');
    await _printToConsole(
        '  - ps                     # List Docker containers.');
    await _printToConsole(
        '  - cmd %command %args*    # Executes a Docker command.');
    await _printToConsole('');
    await _printToConsole('  - create-network %networkName');
    await _printToConsole('');
    await _printToConsole(
        '  - create-container %containerName %imageName %version %ports %volumes %hostname %network %environment --cleanContainer --restart alway --health-cmd "curl..." ');
    await _printToConsole(
        '  - create-service %serviceName %imageName %version %replicas %ports %volumes %hostname %network %environment');
    await _printToConsole('');
    await _printToConsole(
        '  - remove-container %containerName %force # Removes a Docker container.');
    await _printToConsole('');
    await _printToConsole(
        '  - start %containerName   # Starts a Docker container.');
    await _printToConsole(
        '  - stop %containerName    # Stops a Docker container.');
    await _printToConsole('  - exec %containerName %binaryName %args*');
    await _printToConsole('  - exec-which %containerName %binaryName');
    await _printToConsole('');
    await _printToConsole('  - logs %containerOrServiceName');
    await _printToConsole(
        '  - close                  # Closes docker_commander server.');
    await _printToConsole('  - exit                   # Exits console.');
    await _printToConsole('');
    await _printToConsole(
        '  - list-formulas                         # List available formulas.');
    await _printToConsole(
        '  - get-formula-class-name %formulaName   # Show the formula class name.');
    await _printToConsole(
        '  - get-formulas-fields %formulaName      # Show the formula fields.');
    await _printToConsole(
        '  - list-formula-functions %formulaName   # List formula functions.');
    await _printToConsole(
        '  - show-formula %formulaName             # Show formula information.');
    await _printToConsole(
        '  - formula-exec %formulaName %function %args*  # Execute a formula function.');

    await _printToConsole('');
    await _printLineToConsole();
  }

  Future<bool> executeConsoleCMD(ConsoleCMD cmd) async {
    switch (cmd.cmd) {
      case 'help':
        {
          await showHelp();
          return true;
        }
      case 'initialize':
        {
          return dockerCommander.initialize();
        }
      case 'checkdaemon':
        {
          await dockerCommander.checkDaemon();
          return true;
        }
      case 'close':
        {
          await dockerCommander.close();
          return true;
        }
      case 'ps':
        {
          var exec = await dockerCommander.command('ps', ['-a']);
          return await _processReturn(cmd, exec);
        }
      case 'createnetwork':
        {
          var parameters = await _requireParameters({
            'networkName': cmd.get(0, 'networkName', 'network', 'name'),
          }, {
            'networkName',
          }, cmd.askAllProperties);

          var networkName = await dockerCommander.createNetwork(
            parameters['networkName']!,
          );

          if (networkName != null) {
            await _printToConsole('CREATED NETWORK> $networkName');
            return true;
          }

          return false;
        }
      case 'createcontainer':
        {
          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerName', 'container'),
            'imageName': cmd.get(1, 'imageName', 'image'),
            'version': cmd.get(2, 'version', 'ver'),
            'ports': cmd.get(3, 'ports', 'port'),
            'volumes': cmd.get(4, 'volumes'),
            'hostname': cmd.get(5, 'hostname', 'host'),
            'network': cmd.get(6, 'network'),
            'environment': cmd.get(7, 'environment', 'env'),
            'cleanContainer': cmd.getProperty('cleanContainer'),
            'health-cmd': cmd.getProperty('health-cmd'),
            'health-interval': cmd.getProperty('health-interval'),
            'health-retries': cmd.getProperty('health-retries'),
            'health-start-period': cmd.getProperty('health-start-period'),
            'health-timeout': cmd.getProperty('health-timeout'),
            'restart': cmd.getProperty('restart'),
          }, {
            'containerName',
            'imageName',
          }, cmd.askAllProperties);

          var paramPorts = await _parsePortsProperties(parameters);
          var paramVolumes = await _parseVolumesProperties(parameters);
          var paramEnvironment = await _parseEnvironmentProperties(parameters);

          var containerInfos = await dockerCommander.createContainer(
            parameters['containerName']!,
            parameters['imageName']!,
            version: parameters['version'],
            ports: paramPorts,
            volumes: paramVolumes,
            hostname: parameters['hostname'],
            network: parameters['network'],
            environment: paramEnvironment,
            cleanContainer: parseBool(parameters['cleanContainer']) ?? false,
            healthCmd: parameters['health-cmd'],
            healthInterval: _parseDurationInMs(parameters['health-interval']),
            healthRetries: parseInt(parameters['health-retries']),
            healthStartPeriod:
                _parseDurationInMs(parameters['health-start-period']),
            healthTimeout: _parseDurationInMs(parameters['health-timeout']),
            restart: parameters['restart'],
          );

          if (containerInfos != null) {
            await _printToConsole('CREATED CONTAINER> $containerInfos');
            return true;
          }

          return false;
        }
      case 'createservice':
        {
          var parameters = await _requireParameters({
            'serviceName': cmd.get(0, 'serviceName', 'service'),
            'imageName': cmd.get(1, 'imageName', 'image'),
            'version': cmd.get(2, 'version', 'ver'),
            'replicas': cmd.get(3, 'replicas'),
            'ports': cmd.get(4, 'ports', 'port'),
            'volumes': cmd.get(5, 'volumes'),
            'hostname': cmd.get(6, 'hostname', 'host'),
            'network': cmd.get(7, 'network'),
            'environment': cmd.get(8, 'environment', 'env'),
          }, {
            'containerName',
            'imageName',
          }, cmd.askAllProperties);

          var paramPorts = await _parsePortsProperties(parameters);
          var paramVolumes = await _parseVolumesProperties(parameters);
          var paramEnvironment = await _parseEnvironmentProperties(parameters);

          var service = await dockerCommander.createService(
            parameters['serviceName']!,
            parameters['imageName']!,
            version: parameters['version'],
            replicas: parseInt(parameters['replicas']),
            ports: paramPorts,
            volumes: paramVolumes,
            hostname: parameters['hostname'],
            network: parameters['network'],
            environment: paramEnvironment,
          );

          if (service != null) {
            await _printToConsole('CREATED SERVICE> $service');
            return true;
          }

          return false;
        }
      case 'removecontainer':
        {
          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerOrServiceName',
                'containerName', 'container', 'serviceName', 'service'),
            'force': cmd.getProperty('force'),
          }, {
            'containerName',
          }, cmd.askAllProperties);

          var ok = await dockerCommander.removeContainer(
              parameters['containerName']!,
              force: parseBool(parameters['force']) ?? false);

          await _printToConsole('STARTED CONTAINER: $ok');

          return ok;
        }
      case 'start':
        {
          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerOrServiceName',
                'containerName', 'container', 'serviceName', 'service'),
          }, {
            'containerName',
          }, cmd.askAllProperties);

          var ok = await dockerCommander
              .startContainer(parameters['containerName']!);

          await _printToConsole('STARTED CONTAINER: $ok');

          return ok;
        }
      case 'stop':
        {
          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerOrServiceName',
                'containerName', 'container', 'serviceName', 'service'),
          }, {
            'containerName',
          }, cmd.askAllProperties);

          var ok =
              await dockerCommander.stopContainer(parameters['containerName']!);

          await _printToConsole('STOPPED CONTAINER: $ok');

          return ok;
        }
      case 'log':
      case 'logs':
        {
          cmd.defaultReturnType = ConsoleCMDReturnType.stdout;

          var parameters = await _requireParameters({
            'name': cmd.get(0, 'containerOrServiceName', 'containerName',
                'container', 'serviceName', 'service'),
            'stdout': cmd.getProperty('stdout'),
            'stderr': cmd.getProperty('stderr'),
          }, {
            'name',
          }, cmd.askAllProperties);

          if (parseBool(parameters['stdout'], false)!) {
            cmd.returnType = ConsoleCMDReturnType.stdout;
          } else if (parseBool(parameters['stderr'], false)!) {
            cmd.returnType = ConsoleCMDReturnType.stderr;
          }

          var name = parameters['name'];

          var containersNames = await dockerCommander.psContainerNames();

          await _printToConsole('CONTAINERS: $containersNames');

          DockerProcess? process;
          if (containersNames != null && containersNames.contains(name)) {
            process = await dockerCommander.openContainerLogs(name!);
          } else {
            var servicesNames = await dockerCommander.listServicesNames();
            await _printToConsole('SERVICES: $servicesNames');

            if (servicesNames != null && servicesNames.contains(name)) {
              process = await dockerCommander.openServiceLogs(name!);
            } else {
              return false;
            }
          }

          return await _processReturn(cmd, process);
        }
      case 'execwhich':
        {
          cmd.returnType = ConsoleCMDReturnType.stdout;

          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerName', 'container'),
            'binary': cmd.get(1, 'binaryName', 'binary'),
          }, {
            'containerName',
            'binary',
          }, cmd.askAllProperties);

          var exec = await dockerCommander.execWhich(
              parameters['containerName']!, parameters['binary']!);

          await _printToConsole(exec);

          return true;
        }
      case 'exec':
        {
          cmd.defaultReturnType = ConsoleCMDReturnType.stdout;

          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerName', 'container'),
            'command': cmd.get(1, 'command', 'cmd'),
          }, {
            'containerName',
            'command'
          }, cmd.askAllProperties);

          var exec = await dockerCommander.exec(parameters['containerName']!,
              parameters['command'], cmd.argsSub(2));
          return await _processReturn(cmd, exec);
        }
      case 'docker':
      case 'cmd':
      case 'command':
        {
          cmd.defaultReturnType = ConsoleCMDReturnType.stdout;

          var parameters = await _requireParameters({
            'command': cmd.get(0, 'command', 'cmd'),
          }, {
            'command'
          }, cmd.askAllProperties);

          var exec = await dockerCommander.command(
              parameters['command']!, cmd.argsSub(1));

          return await _processReturn(cmd, exec);
        }
      case 'listformula':
      case 'listformulas':
        {
          var formulasNames = await dockerCommander.listFormulasNames();

          await _printLineToConsole();
          await _printToConsole('FORMULAS:');
          await _printToConsole('');
          await _printToConsole('  ${formulasNames.join(' ')}');
          await _printToConsole('');
          await _printLineToConsole();

          return true;
        }
      case 'getformulaclassname':
        {
          var parameters = await _requireParameters({
            'formulaName': cmd.get(0, 'formulaName', 'formula'),
          }, {
            'formulaName',
          }, cmd.askAllProperties);

          var formulaName = parameters['formulaName']!;

          var className =
              await dockerCommander.getFormulaClassName(formulaName);

          await _printToConsole("'$formulaName' CLASS NAME: $className");

          return true;
        }
      case 'listformulafunction':
      case 'listformulafunctions':
        {
          var parameters = await _requireParameters({
            'formulaName': cmd.get(0, 'formulaName', 'formula'),
          }, {
            'formulaName',
          }, cmd.askAllProperties);

          var formulaName = parameters['formulaName']!;

          var functions =
              await dockerCommander.listFormulasFunctions(formulaName);

          await _printLineToConsole();
          await _printToConsole("'$formulaName' FUNCTIONS:");
          await _printToConsole('');

          for (var f in functions) {
            await _printToConsole('  - $f');
          }

          await _printToConsole('');
          await _printLineToConsole();

          return true;
        }
      case 'showformula':
        {
          var parameters = await _requireParameters({
            'formulaName': cmd.get(0, 'formulaName', 'formula'),
          }, {
            'formulaName',
          }, cmd.askAllProperties);

          var formulaName = parameters['formulaName']!;

          var fieldsFuture = dockerCommander.getFormulaFields(formulaName);

          var functionsFuture =
              dockerCommander.listFormulasFunctions(formulaName);

          var classNameFuture =
              dockerCommander.getFormulaClassName(formulaName);

          var className = await classNameFuture;
          var fields = await fieldsFuture;
          var functions = await functionsFuture;

          await _printLineToConsole();
          await _printToConsole('FORMULA: $formulaName');
          await _printToConsole('');
          await _printToConsole('CLASS NAME: $className');
          await _printToConsole('');
          await _printToConsole('FIELDS:');
          await _printToConsole('');

          for (var entry in fields.entries) {
            await _printToConsole('  - ${entry.key}: ${entry.value}');
          }

          await _printToConsole('');
          await _printToConsole('FUNCTIONS:');
          await _printToConsole('');

          for (var f in functions) {
            await _printToConsole('  - $f');
          }

          await _printToConsole('');
          await _printLineToConsole();

          return true;
        }
      case 'formulaexec':
        {
          var parameters = await _requireParameters({
            'formulaName': cmd.get(0, 'formulaName', 'formula'),
            'function': cmd.get(1, 'function'),
          }, {
            'formulaName',
            'function',
          }, cmd.askAllProperties);

          var formulaName = parameters['formulaName']!;
          var fName = parameters['function']!;
          var arguments = cmd.argsSub(2);

          var properties = cmd.properties;

          var result = await dockerCommander.formulaExec(
              formulaName, fName, arguments, properties);

          await _printLineToConsole();
          await _printToConsole(
              'FORMULA EXEC: $formulaName.$fName( ${arguments.join(' , ')} )');
          await _printToConsole('');
          await _printToConsole('RESULT:');
          await _printToConsole('$result');
          await _printToConsole('');
          await _printLineToConsole();

          return true;
        }
      default:
        return false;
    }
  }

  Duration? _parseDurationInMs(String? duration) {
    if (duration == null) return null;
    duration = duration.trim();
    if (duration.isEmpty) return null;
    var ms = parseInt(duration)!;
    return Duration(milliseconds: ms);
  }

  final List<FilterPortsProperties> filterPorts = <FilterPortsProperties>[];

  Future<List<String>?> _parsePortsProperties(
      Map<String, String> parameters) async {
    var ports =
        parseStringFromInlineList(parameters['ports'], RegExp(r'\s*[,;|]\s*'));

    for (var filter in filterPorts) {
      ports = await filter(ports);
    }

    return ports;
  }

  final List<FilterVolumesProperties> filterVolumesProperties =
      <FilterVolumesProperties>[];

  Future<Map<String, String>?> _parseVolumesProperties(
      Map<String, String> parameters) async {
    var volumesProps = parseFromInlineMap<String, String>(
        parameters['volumes'], RegExp(r'[;|]'), RegExp(r'[:=]'));

    for (var filter in filterVolumesProperties) {
      volumesProps = await filter(volumesProps);
    }

    return volumesProps;
  }

  final List<FilterEnvironmentProperties> filterEnvironmentProperties =
      <FilterVolumesProperties>[];

  Future<Map<String, String>?> _parseEnvironmentProperties(
      Map<String, String> parameters) async {
    var environmentProps = parseFromInlineMap<String, String>(
        parameters['environment'], RegExp(r'[|]'), RegExp(r'[:=]'));

    for (var filter in filterEnvironmentProperties) {
      environmentProps = await filter(environmentProps);
    }

    return environmentProps;
  }

  Future<bool> _processReturn(ConsoleCMD cmd, DockerProcess? process,
      [bool allowPrintAsOutput = true]) async {
    if (process == null) {
      return false;
    }

    switch (cmd.returnType) {
      case ConsoleCMDReturnType.stderr:
      case ConsoleCMDReturnType.stdout:
        {
          var outputName = cmd.returnType == ConsoleCMDReturnType.stderr
              ? 'STDERR'
              : 'STDOUT';

          var output = cmd.returnType == ConsoleCMDReturnType.stderr
              ? process.stderr!
              : process.stdout!;

          await _printLineToConsole();

          var printData0 = output.asString;
          var printData0EntriesRemoved = output.entriesRemoved;
          var printData0ContentRemoved = output.contentRemoved;
          _printData(printData0, allowPrintAsOutput, 'printData0');

          var anyDataReceived = Completer<int>();

          var waitingData = <String>[];

          var listener = output.onData.listen((d) {
            if (anyDataReceived.isCompleted) {
              if (waitingData.isNotEmpty) {
                for (var d in waitingData) {
                  _printData(d, allowPrintAsOutput, 'printData2');
                }
                waitingData.clear();
              }
              _printData(d, allowPrintAsOutput, 'listener');
            } else {
              waitingData.add('$d');
              anyDataReceived.complete(-1);
            }
          });

          var finished = process.isFinished;
          if (!finished) {
            await Future.any([
              process.waitExit(timeout: Duration(seconds: 1)),
              anyDataReceived.future,
            ]);

            if (!anyDataReceived.isCompleted) {
              anyDataReceived.complete(-2);
            }
          }

          if (process.isFinished) {
            await _cancelStreamSubscription(listener);

            await process.stdout!
                .waitData(timeout: Duration(milliseconds: 300));

            var printData1 = output.asStringFrom(
                entriesRealOffset: printData0EntriesRemoved,
                contentRealOffset:
                    printData0ContentRemoved + printData0.length);

            if (printData1.isNotEmpty) {
              _printData(printData1, allowPrintAsOutput, 'printData1');
            }
          } else {
            if (!anyDataReceived.isCompleted) {
              anyDataReceived.complete(-3);
            }

            for (var d in waitingData) {
              _printData(d, allowPrintAsOutput, 'printData2');
            }
            waitingData.clear();

            while (true) {
              await _askParameter('', '[STOP $outputName CONSUMER]');
              await _cancelStreamSubscription(listener);
              break;
            }
          }

          process.dispose();

          await _printLineToConsole();

          var exitCode = process.exitCode;
          if (exitCode != null) {
            await _printToConsole('EXIT_CODE: $exitCode');
          }

          return true;
        }
      case ConsoleCMDReturnType.exitCode:
        {
          var exitCode = await process.waitExit();
          await _printToConsole('EXIT CODE: $exitCode');
          return true;
        }
      default:
        return false;
    }
  }

  static final RegExp _regexpLineBreak = RegExp(r'\r?\n', multiLine: false);
  static final RegExp _regexpLineBreakEnding =
      RegExp(r'\r?\n$', multiLine: false);

  Future<void> _cancelStreamSubscription(StreamSubscription listener) async {
    try {
      return await listener.cancel();
    }
    // ignore: empty_catches
    catch (ignore) {}
  }

  int _printID = 0;

  void _printData(data, bool allowPrintAsOutput, [String? from]) {
    Iterable<String>? lines;

    if (data is List<String>) {
      var s = data.join();
      if (data.isNotEmpty) {
        lines =
            s.replaceFirst(_regexpLineBreakEnding, '').split(_regexpLineBreak);
      }
    } else if (data is String) {
      if (data.isNotEmpty) {
        lines = data
            .replaceFirst(_regexpLineBreakEnding, '')
            .split(_regexpLineBreak);
      }
    } else if (data is List<int>) {
      var s = String.fromCharCodes(data);
      if (s.isNotEmpty) {
        lines =
            s.replaceFirst(_regexpLineBreakEnding, '').split(_regexpLineBreak);
      }
    } else if (data is int) {
      var s = String.fromCharCodes([data]);
      if (s.isNotEmpty) {
        lines =
            s.replaceFirst(_regexpLineBreakEnding, '').split(_regexpLineBreak);
      }
    }

    from ??= '';
    ++_printID;

    if (lines != null) {
      for (var line in lines) {
        var output = allowPrintAsOutput ? true : false;
        _printToConsole(line, output, _printID, from);
      }
    }
  }

  Future<Map<String, String>> _requireParameters(Map<String, String?> fields,
      Set<String> required, bool? askAllProperties) async {
    var parameters = <String, String>{};
    for (var name in fields.keys.toList()) {
      var value = fields[name];

      if (isNotEmptyString(value, trim: true)) {
        parameters[name] = value!.trim();
      } else if (required.contains(name) || askAllProperties!) {
        var value = await _askParameter(name);
        if (isNotEmptyString(value, trim: true)) {
          parameters[name] = value.trim();
        }
      }
    }
    return parameters;
  }

  Future<String> _askParameter(String name, [String? description]) async {
    var value = await parameterProvider(name, description);
    return value;
  }

  Future<void> _printToConsole(String? line,
          [bool? output, int? printID, String? from]) =>
      consoleOutput(line, output ?? false);

  Future<void> _printLineToConsole() => _printToConsole(
      '------------------------------------------------------------------------------');

  @override
  String toString() {
    return 'DockerCommanderConsole{dockerCommander: $dockerCommander}';
  }
}

class ConsoleCMD {
  final String cmd;

  late List<String> _args;
  late Map<String, String?> _properties;

  ConsoleCMD(String cmd, List<String?> args)
      : cmd = cmd.trim().toLowerCase().replaceAll(RegExp(r'[\s._\-]+'), '') {
    _args = <String>[];
    _properties = <String, String?>{};

    for (var i = 0; i < args.length; ++i) {
      var arg = args[i]!;
      if (arg.startsWith('----')) {
        var nextI = i + 1;
        var name = arg.substring(4);

        String? value;
        if (nextI < args.length) {
          value = args[nextI];
          if (value!.startsWith('----')) {
            value = 'true';
          } else {
            args.removeAt(nextI);
          }
        } else {
          value = 'true';
        }

        _properties[name.toLowerCase().trim()] = value;
      } else {
        _args.add(arg);
      }
    }

    _normalizeCmdProperties();
  }

  static ConsoleCMD? parse(String? line) {
    if (line == null) return null;
    line = line.trim();
    if (line.isEmpty) return null;
    var parts = line.split(RegExp(r'\s+'));

    var cmd = parts[0];
    var args = parts.length > 1 ? parts.sublist(1) : [];

    return ConsoleCMD(cmd, args.map(parseString).toList());
  }

  bool _normalizeCmdProperties() {
    switch (cmd) {
      case 'createcontainer':
        {
          parseSimpleProperties({
            'containerName',
            'container',
            'imageName',
            'image',
            'version',
            'ver',
            'ports',
            'port',
            'volumes',
            'hostname',
            'host',
            'network',
            'environment',
            'env',
            'cleanContainer',
            'health-cmd',
            'health-interval',
            'health-retries',
            'health-start-period',
            'health-timeout',
            'restart',
          });

          return true;
        }
      case 'createservice':
        {
          parseSimpleProperties({
            'serviceName',
            'service',
            'imageName',
            'image',
            'version',
            'ver',
            'ports',
            'port',
            'volumes',
            'hostname',
            'host',
            'network',
            'environment',
            'env',
            'cleanContainer'
          });

          return true;
        }
      case 'removecontainer':
        {
          parseSimpleProperties({'containerName', 'container', 'force'});

          return true;
        }
      case 'start':
        {
          parseSimpleProperties({
            'containerOrServiceName',
            'containerName',
            'container',
            'serviceName',
            'service'
          });

          return true;
        }
      case 'stop':
        {
          parseSimpleProperties({
            'containerOrServiceName',
            'containerName',
            'container',
            'serviceName',
            'service'
          });

          return true;
        }
      case 'log':
      case 'logs':
        {
          parseSimpleProperties({
            'containerOrServiceName',
            'containerName',
            'container',
            'serviceName',
            'service',
            'stdout',
            'stderr',
          });
          return true;
        }
      case 'execwhich':
        {
          parseSimpleProperties();

          return true;
        }
      case 'exec':
        {
          parseSimpleProperties({
            'containerName',
            'container',
          });

          return true;
        }
      case 'formulaexec':
        {
          parseSimpleProperties({'*'});

          return true;
        }

      default:
        return false;
    }
  }

  void parseSimpleProperties([Set<String>? simpleProperties]) {
    var allSimpleProperties = false;

    if (simpleProperties != null) {
      simpleProperties =
          simpleProperties.map((e) => e.toLowerCase().trim()).toSet();

      allSimpleProperties = simpleProperties.remove('*');
    } else {
      simpleProperties = {};
    }

    for (var i = 0; i < _args.length;) {
      var arg = _args[i];

      if (arg.startsWith('--')) {
        var name = arg.substring(2).toLowerCase().trim();

        if (!allSimpleProperties && !simpleProperties.contains(name)) {
          ++i;
          continue;
        }

        _args.removeAt(i);

        String value;
        if (i < _args.length) {
          value = _args[i];
          if (value.startsWith('--')) {
            value = 'true';
          } else {
            _args.removeAt(i);
          }
        } else {
          value = 'true';
        }

        _properties[name] = value;
      } else {
        ++i;
      }
    }
  }

  String? operator [](dynamic argOrProperty) => argOrProperty is int
      ? getArg(argOrProperty)
      : getProperty('$argOrProperty');

  List<String> get args => _args.toList();

  List<String> argsSub(int start) =>
      start < args.length ? _args.sublist(start) : [];

  String? getArg(int argIndex) =>
      argIndex < _args.length ? _args[argIndex] : null;

  Map<String, String?> get properties => sortMapEntries(_properties);

  String? getProperty(String? propKey) =>
      propKey != null ? _properties[propKey.toLowerCase().trim()] : null;

  String? get(int index,
          [String? propertyKey,
          propertyKey1,
          propertyKey2,
          propertyKey3,
          propertyKey4]) =>
      getArg(index) ??
      getProperty(propertyKey) ??
      getProperty(propertyKey1) ??
      getProperty(propertyKey2) ??
      getProperty(propertyKey3) ??
      getProperty(propertyKey4);

  set returnType(ConsoleCMDReturnType type) {
    String? typeStr;

    switch (type) {
      case ConsoleCMDReturnType.stdout:
        {
          typeStr = 'stdout';
          break;
        }
      case ConsoleCMDReturnType.stderr:
        {
          typeStr = 'stderr';
          break;
        }
      case ConsoleCMDReturnType.exitCode:
        {
          typeStr = 'exit_code';
          break;
        }
      default:
        typeStr = null;
    }
    _properties['return'] = typeStr;
  }

  set defaultReturnType(ConsoleCMDReturnType type) {
    var ret = getProperty('return');
    if (isNotEmptyString(ret)) return;
    returnType = type;
  }

  ConsoleCMDReturnType get returnType {
    var ret = getProperty('return');
    if (isEmptyString(ret, trim: true)) {
      return ConsoleCMDReturnType.stdout;
    }
    ret = ret!.trim().toLowerCase();

    switch (ret) {
      case 'stdout':
        return ConsoleCMDReturnType.stdout;
      case 'err':
      case 'error':
      case 'stderr':
        return ConsoleCMDReturnType.stderr;
      case 'exit':
      case 'exitcode':
      case 'exit_code':
        return ConsoleCMDReturnType.exitCode;
      default:
        return ConsoleCMDReturnType.stdout;
    }
  }

  bool? get askAllProperties => parseBool(getProperty('*'), false);

  @override
  String toString() {
    return 'ConsoleCMD{cmd: $cmd, _args: $_args, _properties: $_properties}';
  }
}

enum ConsoleCMDReturnType { stdout, stderr, exitCode }
