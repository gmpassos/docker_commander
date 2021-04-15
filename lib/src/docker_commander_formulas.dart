import 'dart:async';

import 'package:apollovm/apollovm.dart';
import 'package:docker_commander/docker_commander.dart';
import 'package:docker_commander/src/formulas/apache_formula.dart';
import 'package:docker_commander/src/formulas/gitlab_formula.dart';
import 'package:swiss_knife/swiss_knife.dart';

/// A `docker_commander` Formula:
class DockerCommanderFormula {
  /// The formula source.
  DockerCommanderFormulaSource source;

  DockerCommanderFormula(this.source);

  String get language => source.language;

  DockerCommanderConsole? _dockerCommanderConsole;

  /// Setups this formula to be used.
  ///
  /// A [dockerCommander] or [dockerCommanderConsole] parameter should be provided.
  void setup(
      {DockerCommander? dockerCommander,
      DockerCommanderConsole? dockerCommanderConsole}) {
    if (dockerCommanderConsole == null) {
      if (dockerCommander == null) {
        throw ArgumentError(
            "A 'dockerCommander' or 'dockerCommanderConsole' parameter should be provided!");
      }

      dockerCommanderConsole = dockerCommanderConsole =
          DockerCommanderConsole(dockerCommander, (name, description) async {
        return '';
      }, (line, output) async {
        print(output ? '>> $line' : line);
      });
    }

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
      var vm = await source.createVM();
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
  Future<ASTValue?> run(String command, List parameters,
      {Map<String, dynamic>? fields}) async {
    var vm = (await getVM())!;

    var runner = _createRunner(vm);

    var className = await getFormulaClassName();

    if (className.isEmpty) {
      throw StateError("A formula needs a class ending with 'Formula'.");
    }

    var classInstanceFields = _toClassInstanceFields(fields);

    FutureOr<ASTValue>? result;

    if ((await runner.getClassMethod('', className, command, parameters)) !=
        null) {
      result = runner.executeClassMethod('', className, command,
          positionalParameters: parameters,
          classInstanceFields: classInstanceFields);
    } else if ((await runner.getClassMethod('', className, command)) != null) {
      result = runner.executeClassMethod('', className, command,
          classInstanceFields: classInstanceFields);
    }

    if (result == null) return null;

    var resultValue = await result;
    return resultValue;
  }

  Map<String, ASTValue>? _toClassInstanceFields(Map<String, dynamic>? fields) {
    if (fields == null || fields.isEmpty) return null;
    var map =
        fields.map((key, value) => MapEntry(key, ASTValue.fromValue(value)));
    return map;
  }

  Future<List<String>> getFunctions() async {
    var vm = (await getVM())!;

    var runner = _createRunner(vm);

    var className = await getFormulaClassName();

    if (className.isEmpty) {
      throw StateError(
          "A formula needs a class with name ending in 'Formula'.");
    }

    var clazz = await runner.getClass('', className);
    if (clazz == null) {
      throw StateError("Can't find class: $className");
    }

    return clazz.functionsNames;
  }

  Future<Map<String, Object>> getFields() async {
    var vm = (await getVM())!;

    var runner = _createRunner(vm);

    var className = await getFormulaClassName();

    if (className.isEmpty) {
      throw StateError(
          "A formula needs a class with name ending in 'Formula'.");
    }

    var clazz = await runner.getClass('', className);
    if (clazz == null) {
      throw StateError("Can't find class: $className");
    }

    var fields = await clazz.getFieldsMap(fieldOverwrite: _fieldOverwrite);
    return fields;
  }

  final Map<String, ASTValue> _fieldOverwrite = {};

  void overwriteField(String fieldName, dynamic value) {
    var astValue = ASTValue.fromValue(value);
    _fieldOverwrite[fieldName] = astValue;
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

  /// Restarts this formula, calling `stop()` than `start()`.
  Future<bool> restart() async {
    await stop();
    return start();
  }

  bool Function(String cmdLine, ConsoleCMD cmd)? overwriteFunctionCMD;

  /// When a formula calls `cmd('start container-x')`
  /// it will be mapped to this function.
  Future<bool> _mapped_dockerCommander_cmd(String cmdLine) async {
    var cmd = ConsoleCMD.parse(cmdLine);
    if (cmd == null) {
      throw StateError("Can't parse command: $cmdLine");
    }

    if (overwriteFunctionCMD != null) {
      return overwriteFunctionCMD!(cmdLine, cmd);
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

  /// Executes a formula function.
  Future<dynamic> exec(String functionName,
      [List? arguments, Map<String, dynamic>? fields]) async {
    arguments ??= [];
    var result = await run(functionName, arguments, fields: fields);

    if (result == null) return null;

    var v = await result.getValueNoContext();
    return v;
  }
}

/// The source of a formula
class DockerCommanderFormulaSource {
  /// The programming language of the formula,
  /// to be parsed by [ApolloVM].
  String language;

  /// Source code of the formula.
  String source;

  DockerCommanderFormulaSource(this.language, this.source);

  /// Creates an [ApolloVM] loaded with this source.
  Future<ApolloVM> createVM() async {
    var vm = ApolloVM();

    var codeUnit = CodeUnit(language, source, 'docker_commander_formula');
    var loaded = await vm.loadCodeUnit(codeUnit);

    if (!loaded) {
      throw StateError("Can't load source in VM");
    }

    return vm;
  }

  String? _name;

  /// The name of this formula.
  ///
  /// This will load an [ApolloVM] and parse the formula source,
  /// than cache the formula name.
  Future<String> getName() async {
    if (_name == null) {
      var formula = toFormula();
      var name = await formula.getFormulaName();
      _name = name;
    }
    return _name!;
  }

  DockerCommanderFormula toFormula() => DockerCommanderFormula(this);
}

abstract class DockerCommanderFormulaRepository {
  DockerCommanderFormulaRepository? parent;

  DockerCommanderFormulaRepository([this.parent]);

  FutureOr<List<DockerCommanderFormulaSource>> listFormulasSources();

  Map<String, DockerCommanderFormulaSource>? _formulasSourcesTable;

  Future<Map<String, DockerCommanderFormulaSource>>
      getFormulasSourcesTable() async {
    if (_formulasSourcesTable == null) {
      var sources = await listFormulasSources();

      var entries = await Future.wait(
          sources.map((e) async => MapEntry(await e.getName(), e)));
      var map = Map<String, DockerCommanderFormulaSource>.fromEntries(entries);

      _formulasSourcesTable = map;
    }
    return Map<String, DockerCommanderFormulaSource>.from(
        _formulasSourcesTable!);
  }

  List<String>? _formulasNames;

  FutureOr<List<String>> listFormulasNames() async {
    if (_formulasNames == null) {
      var formulasSources = await listFormulasSources();

      var names = formulasSources.map((e) async {
        var name = await e.getName();
        return name;
      }).toList();

      _formulasNames = await Future.wait(names);
    }
    return _formulasNames!.toList();
  }

  Future<DockerCommanderFormulaSource?> getFormulaSource(
      String formulaName) async {
    var table = await getFormulasSourcesTable();
    return table[formulaName];
  }
}

class DockerCommanderFormulaRepositoryStandard
    extends DockerCommanderFormulaRepository {
  List<DockerCommanderFormulaSource>? _formulasSources;

  @override
  List<DockerCommanderFormulaSource> listFormulasSources() {
    _formulasSources ??= <DockerCommanderFormulaSource>[
      ApacheFormulaSource(),
      GitLabFormulaSource(),
    ];
    return _formulasSources!.toList();
  }
}
