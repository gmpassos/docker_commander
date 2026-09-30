@Timeout(Duration(minutes: 2))
@TestOn('vm')
import 'dart:async';

import 'package:docker_commander/docker_commander_vm.dart';
import 'package:test/test.dart';

import 'docker_commander_test_basics.dart';
import 'logger_config.dart';

Future<void> main() async {
  configureLogger();

  var dockerRunning = await DockerHost.isDaemonRunning(DockerHostLocal());

  var usedPorts = <int>{};

  Future<int> preSetup() async {
    // A server per test (closed by the test), so one port per test:
    for (var listenPort = 8090; listenPort <= 8129; ++listenPort) {
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

  DockerHost remoteHost(int listenPort) =>
      DockerHostRemote('localhost', listenPort,
          username: 'admin', password: '123');

  doBasicTests(dockerRunning, remoteHost, preSetup);

  doRunOptionsTests(dockerRunning, remoteHost, preSetup);
}
