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
    late DockerCommander dockerCommander;

    setUp(() async {
      logTitle(_LOG, 'SETUP');

      var dockerHost = DockerHostLocal();
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

      logTitle(_LOG, 'TEST');
    });

    tearDown(() async {
      logTitle(_LOG, 'TEARDOWN');

      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
      _LOG.info('tearDown>\tDockerCommander.close()');
      await dockerCommander.close();
      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
    });

    test('PostgreSQL', () async {
      var dockerContainer =
          await PostgreSQLContainer().run(dockerCommander, hostPorts: [4032]);

      _LOG.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      var output = dockerContainer.stdout!.asString;
      expect(
          output, contains('database system is ready to accept connections'));

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info(output);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id!.isNotEmpty, isTrue);

      var execPsql = await dockerContainer.exec('/usr/bin/psql',
          ' -d postgres -U postgres -c \\l '.trim().split(RegExp(r'\s+')));

      var execPsqlExitCode = await execPsql!.waitExit();

      _LOG.info(
          '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< PSQL[exitCode: $execPsqlExitCode]:');
      _LOG.info(execPsql.stdout!.asString);
      _LOG.info('-------------------------------');
      _LOG.info(execPsql.stderr!.asString);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(execPsqlExitCode, equals(0));
      expect(execPsql.stdout!.asString, contains('List of databases'));
      expect(execPsql.stderr!.asString.isEmpty, isTrue);

      _LOG.info('Stopping PostgreSQL...');
      await dockerContainer.stop(timeout: Duration(seconds: 5));

      _LOG.info('Wsit exit...');
      var exitCode = await dockerContainer.waitExit();
      _LOG.info('exitCode: $exitCode');

      expect(exitCode == 0 || exitCode == 137, isTrue);
    });

    test('Apache Httpd', () async {
      var dockerContainer =
          await ApacheHttpdContainer().run(dockerCommander, hostPorts: [4081]);

      _LOG.info(dockerContainer);

      expect(dockerContainer.instanceID > 0, isTrue);
      expect(dockerContainer.name.isNotEmpty, isTrue);

      var output = dockerContainer.stderr!.asString;
      expect(output, contains('Apache'));

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info(output);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id!.isNotEmpty, isTrue);

      var aptGetUpdateOutput = await dockerContainer
          .execAndWaitStdout('/usr/bin/apt-get', ['update']);
      _LOG.info(aptGetUpdateOutput);
      expect(aptGetUpdateOutput!.exitCode, equals(0));

      expect(
          await dockerContainer
              .execAndWaitExit('/usr/bin/apt-get', ['-y', 'install', 'curl']),
          equals(0));

      var curlBinPath = await dockerContainer.execWhich('curl');
      _LOG.info('curl: $curlBinPath');
      expect(curlBinPath, contains('curl'));

      var getLocalhost = await dockerContainer
          .execAndWaitStdoutAsString(curlBinPath!, ['http://localhost/']);
      _LOG.info('getLocalhost:\n$getLocalhost');
      expect(getLocalhost, contains('<html>'));

      var httpdConf =
          await dockerContainer.execCat('/usr/local/apache2/conf/httpd.conf');
      _LOG.info('httpdConf> size: ${httpdConf!.length}');
      expect(httpdConf.contains(RegExp(r'Listen\s+80')), isTrue);

      _LOG.info('Stopping Apache Httpd...');
      await dockerContainer.stop(timeout: Duration(seconds: 5));

      _LOG.info('Wait exit...');
      var exitCode = await dockerContainer.waitExit();
      _LOG.info('exitCode: $exitCode');

      expect(exitCode == 0 || exitCode == 137, isTrue);
    });

    test('NGINX', () async {
      var network = await dockerCommander.createNetwork();

      expect(network, isNotEmpty);

      var apacheContainer = await ApacheHttpdContainer().run(dockerCommander,
          hostPorts: [4081], network: network, hostname: 'apache');
      expect(await apacheContainer.waitReady(), isTrue);

      _LOG.info('Started Apache HTTPD... $apacheContainer');

      expect(apacheContainer.instanceID > 0, isTrue);
      expect(apacheContainer.name.isNotEmpty, isTrue);

      var apacheIP = await dockerCommander.getContainerIP(apacheContainer.name);
      _LOG.info('Apache HTTPD IP:  $apacheIP');
      expect(apacheIP, isNotEmpty);

      var nginxConfig = NginxReverseProxyConfigurer(
          [NginxServerConfig('localhost', 'apache', 80, false)]).build();

      var nginxContainer = await NginxContainer(nginxConfig, hostPorts: [4082])
          .run(dockerCommander, network: network, hostname: 'nginx');

      _LOG.info(nginxContainer);

      expect(nginxContainer.instanceID > 0, isTrue);
      expect(nginxContainer.name.isNotEmpty, isTrue);

      var match = await nginxContainer.stdout!
          .waitForDataMatch('nginx', timeout: Duration(seconds: 10));

      _LOG.info('Data match: $match');

      var output = nginxContainer.stdout!.asString;

      _LOG.info(output);

      expect(output, contains('nginx'));

      expect(nginxContainer.id!.isNotEmpty, isTrue);

      var configFileContent =
          await nginxContainer.execCat(nginxContainer.configPath);

      _LOG.info('------------------------------------------------------------');
      _LOG.info(configFileContent);
      _LOG.info('------------------------------------------------------------');

      expect(configFileContent, contains('apache'));

      var testOK = await nginxContainer.testConfiguration();

      _LOG.info('Nginx test config: $testOK');
      expect(testOK, isTrue);

      var reloadOK = await nginxContainer.reloadConfiguration();
      _LOG.info('Nginx reload: $reloadOK');
      expect(reloadOK, isTrue);

      var apacheContent =
          (await HttpClient('http://localhost:4081/').get('')).bodyAsString;
      expect(apacheContent, contains('<html>'));

      _LOG.info(
          '------------------------------------------------------------ apacheContent:');
      _LOG.info(apacheContent);
      _LOG.info('------------------------------------------------------------');

      var nginxContent =
          (await HttpClient('http://localhost:4082/').get('')).bodyAsString;
      expect(nginxContent, contains('<html>'));

      _LOG.info(
          '------------------------------------------------------------ nginxContent:');
      _LOG.info(nginxContent);
      _LOG.info('------------------------------------------------------------');

      expect(nginxContent, equals(apacheContent));

      var apacheLogs = await apacheContainer.catLogs(
          waitDataMatcher: 'GET /', waitDataTimeout: Duration(seconds: 1));

      _LOG.info(
          '------------------------------------------------------------ Apache logs:');
      _LOG.info(apacheLogs);
      expect(apacheLogs, contains('GET /'));
      _LOG.info('------------------------------------------------------------');

      _LOG.info('Stopping Nginx...');
      await nginxContainer.stop(timeout: Duration(seconds: 5));

      _LOG.info('Wait exit...');
      var exitCode = await nginxContainer.waitExit();
      _LOG.info('exitCode: $exitCode');
      expect(exitCode == 0 || exitCode == 137, isTrue);

      _LOG.info('Stopping Apache HTTPD...');
      await apacheContainer.stop(timeout: Duration(seconds: 5));

      await dockerCommander.removeNetwork(network);
    });
  });
}
