@Timeout(Duration(minutes: 2))
@TestOn('vm')
import 'package:apollovm/apollovm.dart';
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _log = Logger('docker_commander/test');

void main() {
  configureLogger();

  group('DockerCommanderFormular', () {
    late DockerCommander dockerCommander;
    late DockerCommanderConsole dockerCommanderConsole;
    late DockerCommanderFormulaRepositoryStandard formulaRepositoryStandard;
    late List<String> nonTestContainersNames;

    void removeNonTestContainersNames(List<String>? names) {
      if (names == null) return;
      names.removeWhere((e) => nonTestContainersNames.contains(e));
    }

    String createContainerName(String prefix) {
      if (!nonTestContainersNames.contains(prefix)) {
        return prefix;
      }

      for (var i = 1; i <= 1000; ++i) {
        var name = '${prefix}_$i';

        if (!nonTestContainersNames.contains(name)) {
          return name;
        }
      }

      throw StateError(
          "Can't create container name> prefix: $prefix ; nonTestContainersNames: $nonTestContainersNames");
    }

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

      dockerCommanderConsole =
          DockerCommanderConsole(dockerCommander, (name, description) async {
        return '';
      }, (line, output) async {
        _log.info(output ? '>> $line' : line);
      });

      formulaRepositoryStandard = DockerCommanderFormulaRepositoryStandard();

      nonTestContainersNames =
          (await dockerCommander.psContainerNames()) ?? <String>[];

      _log.info('setUp> nonTestContainersNames: $nonTestContainersNames');

      logTitle(_log, 'TEST');
    });

    tearDown(() async {
      logTitle(_log, 'TEARDOWN');

      _log.info('tearDown>\tDockerCommander: $dockerCommander');
      _log.info('tearDown>\tDockerCommander.close()');
      await dockerCommander.close();
      _log.info('tearDown>\tDockerCommander: $dockerCommander');
    });

    test('DockerCommanderFormulaRepositoryStandard: listFormulasNames',
        () async {
      var formulasNames = await formulaRepositoryStandard.listFormulasNames();
      _log.info('formulasNames: $formulasNames');
      expect(formulasNames, equals(['apache', 'gitlab']));
    });

    test('Apache Formula', () async {
      var formulaSource =
          await formulaRepositoryStandard.getFormulaSource('apache');

      var formula = formulaSource!.toFormula();

      formula.setup(dockerCommanderConsole: dockerCommanderConsole);

      var containerName = createContainerName('dc_test_apache');

      var psContainerNames0 = await dockerCommander.psContainerNames();
      removeNonTestContainersNames(psContainerNames0);
      _log.info('containerNames0: $psContainerNames0');
      expect(psContainerNames0, isEmpty);

      formula.overwriteField('name', containerName);

      var formulaFields = await formula.getFields();
      expect(formulaFields,
          equals({'name': containerName, 'hostname': 'apache', 'port': 80}));

      var installed = await formula.install();
      expect(installed, isTrue);

      var psContainerNames1 = await dockerCommander.psContainerNames();
      removeNonTestContainersNames(psContainerNames1);
      _log.info('containerNames1: $psContainerNames1');
      expect(psContainerNames1, contains(containerName));

      var name = await formula.getFormulaName();
      expect(name, equals('apache'));

      var version = await formula.getFormulaVersion();
      expect(version, equals('1.1'));

      var className = await formula.getFormulaClassName();
      expect(className, equals('ApacheFormula'));

      var functions = await formula.getFunctions();
      functions.sort();
      expect(functions,
          equals(['getVersion', 'install', 'start', 'stop', 'uninstall']));

      var uninstalled = await formula.uninstall();
      expect(uninstalled, isTrue);

      var psContainerNames2 = await dockerCommander.psContainerNames();
      removeNonTestContainersNames(psContainerNames2);
      _log.info('containerNames2: $psContainerNames2');
      expect(psContainerNames2, isEmpty);
    });

    test('GitLab Formula', () async {
      var formulaSource =
          await formulaRepositoryStandard.getFormulaSource('gitlab');

      var formula = formulaSource!.toFormula();

      var cmdLog = <String>[];
      formula.overwriteFunctionCMD = (cmdLine, cmd) {
        cmdLog.add(cmdLine);
        return true;
      };

      formula.setup(dockerCommanderConsole: dockerCommanderConsole);

      var psContainerNames0 = await dockerCommander.psContainerNames();
      removeNonTestContainersNames(psContainerNames0);
      _log.info('containerNames0: $psContainerNames0');
      expect(psContainerNames0, isEmpty);

      var name = await formula.getFormulaName();
      expect(name, equals('gitlab'));

      var version = await formula.getFormulaVersion();
      expect(version, equals('1.0'));

      var className = await formula.getFormulaClassName();
      expect(className, equals('GitLabFormula'));

      var functions = await formula.getFunctions();
      functions.sort();

      expect(
          functions,
          equals([
            'getVersion',
            'install',
            'installRunner',
            'pull',
            'pullRunner',
            'registerRunner',
            'start',
            'startRunner',
            'stop',
            'stopRunner',
            'uninstall',
            'uninstallRunner',
          ]));

      var fields = await formula.getFields();

      _log.info('fields: $fields');

      var fieldsSorted = sortMapEntriesByKey<String, Object>(fields);

      expect(
          fieldsSorted,
          equals(sortMapEntriesByKey<String, String>({
            'hostGitlabConfigPath': '/srv/gitlab-runner/config',
            'imageGitlab': 'gitlab/gitlab-ce',
            'imageGitlabRunner': 'gitlab/gitlab-runner',
            'imageRunner': 'google/dart',
            'network': 'gitlab-net',
          })));

      formula.overwriteField('hostGitlabConfigPath', '/tmp/gitlab-config');

      var fields2 = await formula.getFields();
      _log.info('fields2: $fields2');

      expect(fields2['hostGitlabConfigPath'], equals('/tmp/gitlab-config'));

      expect(cmdLog, isEmpty);

      cmdLog.clear();
      var regRet =
          await formula.run('registerRunner', ['10.0.0.1', 'TOKEN_XYZ']);
      expect(regRet, equals(ASTValueVoid.instance));

      for (var cmdLine in cmdLog) {
        _log.info('FORMULA CMD> $cmdLine');
      }

      expect(cmdLog[0], contains('http://10.0.0.1/'));
      expect(cmdLog[0], contains('--registration-token TOKEN_XYZ'));
      expect(cmdLog[0], contains('--net gitlab-net'));
    });
  });
}
