import 'dart:async';

import 'package:apollovm/apollovm.dart';
import 'package:docker_commander/docker_commander.dart';
import 'package:swiss_knife/swiss_knife.dart';

/// A `docker_commander` Formula:
class DockerCommanderFormular {
  /// The programming language of the formula,
  /// to be parsed by [ApolloVM].
  String language;

  /// Source of the formula.
  String source;

  DockerCommanderFormular(this.language, this.source);

  DockerCommanderConsole? _dockerCommanderConsole;

  void setup(DockerCommanderConsole dockerCommanderConsole) {
    _dockerCommanderConsole = dockerCommanderConsole;
  }

  String? _formulaName;

  /// Returns the formula name, calling `getName`.
  Future<String> getFormulaName() async {
    if (_formulaName == null) {
      var astValue = await run('getName', []);

      if (astValue != null) {
        var name = parseString(await astValue.getValueNoContext(), '')!.trim();
        if (name.isNotEmpty) {
          _formulaName = name;
          return name;
        }
      }

      var className = await getFormulaClassName();
      var name =
          className.toLowerCase().trim().replaceFirst(RegExp(r'formula$'), '');

      _formulaName = name;
      return name;
    }
    return _formulaName!;
  }

  String? _formulaVersion;

  /// Returns the formula version, calling `getVersion`.
  Future<String> getFormulaVersion() async {
    if (_formulaVersion == null) {
      var astValue = await run('getVersion', []);

      if (astValue != null) {
        var ver = parseString(await astValue.getValueNoContext(), '')!.trim();
        if (ver.isNotEmpty) {
          _formulaVersion = ver;
          return ver;
        }
      }

      _formulaVersion = '0';
      return '0';
    }
    return _formulaVersion!;
  }

  ApolloVM? _vm;

  /// Returns a [ApolloVM] loaded with the formula code.
  Future<ApolloVM?> getVM() async {
    if (_vm == null) {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(language, source, 'docker_commander_formula');
      var loaded = await vm.loadCodeUnit(codeUnit);

      if (!loaded) {
        throw StateError("Can't load source in VM");
      }

      _vm = vm;
      return vm;
    } else {
      return _vm!;
    }
  }

  String? _formulaClassName;

  /// Returns the formula class name.
  Future<String> getFormulaClassName() async {
    if (_formulaClassName == null) {
      var vm = (await getVM())!;
      var classesNames = vm.getLanguageNamespaces(language).classesNames;
      var className = classesNames.firstWhere(
          (e) => e.toLowerCase().contains('formula'),
          orElse: () => '');
      _formulaClassName = className;
    }
    return _formulaClassName!;
  }

  /// Runs a formula [command] with [parameters].
  Future<ASTValue?> run(String command, List parameters) async {
    var vm = (await getVM())!;

    var runner = _createRunner(vm);

    var className = await getFormulaClassName();

    FutureOr<ASTValue>? result;

    if (className.isNotEmpty) {
      if ((await runner.getClassMethod('', className, command, [parameters])) !=
          null) {
        result =
            runner.executeClassMethod('', className, command, [parameters]);
      } else if ((await runner.getClassMethod('', className, command)) !=
          null) {
        result = runner.executeClassMethod('', className, command);
      }
    } else {
      if ((await runner.getFunction('', command, [parameters])) != null) {
        result = runner.executeFunction('', command, [parameters]);
      } else if ((await runner.getFunction('', command)) != null) {
        result = runner.executeFunction('', command);
      }
    }

    if (result == null) return null;

    var resultValue = await result;
    return resultValue;
  }

  ApolloLanguageRunner _createRunner(ApolloVM vm) {
    var runner = vm.createRunner(language);
    if (runner == null) {
      throw StateError("Can't create ApolloVM runner for language: $language");
    }

    runner.externalFunctionMapper!.mapExternalFunction1(
        ASTTypeVoid.INSTANCE,
        'cmd',
        ASTTypeString.INSTANCE,
        'cmd',
        (String cmd) => _mapped_dockerCommander_cmd(cmd));

    return runner;
  }

  /// Install this formula, calling `install()`.
  Future<bool> install([List parameters = const []]) async {
    var result = await run('install', parameters);
    return result != null;
  }

  /// Uninstall this formula, calling `uninstall()`.
  Future<bool> uninstall([List parameters = const []]) async {
    var result = await run('uninstall', parameters);
    return result != null;
  }

  /// Starts this formula, calling `start()`.
  Future<bool> start() async {
    var result = await run('start', []);
    return result != null;
  }

  /// Stops this formula, calling `stop()`.
  Future<bool> stop() async {
    var result = await run('stop', []);
    return result != null;
  }

  /// When a formula calls `cmd('start container-x')`
  /// it will be mapped to this function.
  Future<bool> _mapped_dockerCommander_cmd(String cmdLine) async {
    var cmd = ConsoleCMD.parse(cmdLine);
    if (cmd == null) {
      throw StateError("Can't parse command: $cmdLine");
    }

    var dockerCommanderConsole = _dockerCommanderConsole!;

    dockerCommanderConsole.filterEnvironmentProperties
        .add(_filterEnvironmentProperties);

    var ok = await dockerCommanderConsole.executeConsoleCMD(cmd);

    var rm = dockerCommanderConsole.filterEnvironmentProperties
        .remove(_filterEnvironmentProperties);
    assert(rm);

    return ok;
  }

  /// Ensures that a container will have extra environment
  /// properties, like `DOCKER_COMMANDER_FORMULA_NAME`.
  Future<Map<String, String>?> _filterEnvironmentProperties(
      Map<String, String>? environmentProps) async {
    environmentProps ??= <String, String>{};

    var formulaName = await getFormulaName();

    environmentProps['DOCKER_COMMANDER_FORMULA_NAME'] = formulaName;

    return environmentProps;
  }
}
