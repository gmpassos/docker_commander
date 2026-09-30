@Tags(['no_docker'])
@TestOn('vm')
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

void main() {
  configureLogger();

  group('DockerRunOptions', () {
    test('empty', () {
      var options = DockerRunOptions();
      expect(options.isEmpty, isTrue);
      expect(options.toArgs(), isEmpty);
      expect(options.toJson(), isEmpty);
    });

    test('toArgs: every option', () {
      var options = DockerRunOptions(
        cleanContainer: true,
        restart: 'always',
        ports: ['8080:80', '5432', '0:6379', '127.0.0.1:9000:9000'],
        network: ' net1 ',
        hostname: 'host1',
        volumes: {'/host/data': '/data'},
        environment: {'A': '1'},
        healthCmd: 'pg_isready',
        healthInterval: Duration(seconds: 1),
        healthRetries: 3,
        healthStartPeriod: Duration(milliseconds: 1500),
        healthTimeout: Duration(seconds: 2),
        tmpfs: {'/tmp/a': '', '/tmp/b': 'rw,size=64m'},
        shmSize: '256m',
        memory: '512m',
        cpus: '1.5',
        ulimits: {'nofile': '1024:2048'},
        user: 'postgres',
        workdir: '/work',
        entrypoint: '/bin/sh',
        init: true,
        stopSignal: 'SIGINT',
        stopTimeout: Duration(seconds: 5),
        platform: 'linux/amd64',
        pull: DockerPullPolicy.missing,
        labels: {'owner': 'tests', 'flag': ''},
        addHosts: {'db': '10.0.0.2'},
        extraArgs: ['--read-only'],
      );

      expect(
          options.toArgs(),
          equals([
            '--rm',
            '--restart', 'always', //
            '-p', '8080:80',
            '-p', '5432:5432',
            '-p', '6379', // host port 0: chosen by Docker
            '-p', '127.0.0.1:9000:9000',
            '--net', 'net1',
            '-h', 'host1',
            '-v', '/host/data:/data',
            '-e', 'A=1',
            '--health-cmd', 'pg_isready',
            '--health-interval', '1000ms',
            '--health-retries', '3',
            '--health-start-period', '1500ms',
            '--health-timeout', '2000ms',
            '--tmpfs', '/tmp/a',
            '--tmpfs', '/tmp/b:rw,size=64m',
            '--shm-size', '256m',
            '--memory', '512m',
            '--cpus', '1.5',
            '--ulimit', 'nofile=1024:2048',
            '--user', 'postgres',
            '--workdir', '/work',
            '--entrypoint', '/bin/sh',
            '--init',
            '--stop-signal', 'SIGINT',
            '--stop-timeout', '5',
            '--platform', 'linux/amd64',
            '--pull', 'missing',
            '--label', 'owner=tests',
            '--label', 'flag',
            '--add-host', 'db:10.0.0.2',
            '--read-only',
          ]));

      expect(options.hasEphemeralPorts, isTrue);
      expect(DockerRunOptions(ports: ['80:80']).hasEphemeralPorts, isFalse);
    });

    test('JSON round trip', () {
      var options = DockerRunOptions(
        ports: ['0:5432'],
        environment: {'A': '1'},
        cleanContainer: false,
        healthInterval: Duration(milliseconds: 1500),
        tmpfs: {'/data': 'size=64m'},
        stopTimeout: Duration(seconds: 3),
        pull: DockerPullPolicy.always,
        labels: {'a': 'b'},
        extraArgs: ['--read-only'],
        reuse: true,
      );

      var json = options.toJson();
      expect(json['healthInterval'], equals(1500));
      expect(json['pull'], equals('always'));

      var decoded = DockerRunOptions.fromJson(json);
      expect(decoded.toJson(), equals(json));
      expect(decoded.toArgs(), equals(options.toArgs()));
      expect(decoded.reuse, isTrue);
    });

    test('fromJson: string values (console)', () {
      var options = DockerRunOptions.fromJson({
        'ports': '80:80, 0:5432',
        'tmpfs': '/data=rw,size=64m|/tmp',
        'labels': 'a=1;b=x=y',
        'init': 'true',
        'stopTimeout': '2000',
        'extraArgs': '--read-only  --privileged',
        'pull': 'NEVER',
      });

      expect(options.ports, equals(['80:80', '0:5432']));
      expect(options.tmpfs, equals({'/data': 'rw,size=64m', '/tmp': ''}));
      expect(options.labels, equals({'a': '1', 'b': 'x=y'}));
      expect(options.init, isTrue);
      expect(options.stopTimeout, equals(Duration(seconds: 2)));
      expect(options.extraArgs, equals(['--read-only', '--privileged']));
      expect(options.pull, equals(DockerPullPolicy.never));

      expect(() => DockerRunOptions.fromJson({'pull': 'sometimes'}),
          throwsArgumentError);
    });

    test('fromProperties', () {
      var options = DockerRunOptions.fromProperties({
        'shm-size': '128m',
        'stop-signal': 'SIGINT',
        'add-hosts': 'db=10.0.0.2',
        'reuse': 'true',
        'unknown': 'ignored',
        'memory': '  ',
      });

      expect(
          options.toJson(),
          equals({
            'shmSize': '128m',
            'stopSignal': 'SIGINT',
            'addHosts': {'db': '10.0.0.2'},
            'reuse': true,
          }));
    });

    test('merge', () {
      var a = DockerRunOptions(
        ports: ['80:80'],
        environment: {'A': '1', 'B': '1'},
        cleanContainer: true,
        user: 'a',
        extraArgs: ['--x'],
      );
      var b = DockerRunOptions(
        ports: ['80:80', '443:443'],
        environment: {'B': '2'},
        user: 'b',
        extraArgs: ['--y'],
      );

      var merged = a.merge(b);
      expect(merged.ports, equals(['80:80', '443:443']));
      expect(merged.environment, equals({'A': '1', 'B': '2'}));
      expect(merged.cleanContainer, isTrue);
      expect(merged.user, equals('b'));
      expect(merged.extraArgs, equals(['--x', '--y']));

      expect(identical(a.merge(null), a), isTrue);
    });

    test('normalizePorts', () {
      expect(DockerRunOptions.normalizePorts(null), isNull);
      expect(DockerRunOptions.normalizePorts([' ', '']), isNull);
      expect(DockerRunOptions.normalizePorts(['80', '80:80', '8080:80']),
          equals(['80:80', '8080:80']));
      expect(DockerRunOptions.normalizePorts(['127.0.0.1:80:80']),
          equals(['127.0.0.1:80:80']));
    });

    test('toArgs: blank values are skipped', () {
      var options = DockerRunOptions(
        cleanContainer: false,
        restart: '  ',
        network: ' ',
        hostname: '',
        user: ' ',
        healthCmd: '',
        volumes: {'/host': '', '': '/data'},
        environment: {'': 'x', 'EMPTY': ''},
        tmpfs: {' ': 'size=1m'},
        labels: {' ': 'x', ' owner ': 'tests'},
        addHosts: {'db': '', '': '10.0.0.1'},
        init: false,
      );

      expect(
          options.toArgs(),
          equals([
            '-e', 'EMPTY=', //
            '--label', 'owner=tests',
          ]));
      expect(options.networkName, isNull);
      expect(options.hostName, isNull);
    });

    test('toArgs: stop timeout in whole seconds', () {
      expect(
          DockerRunOptions(stopTimeout: Duration(milliseconds: 2500)).toArgs(),
          equals(['--stop-timeout', '2']));
    });

    test('fromJson: non-string values', () {
      var options = DockerRunOptions.fromJson({
        'environment': {'PORT': 5432, 'EMPTY': null},
        'healthRetries': '3',
        'ports': [8080, '0:5432'],
      });

      expect(options.environment, equals({'PORT': '5432', 'EMPTY': ''}));
      expect(options.healthRetries, equals(3));
      expect(options.ports, equals(['8080', '0:5432']));
      expect(DockerRunOptions.fromJson({}).isEmpty, isTrue);
    });

    test('applyPortMappings', () {
      var mappings = {5432: 49153, 80: 8080};

      expect(
          DockerRunOptions.applyPortMappings(
              ['0:5432', '9000:9000', '0:6379'], mappings),
          equals(['49153:5432', '9000:9000', '0:6379']));

      // No ports (a reused container): all its published ports.
      expect(DockerRunOptions.applyPortMappings(null, mappings),
          equals(['49153:5432', '8080:80']));

      expect(DockerRunOptions.applyPortMappings(['0:5432'], {}),
          equals(['0:5432']));
    });

    test('parseInlineMap', () {
      expect(DockerRunOptions.parseInlineMap(null), isNull);
      expect(DockerRunOptions.parseInlineMap('  '), isNull);
      expect(DockerRunOptions.parseInlineMap('a=1| b = 2 ;c'),
          equals({'a': '1', 'b': '2', 'c': ''}));
    });
  });

  group('DockerHost', () {
    test('buildContainerArgs (legacy) now emits the health options', () {
      var host = DockerHostLocal();

      var infos = host.buildContainerArgs(
          'run',
          'postgres',
          '16',
          'pg1',
          ['5432'],
          null,
          null,
          {'A': '1'},
          null,
          true,
          'pg_isready',
          Duration(seconds: 1),
          null,
          null,
          null,
          'no');

      expect(
          infos.args,
          equals([
            'run',
            '--name', 'pg1', //
            '--rm',
            '--restart', 'no',
            '-p', '5432:5432',
            '-e', 'A=1',
            '--health-cmd', 'pg_isready',
            '--health-interval', '1000ms',
            'postgres:16',
          ]));
      expect(infos.image, equals('postgres:16'));
      expect(infos.ports, equals(['5432:5432']));
    });

    test('buildContainerArgsWithOptions', () {
      var host = DockerHostLocal();

      var options = host.defaultRunOptions
          .merge(DockerRunOptions(ports: ['0:5432'], network: 'n1'));

      var infos = host.buildContainerArgsWithOptions(
          'run', 'postgres', null, 'pg1', options);

      expect(
          infos.args,
          equals([
            'run',
            '--name', 'pg1', //
            '-p', '5432',
            '--net', 'n1',
            '--label', '${DockerRunOptions.labelSession}=${host.session}',
            'postgres',
          ]));
      expect(infos.ports, equals(['0:5432']));
      expect(infos.containerNetwork, equals('n1'));
    });

    test('resolveRunOptions: options win over the named parameters', () {
      var options = DockerHost.resolveRunOptions(
        ports: ['80:80'],
        environment: {'A': '1', 'B': '1'},
        cleanContainer: true,
        restart: 'no',
        healthCmd: 'true',
        options: DockerRunOptions(
          ports: ['443:443'],
          environment: {'B': '2'},
          cleanContainer: false,
          restart: 'always',
        ),
      );

      expect(options.ports, equals(['80:80', '443:443']));
      expect(options.environment, equals({'A': '1', 'B': '2'}));
      expect(options.cleanContainer, isFalse);
      expect(options.restart, equals('always'));
      expect(options.healthCmd, equals('true'));
    });

    test('defaultRunOptions: the session label, per host', () {
      var h1 = DockerHostLocal();
      var h2 = DockerHostLocal();

      expect(h1.defaultRunOptions.labels,
          equals({DockerRunOptions.labelSession: '${h1.session}'}));
      expect(h1.defaultRunOptions.labels,
          isNot(equals(h2.defaultRunOptions.labels)));
    });

    test('computeConfigHash ignores the session label', () {
      var options = DockerRunOptions(ports: ['0:5432'], labels: {'a': '1'});

      var hash = DockerHostLocal.computeConfigHash(
          'postgres', null, null, null, options);

      for (var host in [DockerHostLocal(), DockerHostLocal()]) {
        expect(
            DockerHostLocal.computeConfigHash('postgres', null, null, null,
                host.defaultRunOptions.merge(options)),
            equals(hash));
      }

      // Other labels count:
      expect(
          DockerHostLocal.computeConfigHash('postgres', null, null, null,
              options.merge(DockerRunOptions(labels: {'a': '2'}))),
          isNot(equals(hash)));

      // And so does the container name:
      expect(
          DockerHostLocal.computeConfigHash(
              'postgres', null, 'pg1', null, options),
          isNot(equals(hash)));
    });

    test('computeConfigHash', () {
      var options = DockerRunOptions(ports: ['0:5432']);

      var h1 = DockerHostLocal.computeConfigHash(
          'postgres', '16', null, ['-c', 'fsync=off'], options);
      var h2 = DockerHostLocal.computeConfigHash(
          'postgres', '16', null, ['-c', 'fsync=off'], options);
      var h3 = DockerHostLocal.computeConfigHash(
          'postgres', '17', null, ['-c', 'fsync=off'], options);
      var h4 = DockerHostLocal.computeConfigHash('postgres', '16', null,
          ['-c', 'fsync=off'], DockerRunOptions(ports: ['0:5433']));

      expect(h1, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(h1, equals(h2));
      expect(h1, isNot(equals(h3)));
      expect(h1, isNot(equals(h4)));
    });
  });

  group('DockerContainer', () {
    DockerContainer container(List<String> ports, {bool reused = false}) =>
        DockerContainer(_FakeRunner(ports, isReused: reused));

    test('hostPortFor', () {
      var c = container(['49153:5432', '127.0.0.1:8080:80', '0:6379']);

      expect(c.hostPortFor(5432), equals(49153));
      expect(c.hostPortFor(80), equals(8080)); // The IP is ignored.
      expect(c.hostPortFor(6379), isNull); // Not resolved yet.
      expect(c.hostPortFor(1234), isNull); // Not published.

      expect(c.hostPorts, equals([49153, 8080, 0]));
      expect(c.containerPorts, equals([5432, 80, 6379]));
    });

    test('isReused', () {
      expect(container([]).isReused, isFalse);
      expect(container([], reused: true).isReused, isTrue);
    });
  });

  group('DockerContainerConfig', () {
    test('copy keeps the options', () {
      var options = DockerRunOptions(labels: {'a': '1'});
      var config = DockerContainerConfig('alpine', options: options);

      expect(config.copy().options, same(options));

      var other = DockerRunOptions(user: 'x');
      expect(config.copy(options: other).options, same(other));
    });
  });

  group('PostgreSQLContainerConfig', () {
    test('defaults', () {
      var config = PostgreSQLContainerConfig();
      expect(config.imageArgs, isNull);
      expect(
          config.environment,
          equals({
            'POSTGRES_USER': 'postgres',
            'POSTGRES_PASSWORD': 'postgres',
            'POSTGRES_DB': 'postgres',
          }));
      expect(config.options, isNull);
    });

    test('settings', () {
      var config = PostgreSQLContainerConfig(
        postgresPort: 5433,
        maxConnections: 200,
        settings: {'shared_buffers': '256MB', 'max_connections': '300'},
        initdbArgs: '--locale=C',
        extraEnvironment: {'TZ': 'UTC'},
      );

      expect(
          config.imageArgs,
          equals([
            '-c', 'port=5433', //
            '-c', 'max_connections=300',
            '-c', 'shared_buffers=256MB',
          ]));
      expect(config.environment!['POSTGRES_INITDB_ARGS'], equals('--locale=C'));
      expect(config.environment!['TZ'], equals('UTC'));
      expect(config.environment!.containsKey('PGDATA'), isFalse);
    });

    test('ephemeral', () {
      var config = PostgreSQLContainerConfig(
        ephemeral: true,
        initdbArgs: '--locale=C',
        hostPort: 0,
        options: DockerRunOptions(labels: {'owner': 'tests'}),
      );

      expect(
          config.imageArgs,
          equals([
            '-c', 'fsync=off', //
            '-c', 'synchronous_commit=off',
            '-c', 'full_page_writes=off',
          ]));
      expect(config.environment!['POSTGRES_INITDB_ARGS'],
          equals('--locale=C --no-sync'));
      expect(config.environment!['PGDATA'],
          equals('${PostgreSQLContainerConfig.ephemeralDataMount}/pgdata'));
      expect(config.options!.tmpfs,
          equals({PostgreSQLContainerConfig.ephemeralDataMount: ''}));
      expect(config.options!.labels, equals({'owner': 'tests'}));
      expect(config.hostPorts, equals([0]));
    });

    test('invalid', () {
      expect(() => PostgreSQLContainerConfig(pgUser: ' '), throwsArgumentError);
      expect(
          () => PostgreSQLContainerConfig(pgPassword: ''),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', isNot(contains('postgres')))));
    });
  });

  group('MySQLContainerConfig', () {
    test('settings and ephemeral', () {
      var config = MySQLContainerConfig(
        version: '8.0.36',
        ephemeral: true,
        settings: {'max-connections': '500'},
        extraEnvironment: {'TZ': 'UTC'},
      );

      expect(
          config.imageArgs,
          equals([
            '--innodb-flush-log-at-trx-commit=0',
            '--sync-binlog=0',
            '--innodb-doublewrite=OFF',
            '--skip-log-bin',
            '--max-connections=500',
          ]));
      expect(config.environment!['TZ'], equals('UTC'));
      expect(config.options!.tmpfs,
          equals({MySQLContainerConfig.dataDirectory: ''}));
    });

    test('defaults', () {
      var config = MySQLContainerConfig(version: '8.0.36');
      expect(config.imageArgs, isNull);
      expect(config.options, isNull);
    });
  });
}

/// A [DockerRunner] with fixed [ports], for tests without Docker.
class _FakeRunner extends DockerRunner {
  final List<String> _ports;

  @override
  final bool isReused;

  _FakeRunner(this._ports, {this.isReused = false})
      : super(DockerHostLocal(), DockerProcess.incrementInstanceID(), 'fake');

  @override
  String? get id => 'fake-id';

  @override
  String? get image => 'fake:latest';

  @override
  List<String> get ports => _ports;

  @override
  bool get isRunning => true;

  @override
  int? get exitCode => null;

  @override
  DateTime? get exitTime => null;

  @override
  Future<int?> waitExit({int? desiredExitCode, Duration? timeout}) async =>
      null;
}
