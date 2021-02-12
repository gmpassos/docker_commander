@Timeout(Duration(minutes: 2))
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
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

      await dockerContainer.waitReady();

      var output = dockerContainer.stdout.asString;
      expect(
          output, contains('database system is ready to accept connections'));

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info(output);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id.isNotEmpty, isTrue);

      var execPsql = await dockerContainer.exec('/usr/bin/psql',
          ' -d postgres -U postgres -c \\l '.trim().split(RegExp(r'\s+')));

      var execPsqlExitCode = await execPsql.waitExit();

      _LOG.info(
          '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< PSQL[exitCode: $execPsqlExitCode]:');
      _LOG.info(execPsql.stdout.asString);
      _LOG.info('-------------------------------');
      _LOG.info(execPsql.stderr.asString);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(execPsqlExitCode, equals(0));
      expect(execPsql.stdout.asString, contains('List of databases'));
      expect(execPsql.stderr.asString.isEmpty, isTrue);

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

      await dockerContainer.waitReady();

      var output = dockerContainer.stderr.asString;
      expect(output, contains('Apache'));

      _LOG.info('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      _LOG.info(output);
      _LOG.info('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

      expect(dockerContainer.id.isNotEmpty, isTrue);

      var aptGetUpdateOutput = await dockerContainer
          .execAndWaitStdout('/usr/bin/apt-get', ['update']);
      _LOG.info(aptGetUpdateOutput);
      expect(aptGetUpdateOutput.exitCode, equals(0));

      expect(
          await dockerContainer
              .execAndWaitExit('/usr/bin/apt-get', ['install', 'curl']),
          equals(0));

      var curlBinPath = await dockerContainer.execWhich('curl');
      _LOG.info('curl: $curlBinPath');
      expect(curlBinPath, contains('curl'));

      var getLocalhost = await dockerContainer
          .execAndWaitStdoutAsString(curlBinPath, ['http://localhost/']);
      _LOG.info('getLocalhost:\n$getLocalhost');
      expect(getLocalhost, contains('<html>'));

      var httpdConf =
          await dockerContainer.execCat('/usr/local/apache2/conf/httpd.conf');
      _LOG.info('httpdConf> size: ${httpdConf.length}');
      expect(httpdConf.contains(RegExp(r'Listen\s+80')), isTrue);

      _LOG.info('Stopping Apache Httpd...');
      await dockerContainer.stop(timeout: Duration(seconds: 5));

      _LOG.info('Wait exit...');
      var exitCode = await dockerContainer.waitExit();
      _LOG.info('exitCode: $exitCode');

      expect(exitCode == 0 || exitCode == 137, isTrue);
    });
  });
}
