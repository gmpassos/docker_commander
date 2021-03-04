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

  Future<bool> executeConsoleCMD(ConsoleCMD cmd) async {
    if (cmd == null) return false;

    await _printToConsole('$cmd');

    switch (cmd.cmd) {
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
      case 'exec':
        {
          var parameters = await _requireParameters({
            'containerName': cmd.get(0, 'containerName'),
            'command': cmd.get(1, 'command'),
            'return': cmd.getProperty('return') ?? 'stdout',
          }, {
            'containerName',
            'command'
          });

          var exec = await dockerCommander.exec(parameters['containerName'],
              parameters['command'], cmd.argsSub(2));
          return await _processReturn(cmd, exec);
        }
      case 'cmd':
      case 'command':
        {
          var parameters = await _requireParameters({
            'command': cmd.get(0, 'command'),
            'return': cmd.getProperty('return') ?? 'stdout',
          }, {
            'containerName',
            'command'
          });

          var exec = await dockerCommander.command(
              parameters['command'], cmd.argsSub(1));

          return await _processReturn(cmd, exec);
        }
      default:
        return false;
    }
  }

  Future<bool> _processReturn(ConsoleCMD cmd, DockerProcess process) async {
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
          _printData(printData0, 'printData0:');

          var anyDataReceived = Completer<int>();

          var listener = output.onData.listen((d) {
            if (anyDataReceived.isCompleted) {
              _printData(d, 'listener:');
            } else {
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
              _printData(printData1, 'printData1:');
            }
          } else {
            if (!anyDataReceived.isCompleted) {
              anyDataReceived.complete(-3);
            }

            while (true) {
              await _askParameter('', '[STOP $outputName CONSUMER]');
              await _cancelStreamSubscription(listener);
              break;
            }
          }

          process.dispose();

          await _printLineToConsole();

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

  void _printData(data, [String from]) {
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
        _printToConsole(line, true, _printID, from);
      }
    }
  }

  Future<Map<String, String>> _requireParameters(
      Map<String, String> fields, Set<String> required) async {
    var parameters = <String, String>{};
    for (var name in fields.keys.toList()) {
      var value = fields[name];

      if (isNotEmptyString(value, trim: true)) {
        parameters[name] = value.trim();
      } else if (required.contains(name)) {
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
      : cmd = cmd.trim().toLowerCase().replaceAll(RegExp(r'[_\-]+'), '') {
    _args = <String>[];
    _properties = <String, String>{};

    for (var i = 0; i < args.length; ++i) {
      var arg = args[i];
      if (arg.startsWith('--')) {
        var nextI = i + 1;
        var name = arg.substring(2);

        String value;
        if (nextI < args.length) {
          value = args[nextI];
          if (value.startsWith('--')) {
            value = 'true';
          } else {
            args.removeAt(nextI);
          }
        } else {
          value = 'true';
        }

        _properties[name] = value;
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

  String operator [](dynamic argOrProperty) => argOrProperty is int
      ? getArg(argOrProperty)
      : getProperty('$argOrProperty');

  List<String> get args => _args.toList();

  List<String> argsSub(int start) =>
      start < args.length ? _args.sublist(start) : [];

  String getArg(int argIndex) =>
      argIndex != null && argIndex < _args.length ? _args[argIndex] : null;

  String getProperty(String propKey) =>
      propKey != null ? _properties[propKey] : null;

  String get(int index, [String propertyKey]) =>
      getArg(index) ?? getProperty(propertyKey);

  ConsoleCMDReturnType get returnType {
    var ret = getProperty('return');
    if (isEmptyString(ret, trim: true)) {
      return ConsoleCMDReturnType.STDOUT;
    }
    ret = ret.trim().toLowerCase();

    switch (ret) {
      case 'stdout':
        return ConsoleCMDReturnType.STDOUT;
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

  @override
  String toString() {
    return 'ConsoleCMD{cmd: $cmd, _args: $_args, _properties: $_properties}';
  }
}

enum ConsoleCMDReturnType { STDOUT, STDERR, EXIT_CODE }
