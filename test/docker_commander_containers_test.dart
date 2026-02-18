@Timeout(Duration(minutes: 2))
@TestOn('vm')
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _log = Logger('docker_commander/test');

Future<void> main() async {
  configureLogger();

  var dockerRunning = await DockerHost.isDaemonRunning(DockerHostLocal());

  group('DockerContainerConfig', () {
    late DockerCommander dockerCommander;

    setUp(() async {
      logTitle(_log, 'SETUP');

      var dockerHost = DockerHostLocal();
      dockerCommander = DockerCommander(dockerHost);
      _log.info('setUp>\tDockerCommander: $dockerCommander');

      _log.info('setUp>\tDockerCommander.initialize()');
      await dockerCommander.initialize();
      expect(dockerCommander.isSuccessfullyInitialized, isTrue);
      _log.info('setUp>\tDockerCommander: $dockerCommander');

      _log.info('setUp>\tDockerCommander.checkDaemon()');
      await dockerCommander.checkDaemon();
      _log.info('setUp>\tDockerCommander: $dockerCommander');

      expect(dockerCommander.lastDaemonCheck, isNotNull);
      _log.info('setUp>\tDockerCommander.lastDaemonCheck: $dockerCommander');

      logTitle(_log, 'TEST');
    });

    tearDown(() async {
      logTitle(_log, 'TEARDOWN');

      _log.info('tearDown>\tDockerCommander: $dockerCommander');
      _log.info('tearDown>\tDockerCommander.close()');
      await dockerCommander.close();
      _log.info('tearDown>\tDockerCommander: $dockerCommander');
    });

    test('PostgreSQL', () async {
      var freeListenPort =
          await getFreeListenPort(startPort: 4032, endPort: 4132);

      var dockerContainer =
          await PostgreSQLContainerConfig(hostPort: freeListenPort)
              .run(dockerCommander);

      _log.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      var output = dockerContainer.stdout!.asString;
      expect(
          output, contains('database system is ready to accept connections'));

      _log.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _log.info(output);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id!.isNotEmpty, isTrue);

      var execPsql = await dockerContainer.exec('/usr/bin/psql',
          ' -d postgres -U postgres -c \\l '.trim().split(RegExp(r'\s+')));

      var execPsqlExitCode = await execPsql!.waitExit();

      _log.info(
          '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< PSQL[exitCode: $execPsqlExitCode]:');
      _log.info(execPsql.stdout!.asString);
      _log.info('-------------------------------');
      _log.info(execPsql.stderr!.asString);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(execPsqlExitCode, equals(0));
      expect(execPsql.stdout!.asString, contains('List of databases'));
      expect(execPsql.stderr!.asString.isEmpty, isTrue);

      {
        var sqlCreateAddress = '''
        CREATE TABLE IF NOT EXISTS "address" (
          "id" serial,
          "state" text,
          "city" text,
          "street" text,
          "number" integer,
          PRIMARY KEY( id )
        )
      ''';

        var runSQL = await dockerContainer.runSQL(sqlCreateAddress);
        expect(runSQL, contains('CREATE TABLE'));

        var psqlCMD = await dockerContainer.psqlCMD('\\d');
        expect(psqlCMD, contains(RegExp(r'\Waddress\W')));
      }

      _log.info('Stopping PostgreSQL...');
      await dockerContainer.stop(timeout: Duration(seconds: 5));

      _log.info('Wsit exit...');
      var exitCode = await dockerContainer.waitExit();
      _log.info('exitCode: $exitCode');

      expect(exitCode == 0 || exitCode == 137, isTrue);
    });

    testMySQL({bool forceNativePasswordAuthentication = false}) async {
      var freeListenPort =
          await getFreeListenPort(startPort: 3106, endPort: 3206);

      var config = MySQLContainerConfig(
          hostPort: freeListenPort,
          forceNativePasswordAuthentication: forceNativePasswordAuthentication);
      var dockerContainer = await config.run(dockerCommander);

      _log.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      var output = dockerContainer.stdout!.asString;
      expect(output, contains('Database files initialized'));

      _log.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _log.info(output);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id!.isNotEmpty, isTrue);

      var execMySql = await dockerContainer.exec('/usr/bin/mysql', [
        '-D',
        config.dbName,
        '--password=${config.dbPassword}',
        '-e',
        'SELECT TABLE_NAME FROM information_schema.tables'
      ]);

      var execMysqlExitCode = await execMySql!.waitExit();

      _log.info(
          '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< MYSQL[exitCode: $execMysqlExitCode]:');
      _log.info(execMySql.stdout!.asString);
      _log.info('-------------------------------');
      _log.info(execMySql.stderr!.asString);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(execMysqlExitCode, equals(0));
      expect(execMySql.stdout!.asString, contains('TABLE_NAME'));

      {
        var sqlCreateAddress = '''
        CREATE TABLE IF NOT EXISTS `address` (
          `id` serial,
          `state` text,
          `city` text,
          `street` text,
          `number` integer,
          PRIMARY KEY( `id` )
        )
        ''';

        var runSQL = await dockerContainer.runSQL(sqlCreateAddress);
        expect(runSQL, anyOf(isNull, isEmpty));

        var cmd = await dockerContainer.mysqlCMD('SHOW TABLES');
        expect(cmd, contains(RegExp(r'\Waddress\W')));
      }

      _log.info('Stopping MySQL...');
      await dockerContainer.stop(timeout: Duration(seconds: 5));

      _log.info('Wsit exit...');
      var exitCode = await dockerContainer.waitExit();
      _log.info('exitCode: $exitCode');

      expect(exitCode == 0, isTrue);
    }

    test('MySQL', () async => testMySQL());

    test('MySQL (forceNativePasswordAuthentication)',
        () async => testMySQL(forceNativePasswordAuthentication: true));

    test('Apache Httpd', () async {
      var freeListenPort =
          await getFreeListenPort(startPort: 4081, endPort: 4181);

      var dockerContainer =
          await ApacheHttpdContainerConfig(hostPort: freeListenPort)
              .run(dockerCommander);

      _log.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      var output = dockerContainer.stderr!.asString;
      expect(output, contains('Apache'));

      _log.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _log.info(output);
      _log.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id!.isNotEmpty, isTrue);

      var aptGetUpdateOutput = await dockerContainer
          .execAndWaitStdout('/usr/bin/apt-get', ['update']);
      _log.info(aptGetUpdateOutput);
      expect(aptGetUpdateOutput!.exitCode, equals(0));

      expect(
          await dockerContainer
              .execAndWaitExit('/usr/bin/apt-get', ['-y', 'install', 'curl']),
          equals(0));

      var curlBinPath = await dockerContainer.execWhich('curl');
      _log.info('curl: $curlBinPath');
      expect(curlBinPath, contains('curl'));

      var getLocalhost = await dockerContainer
          .execAndWaitStdoutAsString(curlBinPath!, ['http://localhost/']);
      _log.info('getLocalhost:\n$getLocalhost');
      expect(getLocalhost, contains('<html>'));

      var httpdConf =
          await dockerContainer.execCat('/usr/local/apache2/conf/httpd.conf');
      _log.info('httpdConf> size: ${httpdConf!.length}');
      expect(httpdConf.contains(RegExp(r'Listen\s+80')), isTrue);

      _log.info('Stopping Apache Httpd...');
      await dockerContainer.stop(timeout: Duration(seconds: 5));

      _log.info('Wait exit...');
      var exitCode = await dockerContainer.waitExit();
      _log.info('exitCode: $exitCode');

      expect(exitCode == 0 || exitCode == 137, isTrue);
    });

    test('NGINX', () async {
      var apachePort = await getFreeListenPort(startPort: 4071, endPort: 4171);

      var network = await dockerCommander.createNetwork();

      expect(network, isNotEmpty);

      var apacheContainer =
          await ApacheHttpdContainerConfig(hostPort: apachePort)
              .run(dockerCommander, network: network, hostname: 'apache');
      expect(await apacheContainer.waitReady(), isTrue);

      _log.info('Started Apache HTTPD... $apacheContainer');

      expect(apacheContainer.instanceID > 0, isTrue);
      expect(apacheContainer.name.isNotEmpty, isTrue);

      var apacheIP = await dockerCommander.getContainerIP(apacheContainer.name);
      _log.info('Apache HTTPD IP:  $apacheIP');
      expect(apacheIP, isNotEmpty);

      var nginxConfig = NginxReverseProxyConfigurer(
          [NginxServerConfig('localhost', 'apache', 80, false)]).build();

      var nginxPort = await getFreeListenPort(startPort: 4091, endPort: 4191);

      var nginxContainer =
          await NginxContainerConfig(nginxConfig, hostPort: nginxPort)
              .run(dockerCommander, network: network, hostname: 'nginx');

      _log.info(nginxContainer);

      expect(nginxContainer.instanceID > 0, isTrue);
      expect(nginxContainer.name.isNotEmpty, isTrue);

      var match = await nginxContainer.stdout!
          .waitForDataMatch('nginx', timeout: Duration(seconds: 10));

      _log.info('Data match: $match');

      var output = nginxContainer.stdout!.asString;

      _log.info(output);

      expect(output, contains('nginx'));

      expect(nginxContainer.id!.isNotEmpty, isTrue);

      var configFileContent =
          await nginxContainer.execCat(nginxContainer.configPath);

      _log.info('------------------------------------------------------------');
      _log.info(configFileContent);
      _log.info('------------------------------------------------------------');

      expect(configFileContent, contains('apache'));

      var testOK = await nginxContainer.testConfiguration();

      _log.info('Nginx test config: $testOK');
      expect(testOK, isTrue);

      //// Can't reload, since after the initial reload
      //// the file "/var/run/nginx.pid" is empty!
      // var reloadOK = await nginxContainer.reloadConfiguration();
      // _log.info('Nginx reload: $reloadOK');
      // expect(reloadOK, isTrue);

      var apacheContent =
          (await HttpClient('http://localhost:$apachePort/').get(''))
              .bodyAsString;
      expect(apacheContent, contains('<html>'));

      _log.info(
          '------------------------------------------------------------ apacheContent:');
      _log.info(apacheContent);
      _log.info('------------------------------------------------------------');

      var nginxContent =
          (await HttpClient('http://localhost:$nginxPort/').get(''))
              .bodyAsString;
      expect(nginxContent, contains('<html>'));

      _log.info(
          '------------------------------------------------------------ nginxContent:');
      _log.info(nginxContent);
      _log.info('------------------------------------------------------------');

      expect(nginxContent, equals(apacheContent));

      var apacheLogs = await apacheContainer.catLogs(
          waitDataMatcher: 'GET /', waitDataTimeout: Duration(seconds: 1));

      _log.info(
          '------------------------------------------------------------ Apache logs:');
      _log.info(apacheLogs);
      expect(apacheLogs, contains('GET /'));
      _log.info('------------------------------------------------------------');

      _log.info('Stopping Nginx...');
      await nginxContainer.stop(timeout: Duration(seconds: 5));

      _log.info('Wait exit...');
      var exitCode = await nginxContainer.waitExit();
      _log.info('exitCode: $exitCode');
      expect(exitCode == 0 || exitCode == 137, isTrue);

      _log.info('Stopping Apache HTTPD...');
      await apacheContainer.stop(timeout: Duration(seconds: 5));

      await dockerCommander.removeNetwork(network);
    });
  }, skip: !dockerRunning);
}
