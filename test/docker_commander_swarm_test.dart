@Tags(['swarm'])
@Timeout(Duration(minutes: 2))
@TestOn('vm')
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _log = Logger('docker_commander/test');

void main() {
  configureLogger();

  group('DockerContainerConfig', () {
    late DockerCommander dockerCommander;

    setUp(() async {
      logTitle(_log, 'SETUP');

      var dockerHost = DockerHostLocal();
      dockerCommander = DockerCommander(dockerHost);

      await dockerCommander.initialize();
      await dockerCommander.checkDaemon();

      _log.info('setUp>\tDockerCommander: $dockerCommander');

      logTitle(_log, 'TEST');
    });

    tearDown(() async {
      logTitle(_log, 'TEARDOWN');
      await dockerCommander.close();
      _log.info('tearDown>\tDockerCommander: $dockerCommander');
    });

    test('Swarm 1', () async {
      var myNodeID = await dockerCommander.swarmSelfNodeID();

      expect(myNodeID, isNull,
          reason:
              'Only can run test if Docker is not in swarm node yet! Leave swarm mode before run tests: docker swarm leave --force');

      expect(await dockerCommander.getSwarmInfos(), isNull);

      var swarmInfos = await dockerCommander.swarmInit();
      expect(swarmInfos, isNotNull);
      expect(swarmInfos!.nodeID, isNotEmpty);
      expect(swarmInfos.managerToken, isNotEmpty);
      expect(swarmInfos.workerToken, isNotEmpty);
      expect(swarmInfos.advertiseAddress, isNotEmpty);
      expect(swarmInfos.managerToken == swarmInfos.workerToken, isFalse);

      _log.info('SwarmInfos: $swarmInfos');

      myNodeID = await dockerCommander.swarmSelfNodeID();
      expect(myNodeID, matches(RegExp(r'\w+')));
      expect(myNodeID, equals(swarmInfos.nodeID));

      _log.info('My swarm node ID: $myNodeID');
      expect(myNodeID, matches(RegExp(r'\w+')));

      var service = await dockerCommander.createService(
          'docker_commander_service-hello-test', 'httpd',
          replicas: 2, ports: ['4083:80']);
      expect(service, isNotNull);

      _log.info('Service: $service');

      var tasks = await service!.listTasks();

      _log.info('Tasks[${tasks!.length}]:');
      for (var task in tasks) {
        _log.info('[${task.isCurrentlyRunning ? 'RUNNING' : '...'}] - $task');
      }

      var apacheContent =
          (await HttpClient('http://localhost:4083/').get('')).bodyAsString;

      _log.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _log.info('Apache content:');
      _log.info(apacheContent);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(apacheContent, contains('<html>'));

      var apacheLogs = await service.catLogs(
          waitDataMatcher: 'GET /', waitDataTimeout: Duration(seconds: 1));

      _log.info(
          '------------------------------------------------------------ Apache logs:');
      _log.info(apacheLogs);
      expect(apacheLogs, contains('GET /'));
      _log.info('------------------------------------------------------------');

      var removed = await service.remove();
      expect(removed, isTrue);

      var leaveOK = await dockerCommander.swarmLeave(force: true);
      expect(leaveOK, isTrue);
    });
  });
}
