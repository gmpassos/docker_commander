import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_host.dart';

/// Base class for pre-configured containers.
class DockerContainerConfig<D extends DockerContainer> {
  final String image;
  final String? version;
  final List<String>? imageArgs;
  final String? name;
  final String? network;
  final String? hostname;
  final List<String>? ports;
  final List<int>? hostPorts;
  final List<int>? containerPorts;
  final Map<String, String>? environment;
  final Map<String, String>? volumes;
  final bool? cleanContainer;
  final int? outputLimit;
  final bool outputAsLines;
  final OutputReadyFunction? stdoutReadyFunction;
  final OutputReadyFunction? stderrReadyFunction;

  DockerContainerConfig(
    this.image, {
    this.version,
    this.imageArgs,
    this.name,
    this.network,
    this.hostname,
    this.ports,
    this.hostPorts,
    this.containerPorts,
    this.environment,
    this.volumes,
    this.cleanContainer,
    this.outputLimit,
    this.outputAsLines = true,
    this.stdoutReadyFunction,
    this.stderrReadyFunction,
  });

  DockerContainerConfig copy({
    String? image,
    String? version,
    List<String>? imageArgs,
    String? name,
    String? network,
    String? hostname,
    List<String>? ports,
    List<int>? hostPorts,
    List<int>? containerPorts,
    Map<String, String>? environment,
    Map<String, String>? volumes,
    bool? cleanContainer,
    int? outputLimit,
    bool? outputAsLines,
    OutputReadyFunction? stdoutReadyFunction,
    OutputReadyFunction? stderrReadyFunction,
  }) {
    return DockerContainerConfig<D>(
      image ?? this.image,
      version: version ?? this.version,
      imageArgs: imageArgs ?? this.imageArgs,
      name: name ?? this.name,
      network: network ?? this.network,
      hostname: hostname ?? this.hostname,
      ports: ports ?? this.ports,
      hostPorts: hostPorts ?? this.hostPorts,
      containerPorts: containerPorts ?? this.containerPorts,
      environment: environment ?? this.environment,
      volumes: volumes ?? this.volumes,
      cleanContainer: cleanContainer ?? this.cleanContainer,
      outputLimit: outputLimit ?? this.outputLimit,
      outputAsLines: outputAsLines ?? this.outputAsLines,
      stdoutReadyFunction: stdoutReadyFunction ?? this.stdoutReadyFunction,
      stderrReadyFunction: stderrReadyFunction ?? this.stderrReadyFunction,
    );
  }

  Future<D> run(DockerCommander dockerCommander,
      {String? name,
      String? network,
      String? hostname,
      List<int>? hostPorts,
      bool cleanContainer = true,
      int? outputLimit}) {
    var mappedPorts = ports?.toList();

    hostPorts ??= this.hostPorts;

    if (hostPorts != null &&
        containerPorts != null &&
        hostPorts.isNotEmpty &&
        containerPorts!.isNotEmpty) {
      mappedPorts ??= <String>[];

      var portsLength = Math.min(hostPorts.length, containerPorts!.length);

      for (var i = 0; i < portsLength; ++i) {
        var p1 = hostPorts[i];
        var p2 = containerPorts![i];
        mappedPorts.add('$p1:$p2');
      }

      mappedPorts = mappedPorts.toSet().toList();
    }

    var dockerContainer = dockerCommander.run(
      image,
      version: version,
      imageArgs: imageArgs,
      containerName: name ?? this.name,
      ports: mappedPorts,
      network: network ?? this.network,
      hostname: hostname ?? this.hostname,
      environment: environment,
      volumes: volumes,
      cleanContainer: cleanContainer,
      outputAsLines: outputAsLines,
      outputLimit: outputLimit ?? this.outputLimit,
      stdoutReadyFunction: stdoutReadyFunction,
      stderrReadyFunction: stderrReadyFunction,
      dockerContainerInstantiator: instantiateDockerContainer,
    );

    return dockerContainer.then((value) async {
      var d = value as D;
      await initializeContainer(d);
      return d;
    });
  }

  D? instantiateDockerContainer(DockerRunner runner) => null;

  Future<bool> initializeContainer(D dockerContainer) async => false;
}

/// PostgreSQL pre-configured container.
class PostgreSQLContainerConfig
    extends DockerContainerConfig<PostgreSQLContainer> {
  String pgUser;

  String pgPassword;

  String pgDatabase;

  PostgreSQLContainerConfig(
      {this.pgUser = 'postgres',
      this.pgPassword = 'postgres',
      this.pgDatabase = 'postgres',
      int? hostPort})
      : super(
          'postgres',
          version: 'latest',
          hostPorts: hostPort != null ? [hostPort] : null,
          containerPorts: [5432],
          environment: {
            'POSTGRES_USER': pgUser,
            'POSTGRES_PASSWORD': pgPassword,
            'POSTGRES_DB': pgDatabase,
          },
          outputAsLines: true,
          stdoutReadyFunction: (output, line) =>
              line.contains('database system is ready to accept connections'),
        ) {
    if (pgUser.trim().isEmpty) {
      throw ArgumentError('Invalid pgUser: $pgUser');
    }

    if (pgDatabase.trim().isEmpty) {
      throw ArgumentError('Invalid pgDatabase: $pgDatabase');
    }

    if (pgPassword.isEmpty) {
      throw ArgumentError('Invalid pgPassword: $pgUser');
    }
  }

  @override
  PostgreSQLContainer? instantiateDockerContainer(DockerRunner runner) =>
      PostgreSQLContainer(this, runner);
}

class PostgreSQLContainer extends DockerContainer {
  final PostgreSQLContainerConfig config;

  PostgreSQLContainer(this.config, DockerRunner runner) : super(runner);

  /// Runs a SQL. Note that [sqlInline] should be a inline [String], without line-breaks (`\n`).
  ///
  /// Calls [psqlCMD].
  Future<String?> runSQL(String sqlInline) => _psqlSQL(sqlInline);

  Future<String?> _psqlSQL(String sql) {
    sql = _normalizeSQL(sql);
    return psqlCMD(sql);
  }

  /// Runs a psql command. Note that [cmdInline] should be a inline [String], without line-breaks (`\n`).
  ///
  /// Calls [execShell] executing `psql` inside the container.
  Future<String?> psqlCMD(String cmdInline) => _psqlCMD(cmdInline);

  Future<String?> _psqlCMD(String cmd) async {
    var cmdQuoted = !cmd.contains('"') ? '"$cmd"' : "'$cmd'";

    if (!cmd.contains('"')) {
      cmdQuoted = '"$cmd"';
    } else if (!cmd.contains("'")) {
      cmdQuoted = "'$cmd'";
    } else {
      var cmd2 = cmd.replaceAll('"', '\\"');
      cmdQuoted = '"$cmd2"';
    }

    var script = '''#!/bin/bash
export PGPASSWORD="${config.pgPassword}";
psql -U ${config.pgUser} -d ${config.pgDatabase} -c $cmdQuoted
''';

    var process = await execShell(script);
    if (process == null) return null;

    var stdout = await process.waitStdout(desiredExitCode: 0);
    if (stdout == null) return null;

    return stdout.asString;
  }

  String _normalizeSQL(String sql) =>
      sql.trim().replaceAll(RegExp(r'(?:[ \t]*\n+[ \t]*)+'), ' ');
}

/// Apache HTTPD pre-configured container.
class ApacheHttpdContainerConfig
    extends DockerContainerConfig<DockerContainer> {
  ApacheHttpdContainerConfig({int? hostPort})
      : super(
          'httpd',
          version: 'latest',
          hostPorts: hostPort != null ? [hostPort] : null,
          containerPorts: [80],
          outputAsLines: true,
          stderrReadyFunction: (output, line) =>
              line.contains('Apache') && line.contains('configured'),
        );
}
