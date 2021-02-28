import 'package:docker_commander/docker_commander.dart';
import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _LOG = Logger('docker_commander/test');

typedef DockerHostLocalInstantiator = DockerHost Function(int listenPort);

void doBasicTests(DockerHostLocalInstantiator dockerHostLocalInstantiator,
    [dynamic Function() preSetup]) {
  group('DockerCommander basics', () {
    DockerCommander dockerCommander;

    var listenPort = 8099;

    setUp(() async {
      logTitle(_LOG, 'SETUP');

      if (preSetup != null) {
        listenPort = await preSetup();
      }

      var dockerHost = dockerHostLocalInstantiator(listenPort);
      dockerCommander = DockerCommander(dockerHost);
      _LOG.info('setUp>\tDockerCommander: $dockerCommander');

      _LOG.info('setUp>\tDockerCommander.initialize()');
      await dockerCommander.initialize();
      expect(dockerCommander.isSuccessfullyInitialized, isTrue);
      _LOG.info('setUp>\tDockerCommander: $dockerCommander');

      _LOG.info('setUp>\tDockerCommander.checkDaemon()');
      await dockerCommander.checkDaemon();
      _LOG.info('setUp>\tDockerCommander: $dockerCommander');

      expect(dockerCommander.lastDaemonCheck, isNotNull);
      _LOG.info('setUp>\tDockerCommander.lastDaemonCheck: $dockerCommander');
    });

    tearDown(() async {
      logTitle(_LOG, 'TEAR DOWN');

      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
      _LOG.info('tearDown>\tDockerCommander.close()');
      await dockerCommander.close();
      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');

      dockerCommander = null;
    });

    test('Image: hello-world', () async {
      var dockerContainer = await dockerCommander.run('hello-world');

      _LOG.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      var exitCode = await dockerContainer.waitExit();
      expect(exitCode, equals(0));

      var output = dockerContainer.stdout.asString;
      expect(output, contains('Hello from Docker!'));

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info(output);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id.isNotEmpty, isTrue);
    });

    test('Create Image hello-world', () async {
      var session = dockerCommander.session;
      var containerName = 'docker_commander_test-hello-world-$session';

      var containerInfos =
          await dockerCommander.createContainer(containerName, 'hello-world');

      _LOG.info(containerInfos);

      expect(containerInfos, isNotNull);
      expect(containerInfos.containerName, isNotNull);
      expect(containerInfos.id, isNotNull);

      var ok =
          await dockerCommander.removeContainer(containerInfos.containerName);
      expect(ok, isTrue);
    });

    test('ApacheHttpdContainer', () async {
      var apachePort = listenPort - 4000;

      _LOG.info('Starting Apache HTTP at port $apachePort');

      var dockerContainer = await ApacheHttpdContainer()
          .run(dockerCommander, hostPorts: [apachePort]);

      _LOG.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      expect(dockerContainer.ports, equals(['$apachePort:80']));

      var containersNames = await dockerCommander.psContainerNames();
      expect(containersNames, contains(dockerContainer.name));

      var hostPort = dockerContainer.hostPorts[0];

      var getURLResponse =
          await HttpClient('http://localhost:$hostPort/').get('');
      var getURLContent = getURLResponse.bodyAsString;
      _LOG.info(getURLContent);
      expect(getURLContent, contains('<html>'));

      await dockerContainer.stop(timeout: Duration(seconds: 5));

      var output = dockerContainer.stderr.asString;
      expect(output, contains('Apache'));

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info(output);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id.isNotEmpty, isTrue);
    });
  });
}
