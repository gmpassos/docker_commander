@Timeout(Duration(minutes: 2))
import 'dart:async';

import 'package:docker_commander/docker_commander_vm.dart';
import 'package:test/test.dart';

import 'docker_commander_test_basics.dart';
import 'logger_config.dart';

void main() async {
  configureLogger();

  var usedPorts = <int>{};

  Future<int> preSetup() async {
    for (var listenPort = 8090; listenPort <= 8099; ++listenPort) {
      if (usedPorts.contains(listenPort)) continue;

      try {
        var authenticationTable = AuthenticationTable({'admin': '123'});

        var hostServer = DockerHostServer(
            (user, pass) async => authenticationTable.checkPassword(user, pass),
            listenPort);

        await hostServer.startAndWait();

        usedPorts.add(listenPort);

        await Future.delayed(Duration(seconds: 1));

        return listenPort;
      } catch (e) {
        usedPorts.add(listenPort);
        print(e);
      }
    }

    return 0;
  }

  doBasicTests(
      (listenPort) => DockerHostRemote('localhost', listenPort,
          username: 'admin', password: '123'),
      preSetup);
}
