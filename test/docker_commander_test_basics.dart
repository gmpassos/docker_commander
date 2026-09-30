import 'package:docker_commander/docker_commander.dart';
import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _log = Logger('docker_commander/test');

typedef DockerHostLocalInstantiator = DockerHost Function(int listenPort);

Future<void> doBasicTests(
    bool dockerRunning, DockerHostLocalInstantiator dockerHostLocalInstantiator,
    [dynamic Function()? preSetup]) async {
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
  }, skip: !dockerRunning);

  await doRunOptionsTests(dockerRunning, dockerHostLocalInstantiator, preSetup);
}

/// Returns `docker container inspect --format [format]` of [name].
Future<String> inspectContainer(
    DockerCommander dockerCommander, String name, String format) async {
  var process = await dockerCommander
      .command('container', ['inspect', '--format', format, name]);
  expect(await process!.waitExit(), equals(0),
      reason: 'docker container inspect $name');
  await process.stdout!
      .waitForDataMatch(RegExp(r'\S'), timeout: Duration(seconds: 5));
  return process.stdout!.asString.trim();
}

/// [DockerRunOptions] against a real Docker daemon, through a local or a
/// remote host: every flag must be accepted by Docker and take effect.
Future<void> doRunOptionsTests(
    bool dockerRunning, DockerHostLocalInstantiator dockerHostLocalInstantiator,
    [dynamic Function()? preSetup]) async {
  group('DockerRunOptions (integration)', () {
    late DockerCommander dockerCommander;
    var listenPort = 8099;

    Future<DockerCommander> newCommander() async {
      var dc = DockerCommander(dockerHostLocalInstantiator(listenPort));
      await dc.initialize();
      await dc.checkDaemon();
      return dc;
    }

    setUp(() async {
      if (preSetup != null) {
        listenPort = await preSetup();
      }
      dockerCommander = await newCommander();
    });

    tearDown(() async {
      var removed = await dockerCommander.cleanupSession();
      _log.info('tearDown> removed containers of this session: $removed');
      await dockerCommander.close();
    });

    test('flags reach Docker and take effect', () async {
      var script = [
        'id -u',
        'pwd',
        'ulimit -n',
        'grep myhost /etc/hosts',
        'df -k /dev/shm | tail -1',
        'touch /readonly-test 2>/dev/null && echo WRITABLE || echo READONLY',
        'touch /tmp/x && echo TMPFS_OK',
        r'echo "ENV=$FOO"',
        'echo started',
        'sleep 30',
      ].join('; ');

      var container = await dockerCommander.run(
        'alpine',
        imageArgs: ['-c', script],
        options: DockerRunOptions(
          cleanContainer: true,
          entrypoint: 'sh',
          user: '1000:1000',
          workdir: '/tmp',
          environment: {'FOO': 'bar'},
          ulimits: {'nofile': '1024:2048'},
          addHosts: {'myhost': '10.1.2.3'},
          shmSize: '32m',
          tmpfs: {'/tmp': ''},
          extraArgs: ['--read-only'],
          memory: '64m',
          cpus: '0.5',
          init: true,
          stopSignal: 'SIGTERM',
          stopTimeout: Duration(seconds: 3),
          pull: DockerPullPolicy.missing,
          labels: {'docker_commander.test': 'flags'},
        ),
      );

      expect(container, isNotNull);
      expect(
          await container!.stdout!
              .waitForDataMatch('started', timeout: Duration(seconds: 20)),
          isTrue);

      var lines = container.stdout!.asString
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .toList();
      _log.info('flags output: $lines');

      expect(lines, contains('1000')); // --user
      expect(lines, contains('/tmp')); // --workdir
      expect(lines, contains('1024')); // --ulimit
      expect(lines.any((l) => l.contains('10.1.2.3') && l.contains('myhost')),
          isTrue); // --add-host
      expect(lines.any((l) => l.contains('32768')), isTrue); // --shm-size
      expect(lines, contains('READONLY')); // --read-only (extraArgs)
      expect(lines, contains('TMPFS_OK')); // --tmpfs
      expect(lines, contains('ENV=bar')); // -e

      expect(
          await inspectContainer(
              dockerCommander,
              container.name,
              '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} '
              '{{.HostConfig.Init}} {{.Config.StopSignal}} '
              '{{.Config.StopTimeout}} '
              '{{index .Config.Labels "docker_commander.test"}} '
              '{{index .Config.Labels "docker_commander.session"}}'),
          equals('67108864 500000000 true SIGTERM 3 flags '
              '${dockerCommander.session}'));

      // No health check:
      expect(await container.healthStatus(), isNull);
      expect(await container.waitHealthy(), isFalse);

      await container.stop(timeout: Duration(seconds: 5));
      await container.waitExit();
    });

    test('legacy health parameters reach Docker', () async {
      var container = await dockerCommander.run(
        'alpine',
        imageArgs: ['sh', '-c', 'echo started; sleep 30'],
        healthCmd: 'true',
        healthInterval: Duration(milliseconds: 500),
        healthRetries: 3,
      );

      expect(
          await container!.waitHealthy(timeout: Duration(seconds: 20)), isTrue);
      expect(await container.healthStatus(), equals('healthy'));

      await container.stop(timeout: Duration(seconds: 1));
    });

    test('restart through DockerCommander.run', () async {
      var container = await dockerCommander.run(
        'alpine',
        imageArgs: ['sh', '-c', 'echo started; sleep 30'],
        cleanContainer: false,
        restart: 'on-failure:3',
      );

      expect(
          await inspectContainer(
              dockerCommander,
              container!.name,
              '{{.HostConfig.RestartPolicy.Name}}:'
              '{{.HostConfig.RestartPolicy.MaximumRetryCount}}'),
          equals('on-failure:3'));

      expect(await dockerCommander.removeContainer(container.name, force: true),
          isTrue);
    });

    test('createContainer with options', () async {
      var name = 'docker_commander_test-create-${dockerCommander.session}';

      var infos = await dockerCommander.createContainer(name, 'alpine',
          options: DockerRunOptions(
            tmpfs: {'/data': 'size=16m'},
            labels: {'docker_commander.test': 'create'},
          ));

      expect(infos, isNotNull);
      expect(infos!.id, isNotEmpty);

      expect(
          await dockerCommander
              .listContainersByLabel({'docker_commander.test': 'create'}),
          contains(name));

      expect(
          await inspectContainer(
              dockerCommander, name, '{{index .HostConfig.Tmpfs "/data"}}'),
          equals('size=16m'));

      // The session label: cleanupSession removes it.
      expect(await dockerCommander.cleanupSession(), contains(name));
      expect(
          await dockerCommander.listContainersByLabel({
            'docker_commander.test': 'create',
            DockerRunOptions.labelSession: '${dockerCommander.session}',
          }),
          isEmpty);
    });

    test('PostgreSQL: ephemeral, settings and a host port chosen by Docker',
        () async {
      // `settings` travel as `imageArgs`: through a remote host this also
      // covers the server decoding them.
      var container = await PostgreSQLContainerConfig(
        hostPort: 0,
        ephemeral: true,
        settings: {'max_connections': '42'},
      ).run(dockerCommander);

      var hostPort = container.hostPortFor(5432);
      expect(hostPort, isNotNull);
      expect(container.ports, equals(['$hostPort:5432']));
      expect(await dockerCommander.getContainerPortMappings(container.name),
          equals({5432: hostPort}));

      expect(await container.runSQLScript('SHOW max_connections;'),
          contains('42'));
      expect(await container.runSQLScript('SHOW synchronous_commit;'),
          contains('off'));

      await container.stop(timeout: Duration(seconds: 5));
    });

    test('reuse across sessions, and cleanupSession per session', () async {
      config() => PostgreSQLContainerConfig(
            hostPort: 0,
            ephemeral: true,
            options: DockerRunOptions(reuse: true),
          );

      var first = await config().run(dockerCommander);
      expect(first.isReused, isFalse);

      // Another session (another client, for a remote host). Not closed:
      // closing a remote client also closes the server.
      var other = await newCommander();
      expect(other.session, isNot(equals(dockerCommander.session)));

      var second = await config().run(other);
      expect(second.isReused, isTrue);
      expect(second.name, equals(first.name));
      expect(second.id, equals(first.id));
      expect(second.hostPortFor(5432), equals(first.hostPortFor(5432)));

      // The reused container belongs to the first session:
      expect(await other.cleanupSession(), isEmpty);
      expect(await dockerCommander.psContainerNames(), contains(first.name));

      expect(await dockerCommander.cleanupSession(), contains(first.name));

      // Nothing running with that config anymore: a new container.
      var third = await config().run(dockerCommander);
      expect(third.isReused, isFalse);
      expect(third.name, isNot(equals(first.name)));
    });

    test('getContainerIDByName matches the exact name', () async {
      var prefix = 'docker_commander_test-${dockerCommander.session}';

      var c7 = await dockerCommander.run('alpine',
          containerName: '$prefix-7',
          imageArgs: ['sh', '-c', 'echo started; sleep 30']);
      var c70 = await dockerCommander.run('alpine',
          containerName: '$prefix-70',
          imageArgs: ['sh', '-c', 'echo started; sleep 30']);

      var host = dockerCommander.dockerHost;
      expect(await host.getContainerIDByName('$prefix-7'), equals(c7!.id));
      expect(await host.getContainerIDByName('$prefix-70'), equals(c70!.id));
      expect(await host.getContainerIDByName('$prefix-700'), isNull);
      expect(c7.id, hasLength(64));

      await c7.stop(timeout: Duration(seconds: 1));
      await c70.stop(timeout: Duration(seconds: 1));
    });
  }, skip: !dockerRunning);
}
