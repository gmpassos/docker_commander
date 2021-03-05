import 'package:docker_commander/docker_commander_vm.dart';

import 'docker_commander_console.dart' as docker_commander_console;
import 'docker_commander_server.dart' as docker_commander_server;

void showHelp() {
  print(
      '-----------------------------------------------------------------------------');
  print('| docker_commander - version ${DockerCommander.VERSION}');
  print(
      '-----------------------------------------------------------------------------');
  print('');
  print('SERVER MODE:\n');
  print(
      '  \$> docker_commander --server %username %password %port? --public/private? --ipv6?');
  print('');
  print('CONSOLE MODE:');
  print('  \$> docker_commander --console %username %serverHost %serverPort');
  print('');
}

void main(List<String> args) async {
  var console = args.contains('--console');
  var server = args.contains('--server');

  if (console ?? false) {
    print('CONSOLE MODE:');
    docker_commander_console.main(args);
  } else if (server ?? false) {
    print('SERVER MODE:');
    docker_commander_server.main(args);
  } else {
    print('DEFAULT MODE: SERVER');
    docker_commander_server.main(args);
  }
}
