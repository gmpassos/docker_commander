import 'dart:async';

import 'package:docker_commander/docker_commander.dart';
import 'package:swiss_knife/swiss_knife.dart';

typedef ParameterProvider = Future<String> Function(
    String name, String description);

typedef ConsoleOutput = Future<void> Function(String line, bool output);

class DockerCommanderConsole {
  final DockerCommander dockerCommander;
  final ParameterProvider parameterProvider;
  final ConsoleOutput consoleOutput;

  DockerCommanderConsole(
      this.dockerCommander, this.parameterProvider, this.consoleOutput);

  Future<bool> executeCommand(String line) {
    var cmd = ConsoleCMD.parse(line);
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
    await _printToConsole(
        '  - create-container %containerName %imageName %version %ports %volumes %hostname %network %environment --cleanContainer');
    await _printToConsole(
        '  - create-service %serviceName %imageName %version %replicas %ports %volumes %hostname %network %environment');
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
    await _printLineToConsole();
  }

  Future<bool> executeConsoleCMD(ConsoleCMD cmd) async {
    if (cmd == null) return false;

    await _printToConsole('$cmd');

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
      case 'createcontainer':
        {
          cmd.parseSimpleProperties({
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
            'cleanContainer'
          });

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
          }, {
            'containerName',
            'imageName',
          }, cmd.askAllProperties);

          var containerInfos = await dockerCommander.createContainer(
            parameters['containerName'],
            parameters['imageName'],
            version: parameters['version'],
            ports: parseStringFromInlineList(
                parameters['ports'], RegExp(r'\s*,\s*')),
            volumes: parseFromInlineMap(
                parameters['volumes'], RegExp(r'[;|]'), RegExp(r'[:=]')),
            hostname: parameters['hostname'],
            network: parameters['network'],
            environment: parseFromInlineMap(
                parameters['volumes'], RegExp(r'[|]'), RegExp(r'[:=]')),
            cleanContainer: parseBool(parameters['cleanContainer']),
          );

          if (containerInfos != null) {
            await _printToConsole('CREATED CONTAINER> $containerInfos');
            return true;
          }

          return false;
        }
      case 'createservice':
        {
          cmd.parseSimpleProperties({
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

          var service = await dockerCommander.createService(
            parameters['serviceName'],
            parameters['imageName'],
            version: parameters['version'],
            replicas: parseInt(parameters['replicas']),
            ports: parseStringFromInlineList(
                parameters['ports'], RegExp(r'\s*,\s*')),
            volumes: parseFromInlineMap(
                parameters['volumes'], RegExp(r'[;|]'), RegExp(r'[:=]')),
            hostname: parameters['hostname'],
            network: parameters['network'],
            environment: parseFromInlineMap(
                parameters['volumes'], RegExp(r'[|]'), RegExp(r'[:=]')),
          );

          if (service != null) {
            await _printToConsole('CREATED SERVICE> $service');
            return true;
          }

          return false;
        }
      case 'start':
        {
          cmd.parseSimpleProperties({
            'containerOrServiceName',
            'containerName',
            'container',
            'serviceName',
            'service'
          });

          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerOrServiceName',
                'containerName', 'container', 'serviceName', 'service'),
          }, {
            'containerName',
          }, cmd.askAllProperties);

          var ok =
              await dockerCommander.startContainer(parameters['containerName']);

          await _printToConsole('STARTED CONTAINER: $ok');

          return ok;
        }
      case 'stop':
        {
          cmd.parseSimpleProperties({
            'containerOrServiceName',
            'containerName',
            'container',
            'serviceName',
            'service'
          });

          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerOrServiceName',
                'containerName', 'container', 'serviceName', 'service'),
          }, {
            'containerName',
          }, cmd.askAllProperties);

          var ok =
              await dockerCommander.stopContainer(parameters['containerName']);

          await _printToConsole('STOPPED CONTAINER: $ok');

          return ok;
        }
      case 'log':
      case 'logs':
        {
          cmd.parseSimpleProperties({
            'containerOrServiceName',
            'containerName',
            'container',
            'serviceName',
            'service',
            'stdout',
            'stderr',
          });

          cmd.defaultReturnType = ConsoleCMDReturnType.STDOUT;

          var parameters = await _requireParameters({
            'name': cmd.get(0, 'containerOrServiceName', 'containerName',
                'container', 'serviceName', 'service'),
            'stdout': cmd.getProperty('stdout'),
            'stderr': cmd.getProperty('stderr'),
          }, {
            'name',
          }, cmd.askAllProperties);

          if (parseBool(parameters['stdout'], false)) {
            cmd.returnType = ConsoleCMDReturnType.STDOUT;
          } else if (parseBool(parameters['stderr'], false)) {
            cmd.returnType = ConsoleCMDReturnType.STDERR;
          }

          var name = parameters['name'];

          var containersNames = await dockerCommander.psContainerNames();

          await _printToConsole('CONTAINERS: $containersNames');

          DockerProcess process;
          if (containersNames != null && containersNames.contains(name)) {
            process = await dockerCommander.openContainerLogs(name);
          } else {
            var servicesNames = await dockerCommander.listServicesNames();
            await _printToConsole('SERVICES: $servicesNames');

            if (servicesNames != null && servicesNames.contains(name)) {
              process = await dockerCommander.openServiceLogs(name);
            } else {
              return false;
            }
          }

          return await _processReturn(cmd, process);
        }
      case 'execwhich':
        {
          cmd.parseSimpleProperties();

          cmd.returnType = ConsoleCMDReturnType.STDOUT;

          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerName', 'container'),
            'binary': cmd.get(1, 'binaryName', 'binary'),
          }, {
            'containerName',
            'binary',
          }, cmd.askAllProperties);

          var exec = await dockerCommander.execWhich(
              parameters['containerName'], parameters['binary']);

          await _printToConsole(exec);

          return true;
        }
      case 'exec':
        {
          cmd.parseSimpleProperties({
            'containerName',
            'container',
          });

          cmd.defaultReturnType = ConsoleCMDReturnType.STDOUT;

          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerName', 'container'),
            'command': cmd.get(1, 'command', 'cmd'),
          }, {
            'containerName',
            'command'
          }, cmd.askAllProperties);

          var exec = await dockerCommander.exec(parameters['containerName'],
              parameters['command'], cmd.argsSub(2));
          return await _processReturn(cmd, exec);
        }
      case 'docker':
      case 'cmd':
      case 'command':
        {
          cmd.defaultReturnType = ConsoleCMDReturnType.STDOUT;

          var parameters = await _requireParameters({
            'command': cmd.get(0, 'command', 'cmd'),
          }, {
            'command'
          }, cmd.askAllProperties);

          print(parameters);

          var exec = await dockerCommander.command(
              parameters['command'], cmd.argsSub(1));

          return await _processReturn(cmd, exec);
        }
      default:
        return false;
    }
  }

  Future<bool> _processReturn(ConsoleCMD cmd, DockerProcess process,
      [bool allowPrintAsOutput = true]) async {
    if (process == null) {
      return false;
    }

    switch (cmd.returnType) {
      case ConsoleCMDReturnType.STDERR:
      case ConsoleCMDReturnType.STDOUT:
        {
          var outputName = cmd.returnType == ConsoleCMDReturnType.STDERR
              ? 'STDERR'
              : 'STDOUT';

          var output = cmd.returnType == ConsoleCMDReturnType.STDERR
              ? process.stderr
              : process.stdout;

          await _printLineToConsole();

          var printData0 = output.asString;
          var printData0_entriesRemoved = output.entriesRemoved;
          var printData0_contentRemoved = output.contentRemoved;
          _printData(printData0, allowPrintAsOutput, 'printData0');

          var anyDataReceived = Completer<int>();

          var waitingData = <String>[];

          var listener = output.onData.listen((d) {
            if (anyDataReceived.isCompleted) {
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

            await process.stdout.waitData(timeout: Duration(milliseconds: 300));

            var printData1 = output.asStringFrom(
                entriesRealOffset: printData0_entriesRemoved,
                contentRealOffset:
                    printData0_contentRemoved + printData0.length);

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
      case ConsoleCMDReturnType.EXIT_CODE:
        {
          var exitCode = await process.waitExit();
          await _printToConsole('EXIT CODE: $exitCode');
          return true;
        }
      default:
        return false;
    }
  }

  static final RegExp _REGEXP_LINE_BREAK = RegExp(r'\r?\n', multiLine: false);
  static final RegExp _REGEXP_LINE_BREAK_ENDING =
      RegExp(r'\r?\n$', multiLine: false);

  Future<void> _cancelStreamSubscription(StreamSubscription listener) async {
    try {
      return await listener.cancel();
    }
    // ignore: empty_catches
    catch (ignore) {}
  }

  int _printID = 0;

  void _printData(data, bool allowPrintAsOutput, [String from]) {
    var lines;

    if (data is List<String>) {
      var s = data.join();
      if (data.isNotEmpty) {
        lines = s
            .replaceFirst(_REGEXP_LINE_BREAK_ENDING, '')
            .split(_REGEXP_LINE_BREAK);
      }
    } else if (data is String) {
      if (data.isNotEmpty) {
        lines = data
            .replaceFirst(_REGEXP_LINE_BREAK_ENDING, '')
            .split(_REGEXP_LINE_BREAK);
      }
    } else if (data is List<int>) {
      var s = String.fromCharCodes(data);
      if (s.isNotEmpty) {
        lines = s
            .replaceFirst(_REGEXP_LINE_BREAK_ENDING, '')
            .split(_REGEXP_LINE_BREAK);
      }
    } else if (data is int) {
      var s = String.fromCharCodes([data]);
      if (s.isNotEmpty) {
        lines = s
            .replaceFirst(_REGEXP_LINE_BREAK_ENDING, '')
            .split(_REGEXP_LINE_BREAK);
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

  Future<Map<String, String>> _requireParameters(Map<String, String> fields,
      Set<String> required, bool askAllProperties) async {
    var parameters = <String, String>{};
    for (var name in fields.keys.toList()) {
      var value = fields[name];

      if (isNotEmptyString(value, trim: true)) {
        parameters[name] = value.trim();
      } else if (required.contains(name) || askAllProperties) {
        var value = await _askParameter(name);
        if (isNotEmptyString(value, trim: true)) {
          parameters[name] = value.trim();
        }
      }
    }
    return parameters;
  }

  Future<String> _askParameter(String name, [String description]) async {
    var value = await parameterProvider(name, description);
    return value;
  }

  Future<void> _printToConsole(String line,
          [bool output, int printID, String from]) =>
      consoleOutput(line, output);

  Future<void> _printLineToConsole() => _printToConsole(
      '------------------------------------------------------------------------------');

  @override
  String toString() {
    return 'DockerCommanderConsole{dockerCommander: $dockerCommander}';
  }
}

class ConsoleCMD {
  final String cmd;

  List<String> _args;
  Map<String, String> _properties;

  ConsoleCMD(String cmd, List<String> args)
      : cmd = cmd.trim().toLowerCase().replaceAll(RegExp(r'[\s._\-]+'), '') {
    _args = <String>[];
    _properties = <String, String>{};

    for (var i = 0; i < args.length; ++i) {
      var arg = args[i];
      if (arg.startsWith('----')) {
        var nextI = i + 1;
        var name = arg.substring(4);

        String value;
        if (nextI < args.length) {
          value = args[nextI];
          if (value.startsWith('----')) {
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
  }

  factory ConsoleCMD.parse(String line) {
    if (line == null) return null;
    line = line.trim();
    if (line.isEmpty) return null;
    var parts = line.split(RegExp(r'\s+'));

    var cmd = parts[0];
    var args = parts.length > 1 ? parts.sublist(1) : [];

    return ConsoleCMD(cmd, args.map(parseString).toList());
  }

  void parseSimpleProperties([Set<String> simpleProperties]) {
    if (simpleProperties != null) {
      simpleProperties =
          simpleProperties.map((e) => e.toLowerCase().trim()).toSet();
    }

    for (var i = 0; i < _args.length; ++i) {
      var arg = _args[i];

      if (arg.startsWith('--')) {
        var name = arg.substring(2).toLowerCase().trim();

        if (simpleProperties != null && !simpleProperties.contains(name)) {
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
      }
    }
  }

  String operator [](dynamic argOrProperty) => argOrProperty is int
      ? getArg(argOrProperty)
      : getProperty('$argOrProperty');

  List<String> get args => _args.toList();

  List<String> argsSub(int start) =>
      start < args.length ? _args.sublist(start) : [];

  String getArg(int argIndex) =>
      argIndex != null && argIndex < _args.length ? _args[argIndex] : null;

  String getProperty(String propKey) =>
      propKey != null ? _properties[propKey.toLowerCase().trim()] : null;

  String get(int index,
          [String propertyKey,
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
    var typeStr;

    switch (type) {
      case ConsoleCMDReturnType.STDOUT:
        {
          typeStr = 'stdout';
          break;
        }
      case ConsoleCMDReturnType.STDERR:
        {
          typeStr = 'stderr';
          break;
        }
      case ConsoleCMDReturnType.EXIT_CODE:
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
      return ConsoleCMDReturnType.STDOUT;
    }
    ret = ret.trim().toLowerCase();

    switch (ret) {
      case 'stdout':
        return ConsoleCMDReturnType.STDOUT;
      case 'err':
      case 'error':
      case 'stderr':
        return ConsoleCMDReturnType.STDERR;
      case 'exit':
      case 'exitcode':
      case 'exit_code':
        return ConsoleCMDReturnType.EXIT_CODE;
      default:
        return ConsoleCMDReturnType.STDOUT;
    }
  }

  bool get askAllProperties => parseBool(getProperty('*'), false);

  @override
  String toString() {
    return 'ConsoleCMD{cmd: $cmd, _args: $_args, _properties: $_properties}';
  }
}

enum ConsoleCMDReturnType { STDOUT, STDERR, EXIT_CODE }
