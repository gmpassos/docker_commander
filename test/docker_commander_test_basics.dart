import 'package:docker_commander/docker_commander.dart';
import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _log = Logger('docker_commander/test');

typedef DockerHostLocalInstantiator = DockerHost Function(int listenPort);

void doBasicTests(DockerHostLocalInstantiator dockerHostLocalInstantiator,
    [dynamic Function()? preSetup]) {
  group('DockerCommander basics', () {
    DockerCommander? dockerCommander;

    var listenPort = 8099;

    setUp(() async {
      logTitle(_log, 'SETUP');

      if (preSetup != null) {
        listenPort = await preSetup();
      }

      var dockerHost = dockerHostLocalInstantiator(listenPort);
      dockerCommander = DockerCommander(dockerHost);
      _log.info('setUp>\tDockerCommander: $dockerCommander');

      _log.info('setUp>\tDockerCommander.initialize()');
      await dockerCommander!.initialize();
      expect(dockerCommander!.isSuccessfullyInitialized, isTrue);
      _log.info('setUp>\tDockerCommander: $dockerCommander');

      _log.info('setUp>\tDockerCommander.checkDaemon()');
      await dockerCommander!.checkDaemon();
      _log.info('setUp>\tDockerCommander: $dockerCommander');

      expect(dockerCommander!.lastDaemonCheck, isNotNull);
      _log.info('setUp>\tDockerCommander.lastDaemonCheck: $dockerCommander');

      logTitle(_log, 'TEST');
    });

    tearDown(() async {
      logTitle(_log, 'TEAR DOWN');

      _log.info('tearDown>\tDockerCommander: $dockerCommander');
      _log.info('tearDown>\tDockerCommander.close()');
      await dockerCommander!.close();
      _log.info('tearDown>\tDockerCommander: $dockerCommander');

      dockerCommander = null;
    });

    test('Image: hello-world', () async {
      var dockerContainer = await dockerCommander!.run('hello-world');

      _log.info(dockerContainer);

      expect(dockerContainer!.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      var exitCode = await dockerContainer.waitExit();
      expect(exitCode, equals(0));

      var output = dockerContainer.stdout!.asString;
      expect(output, contains('Hello from Docker!'));

      _log.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _log.info(output);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id!.isNotEmpty, isTrue);
    });

    test('Create Image hello-world', () async {
      var session = dockerCommander!.session;
      var containerName = 'docker_commander_test-hello-world-$session';

      var containerInfos =
          await dockerCommander!.createContainer(containerName, 'hello-world');

      _log.info(containerInfos);

      expect(containerInfos, isNotNull);
      expect(containerInfos!.containerName, isNotNull);
      expect(containerInfos.id, isNotNull);

      var started =
          await dockerCommander!.startContainer(containerInfos.containerName);
      expect(started, isTrue);

      await dockerCommander!.stopContainer(containerInfos.containerName,
          timeout: Duration(seconds: 5));

      var ok =
          await dockerCommander!.removeContainer(containerInfos.containerName);
      expect(ok, isTrue);
    });

    test('ApacheHttpdContainer', () async {
      var apachePort = listenPort - 4000;

      _log.info('Starting Apache HTTP at port $apachePort');

      var dockerContainer = await ApacheHttpdContainerConfig()
          .run(dockerCommander!, hostPorts: [apachePort]);

      _log.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      expect(dockerContainer.ports, equals(['$apachePort:80']));

      var containersNames = await dockerCommander!.psContainerNames();
      expect(containersNames, contains(dockerContainer.name));

      var hostPort = dockerContainer.hostPorts[0];

      var getURLResponse =
          await HttpClient('http://localhost:$hostPort/').get('');
      var getURLContent = getURLResponse.bodyAsString;
      _log.info(getURLContent);
      expect(getURLContent, contains('<html>'));

      await dockerContainer.stop(timeout: Duration(seconds: 5));

      var output = dockerContainer.stderr!.asString;
      expect(output, contains('Apache'));

      _log.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _log.info(output);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id!.isNotEmpty, isTrue);
    });
  });
}
