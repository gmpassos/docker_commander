import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

const int DEFAULT_SERVER_PORT = 8099;

bool _loggerConfigured = false;

void configureLogger() {
  if (_loggerConfigured) return;
  _loggerConfigured = true;

  Logger.root.level = Level.ALL; // defaults to Level.INFO

  Logger.root.onRecord.listen((record) {
    print('${record.time}\t[${record.level.name}]\t${record.message}');

    if (record.error != null) {
      print(record.error);
    }

    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  });
}

void showHelp() {
  print(
      '-----------------------------------------------------------------------------');
  print('| docker_commander_console - version ${DockerCommander.VERSION}');
  print(
      '-----------------------------------------------------------------------------');
  print('');
  print('USAGE:\n');
  print('  \$> docker_commander_console %username %server_host %port?');
  print('');
  print('## Default Server port: $DEFAULT_SERVER_PORT');
  print('');
}

void _printLine() {
  print(
      '------------------------------------------------------------------------------');
}

Future<void> _printToConsole(String line, bool output) async {
  if (output ?? false) {
    print('>> $line');
  } else {
    print(line);
  }
}

Future<String> _ask(String name, [String description]) async {
  if (name == 'CONTINUE') {
    name = 'Press ENTER to continue';
  }

  if (isNotEmptyString(description, trim: true)) {
    print('\n$description');
    if (isNotEmptyString(name, trim: true)) {
      stdout.write('$name> ');
    }
  } else {
    stdout.write('\n$name> ');
  }

  var resp = await _readStdinLine();
  resp = resp.trim();
  return resp;
}

/// [stdin] as a broadcast [Stream] of lines.
Stream<String> _stdinLineStreamBroadcaster = stdin
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .asBroadcastStream();

/// Reads a single line from [stdin] asynchronously.
Future<String> _readStdinLine() async {
  var lineCompleter = Completer<String>();

  var listener = _stdinLineStreamBroadcaster.listen((line) {
    if (!lineCompleter.isCompleted) {
      lineCompleter.complete(line);
    }
  });

  return lineCompleter.future.then((line) {
    listener.cancel();
    return line;
  });
}

void main(List<String> args) async {
  print('[ARGS: $args]');
  args = args.toList();

  var help =
      args.contains('--help') || args.contains('-help') || args.contains('-h');

  if (help) {
    showHelp();
    return;
  }

  configureLogger();

  args.removeWhere((a) => a.startsWith('--'));

  var username = args.isNotEmpty ? args[0] : await _ask('username');
  var serverHost = args.length > 1 ? args[1] : await _ask('serverHost');

  if (isEmptyString(username, trim: true) ||
      isEmptyString(serverHost, trim: true)) {
    showHelp();
    return;
  }

  var serverPort = args.length > 2 && isInt(args[2])
      ? parseInt(args[2], DEFAULT_SERVER_PORT)
      : DEFAULT_SERVER_PORT;

  var password = await _ask('password',
      'Please, provide the password for user \'$username\' at docker_commander server $serverHost:$serverPort.');

  var dockerHostRemote = DockerHostRemote(serverHost, serverPort,
      username: username, password: password);

  var dockerCommander = DockerCommander(dockerHostRemote);

  var console = DockerCommanderConsole(dockerCommander, _ask, _printToConsole);

  _printLine();
  print(console);

  print('Initializing...');

  var initOK = false;
  try {
    initOK = await dockerCommander.initialize();
    print('Initialization: $initOK');
  } catch (e, s) {
    print('** Initialization ERROR: $e');
    print(s);
  }

  if (!initOK) {
    print(
        "** Can't connect to docker_commander server at $serverHost:$serverPort!");
    exit(1);
  }

  _printLine();

  while (true) {
    stdout.write('\n\$> ');
    var line = await _readStdinLine();
    line = line.trim();

    if (line.isEmpty) {
      continue;
    } else if (line.toLowerCase() == 'exit') {
      break;
    }

    var cmd = ConsoleCMD.parse(line);

    try {
      var ok = await console.executeConsoleCMD(cmd);
      if (!ok) {
        print('** CMD NOT COMPLETED: $cmd\n');
      }
    } catch (e, s) {
      print('** CMD ERROR: $cmd\n');
      print(e);
      print(s);
    }

    if (cmd.cmd == 'close') {
      break;
    }
  }

  _printLine();

  print('By!');
  exit(0);
}
