import 'dart:io';

import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

const int defaultServerPort = 8099;

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
  print('| docker_commander_server - version ${DockerCommander.VERSION}');
  print(
      '-----------------------------------------------------------------------------');
  print('');
  print('USAGE:\n');
  print(
      '  \$> docker_commander_server %username %password %port? --public/private? --ipv6?');
  print('');
  print('## Default Server port: $defaultServerPort');
  print('');
}

void main(List<String> args) async {
  print('ARGS: $args');
  args = args.toList();

  var help =
      args.contains('--help') || args.contains('-help') || args.contains('-h');

  if (help) {
    showHelp();
    return;
  }

  configureLogger();

  var public = args.contains('--public');
  var private = args.contains('--private');
  var ipv6 = args.contains('--ipv6');
  var production = args.contains('--production');

  if (private) {
    public = false;
  }

  args.removeWhere((a) => a.startsWith('--'));

  if (args.length < 2) {
    showHelp();
    return;
  }

  var username = args[0];
  var password = args[1];

  if (isEmptyString(username, trim: true) ||
      isEmptyString(password, trim: true)) {
    showHelp();
    return;
  }

  var port = args.length > 2 && isInt(args[2])
      ? parseInt(args[2], defaultServerPort)!
      : defaultServerPort;

  var authenticationTable = AuthenticationTable({username: password});
  print('\n$authenticationTable');
  print('- Username: $username\n');

  var hostServer = DockerHostServer(
    (user, pass) async => authenticationTable.checkPassword(user, pass),
    port,
    public: public,
    ipv6: ipv6,
  );

  print('$hostServer\n');

  var checkSecurityOK = await hostServer.checkAuthenticationBasicSecurity();

  if (!checkSecurityOK && production) {
    print('** Server with weak credentials! Aborting server startup!');
    exit(1);
  }

  await hostServer.startAndWait();

  print('\nRUNNING SERVER AT PORT: ${hostServer.listenPort}');
}
