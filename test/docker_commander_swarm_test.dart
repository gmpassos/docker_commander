@Timeout(Duration(minutes: 2))
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _LOG = Logger('docker_commander/test');

void main() {
  configureLogger();

  group('DockerContainerConfig', () {
    DockerCommander dockerCommander;

    setUp(() async {
      logTitle(_LOG, 'SETUP');

      var dockerHost = DockerHostLocal();
      dockerCommander = DockerCommander(dockerHost);

      await dockerCommander.initialize();
      await dockerCommander.checkDaemon();

      _LOG.info('setUp>\tDockerCommander: $dockerCommander');
    });

    tearDown(() async {
      logTitle(_LOG, 'TEARDOWN');
      await dockerCommander.close();
      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
    });

    test('Swarm 1', () async {
      var myNodeID = await dockerCommander.swarmSelfNodeID();

      expect(myNodeID, isNull,
          reason:
              'Only can run test if Docker is not in swarm node yet! Leave swarm mode before run tests: docker swarm leave --force');

      var swarmOk = await dockerCommander.swarmInit();
      expect(swarmOk, isTrue);

      myNodeID = await dockerCommander.swarmSelfNodeID();

      _LOG.info('My swarm node ID: $myNodeID');
      expect(myNodeID, matches(RegExp(r'\w+')));

      var service = await dockerCommander.createService(
          'docker_commander_service-hello-test', 'httpd',
          replicas: 2, ports: ['4083:80']);
      expect(service, isNotNull);

      _LOG.info('Service: $service');

      var tasks = await service.listTasks();

      _LOG.info('Tasks[${tasks.length}]:');
      for (var task in tasks) {
        _LOG.info('[${task.isCurrentlyRunning ? 'RUNNING' : '...'}] - $task');
      }

      var apacheContent =
          (await HttpClient('http://localhost:4083/').get('')).bodyAsString;

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info('Apache content:');
      _LOG.info(apacheContent);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(apacheContent, contains('<html>'));

      var removed = await service.remove();
      expect(removed, isTrue);

      var leaveOK = await dockerCommander.swarmLeave(force: true);
      expect(leaveOK, isTrue);
    });
  });
}
