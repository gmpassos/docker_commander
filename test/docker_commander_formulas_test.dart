@Timeout(Duration(minutes: 2))
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

final _LOG = Logger('docker_commander/test');

void main() {
  configureLogger();

  group('DockerCommanderFormular', () {
    late DockerCommander dockerCommander;
    late DockerCommanderConsole dockerCommanderConsole;
    late DockerCommanderFormulaRepositoryStandard formulaRepositoryStandard;

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

      dockerCommanderConsole =
          DockerCommanderConsole(dockerCommander, (name, description) async {
        return '';
      }, (line, output) async {
        print(output ? '>> $line' : line);
      });

      formulaRepositoryStandard = DockerCommanderFormulaRepositoryStandard();
    });

    tearDown(() async {
      logTitle(_LOG, 'TEARDOWN');

      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
      _LOG.info('tearDown>\tDockerCommander.close()');
      await dockerCommander.close();
      _LOG.info('tearDown>\tDockerCommander: $dockerCommander');
    });

    test('Apache Formula', () async {
      var formulasNames = await formulaRepositoryStandard.listFormulasNames();
      expect(formulasNames, equals(['apache']));

      var formulaSource =
          await formulaRepositoryStandard.getFormulaSource('apache');

      var formula = formulaSource!.toFormula();

      formula.setup(dockerCommanderConsole: dockerCommanderConsole);

      var psContainerNames0 = await dockerCommander.psContainerNames();
      _LOG.info('containerNames0: $psContainerNames0');
      expect(psContainerNames0, isEmpty);

      var installed = await formula.install();
      expect(installed, isTrue);

      var psContainerNames1 = await dockerCommander.psContainerNames();
      _LOG.info('containerNames1: $psContainerNames1');
      expect(psContainerNames1, contains('apache'));

      var name = await formula.getFormulaName();
      expect(name, equals('apache'));

      var version = await formula.getFormulaVersion();
      expect(version, equals('1.0'));

      var className = await formula.getFormulaClassName();
      expect(className, equals('ApacheFormula'));

      var functions = await formula.getFunctions();
      functions.sort();
      expect(functions,
          equals(['getVersion', 'install', 'start', 'stop', 'uninstall']));

      var uninstalled = await formula.uninstall();
      expect(uninstalled, isTrue);

      var psContainerNames2 = await dockerCommander.psContainerNames();
      _LOG.info('containerNames2: $psContainerNames2');
      expect(psContainerNames2, isEmpty);
    });
  });
}
