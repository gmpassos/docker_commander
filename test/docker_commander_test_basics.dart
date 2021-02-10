import 'package:docker_commander/docker_commander.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

final _LOG = Logger('docker_commander/test');

typedef DockerHostLocalInstantiator = DockerHost Function();

void doBasicTests(DockerHostLocalInstantiator dockerHostLocalInstantiator) {
  group('DockerCommander basics', () {
    DockerCommander dockerCommander;

    setUp(() async {
      var dockerHost = dockerHostLocalInstantiator();
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
      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
      _LOG.info('tearDown>\tDockerCommander.close()');
      await dockerCommander.close();
      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
    });

    test('Image: hello-world', () async {
      var dockerContainer = await dockerCommander.run('hello-world');

      _LOG.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      await dockerContainer.waitReady();

      var exitCode = await dockerContainer.waitExit();
      expect(exitCode, equals(0));

      var output = dockerContainer.stdout.asString;
      expect(output, contains('Hello from Docker!'));

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info(output);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id.isNotEmpty, isTrue);
    });
  });
}
