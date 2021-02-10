@Timeout(Duration(minutes: 5))

import 'package:docker_commander/src/docker_commander_remote.dart';
import 'package:docker_commander/src/docker_commander_server.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'docker_commander_test_basics.dart';

void main() async {
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.time}\t[${record.level.name}]\t${record.message}');
  });

  var authenticationTable = AuthenticationTable({'admin': '123'});

  var hostServer = DockerHostServer(
      (user, pass) async => authenticationTable.checkPassword(user, pass),
      8099);

  await hostServer.startAndWait();

  doBasicTests(() => DockerHostRemote('localhost', hostServer.listenPort,
      username: 'admin', password: '123'));
}