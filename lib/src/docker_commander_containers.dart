import 'package:swiss_knife/swiss_knife.dart';
import 'package:version/version.dart';

import 'docker_commander_base.dart';
import 'docker_commander_commands.dart';
import 'docker_commander_host.dart';
import 'docker_commander_run_options.dart';

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

  /// Further run options (tmpfs, labels, health check, resources...),
  /// merged over the other fields.
  final DockerRunOptions? options;

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
    this.options,
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
    DockerRunOptions? options,
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
      options: options ?? this.options,
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
      options: options,
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
  /// The `tmpfs` mount holding the data directory of an [ephemeral]
  /// container.
  static const String ephemeralDataMount = '/var/lib/postgresql/ephemeral';

  /// The runtime settings of an [ephemeral] container: no waiting on disk
  /// writes.
  static const Map<String, String> ephemeralSettings = {
    'fsync': 'off',
    'synchronous_commit': 'off',
    'full_page_writes': 'off',
  };

  /// Postgres DB username.
  String pgUser;

  /// Postgres DB password.
  String pgPassword;

  /// Postgres DB name.
  String pgDatabase;

  /// Runtime Postgres configuration: `-c port=$postgresPort`
  int? postgresPort;

  /// Runtime Postgres configuration: `-c max_connections=$maxConnections`
  int? maxConnections;

  /// Runtime Postgres configuration: `-c log_statement=$logStatement`
  String? logStatement;

  /// Further runtime settings, each passed as `-c key=value`.
  final Map<String, String>? settings;

  /// Arguments to `initdb`, through `POSTGRES_INITDB_ARGS`.
  final String? initdbArgs;

  /// A throwaway database, for tests: durability off
  /// ([ephemeralSettings]), `initdb --no-sync`, and the data directory in
  /// memory ([ephemeralDataMount]). Its data is lost when the container
  /// stops.
  final bool ephemeral;

  /// - [hostPort]: `0` publishes on a free host port chosen by Docker
  ///   (see [DockerContainer.hostPortFor]).
  /// - [extraEnvironment]: more environment variables, which can override
  ///   the ones set by this config.
  PostgreSQLContainerConfig(
      {super.version = 'latest',
      this.pgUser = 'postgres',
      this.pgPassword = 'postgres',
      this.pgDatabase = 'postgres',
      this.postgresPort,
      this.maxConnections,
      this.logStatement,
      this.settings,
      this.initdbArgs,
      Map<String, String>? extraEnvironment,
      this.ephemeral = false,
      int? hostPort,
      DockerRunOptions? options})
      : super(
          'postgres',
          imageArgs: _buildImageArgs(
              postgresPort, maxConnections, logStatement, settings, ephemeral),
          hostPorts: hostPort != null ? [hostPort] : null,
          containerPorts: [5432],
          environment: {
            'POSTGRES_USER': pgUser,
            'POSTGRES_PASSWORD': pgPassword,
            'POSTGRES_DB': pgDatabase,
            ..._buildInitEnvironment(initdbArgs, ephemeral),
            ...?extraEnvironment,
          },
          options: ephemeral
              ? DockerRunOptions(tmpfs: {ephemeralDataMount: ''}).merge(options)
              : options,
          outputAsLines: true,
          // `pg_ctl` sends the output of the temporary server used by the
          // first-time setup to STDOUT; the real server logs to STDERR.
          stdoutReadyFunction: (output, data) {
            var lines = data is List ? data : [data];

            var readyForConnections = lines.any((l) =>
                l.contains('database system is ready to accept connections'));
            if (!readyForConnections) return false;

            var allLines = output.dataAsListOfStrings;

            var initComplete = allLines.indexWhere(
                (l) => l.contains('PostgreSQL init process complete;'));
            if (initComplete < 0) return false;

            var afterComplete = allLines.sublist(initComplete);

            readyForConnections = afterComplete.any((l) =>
                l.contains('database system is ready to accept connections'));

            return readyForConnections;
          },
          stderrReadyFunction: (output, data) {
            var lines = data is List ? data : [data];

            var readyForConnections = lines.any((l) =>
                l.contains('database system is ready to accept connections'));
            return readyForConnections;
          },
        ) {
    if (pgUser.trim().isEmpty) {
      throw ArgumentError('Invalid pgUser: $pgUser');
    }

    if (pgDatabase.trim().isEmpty) {
      throw ArgumentError('Invalid pgDatabase: $pgDatabase');
    }

    if (pgPassword.isEmpty) {
      throw ArgumentError('Invalid pgPassword: empty');
    }
  }

  static List<String>? _buildImageArgs(int? postgresPort, int? maxConnections,
      String? logStatement, Map<String, String>? settings, bool ephemeral) {
    var allSettings = <String, String>{
      if (ephemeral) ...ephemeralSettings,
      if (postgresPort != null) 'port': '$postgresPort',
      if (maxConnections != null) 'max_connections': '$maxConnections',
      if (logStatement != null) 'log_statement': logStatement,
      ...?settings,
    };

    if (allSettings.isEmpty) return null;

    return [
      for (var e in allSettings.entries) ...['-c', '${e.key}=${e.value}'],
    ];
  }

  static Map<String, String> _buildInitEnvironment(
      String? initdbArgs, bool ephemeral) {
    var args = [
      if (isNotEmptyString(initdbArgs, trim: true)) initdbArgs!.trim(),
      if (ephemeral) '--no-sync',
    ].join(' ');

    return {
      if (args.isNotEmpty) 'POSTGRES_INITDB_ARGS': args,
      // A sub-directory: `initdb` needs an empty directory it can own.
      if (ephemeral) 'PGDATA': '$ephemeralDataMount/pgdata',
    };
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

  /// Runs a SQL script of any size, with line-breaks and quotes.
  ///
  /// Copies [sql] into the container and runs it with `psql -f`, stopping
  /// at the first error. Returns the `psql` output, or `null` on error.
  Future<String?> runSQLScript(String sql) async {
    var path =
        '/tmp/docker_commander-${DateTime.now().microsecondsSinceEpoch}.sql';

    if (!await _putScript(path, sql)) return null;

    try {
      var process = await exec('env', [
        'PGPASSWORD=${config.pgPassword}',
        'psql',
        '-v',
        'ON_ERROR_STOP=1',
        '-U',
        config.pgUser,
        '-d',
        config.pgDatabase,
        '-f',
        path,
      ]);
      if (process == null) return null;

      var stdout = await process.waitStdout(desiredExitCode: 0);
      return stdout?.asString;
    } finally {
      await execAndWaitExit('rm', ['-f', path]);
    }
  }

  /// The largest piece of a script (in UTF-16 code units) written with one
  /// [putFileContent]: it travels base64-encoded in a single command-line
  /// argument, which Linux limits to 128 KiB. 24 Ki code units are at most
  /// 72 KiB of UTF-8, 96 KiB in base64.
  static const int scriptChunkSize = 24 * 1024;

  /// Writes [content] to [path] inside this container: with `docker cp`
  /// from a host temporary file, or, on a host without temporary files
  /// (like a remote one), in [scriptChunkSize] pieces.
  Future<bool> _putScript(String path, String content) async {
    var copied = await DockerCMD.copyFileContentToContainer(
        runner.dockerHost, name, content, false, path);
    if (copied) return true;

    var offset = 0;
    do {
      var end = Math.min(offset + scriptChunkSize, content.length);
      // Don't split a surrogate pair:
      if (end < content.length &&
          (content.codeUnitAt(end - 1) & 0xFC00) == 0xD800) {
        --end;
      }

      var ok = await putFileContent(path, content.substring(offset, end),
          append: offset > 0);
      if (!ok) return false;

      offset = end;
    } while (offset < content.length);

    return true;
  }

  Future<String?> _psqlSQL(String sql) {
    sql = _normalizeSQL(sql);
    return psqlCMD(sql);
  }

  /// Runs a psql command. Note that [cmdInline] should be a inline [String], without line-breaks (`\n`).
  ///
  /// Calls [execShell] executing `psql` inside the container.
  Future<String?> psqlCMD(String cmdInline) => _psqlCMD(cmdInline);

  Future<String?> _psqlCMD(String cmd) async {
    cmd = cmd.replaceAll(r'`', r'\`');

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

/// MySQL pre-configured container.
class MySQLContainerConfig extends DockerContainerConfig<MySQLContainer> {
  /// The data directory, on a `tmpfs` mount for an [ephemeral] container.
  static const String dataDirectory = '/var/lib/mysql';

  /// The server settings of an [ephemeral] container: no waiting on disk
  /// writes, and no binary log.
  static const Map<String, String> ephemeralSettings = {
    'innodb-flush-log-at-trx-commit': '0',
    'sync-binlog': '0',
    'innodb-doublewrite': 'OFF',
    'skip-log-bin': '',
  };

  /// MySQL DB username.
  String dbUser;

  /// MySQL DB password.
  String dbPassword;

  /// MySQL DB name.
  String dbName;

  /// Further server settings, each passed as `--key=value`
  /// (or `--key` for an empty value).
  final Map<String, String>? settings;

  /// A throwaway database, for tests: durability off
  /// ([ephemeralSettings]) and the data directory in memory. Its data is
  /// lost when the container stops.
  final bool ephemeral;

  /// - [hostPort]: `0` publishes on a free host port chosen by Docker
  ///   (see [DockerContainer.hostPortFor]).
  /// - [extraEnvironment]: more environment variables, which can override
  ///   the ones set by this config.
  MySQLContainerConfig({
    super.version = 'latest',
    this.dbUser = 'myuser',
    this.dbPassword = 'mypass',
    this.dbName = 'mydb',
    int? hostPort,
    bool forceNativePasswordAuthentication = false,
    List<String>? daemonArguments,
    this.settings,
    Map<String, String>? extraEnvironment,
    this.ephemeral = false,
    DockerRunOptions? options,
  }) : super(
          'mysql',
          hostPorts: hostPort != null ? [hostPort] : null,
          containerPorts: [3306],
          imageArgs: _buildImageArgs(version, forceNativePasswordAuthentication,
              daemonArguments, settings, ephemeral),
          environment: {
            'MYSQL_USER': dbUser,
            'MYSQL_PASSWORD': dbPassword,
            'MYSQL_ROOT_PASSWORD': dbPassword,
            'MYSQL_DATABASE': dbName,
            ...?extraEnvironment,
          },
          options: ephemeral
              ? DockerRunOptions(tmpfs: {dataDirectory: ''}).merge(options)
              : options,
          outputAsLines: true,
          stdoutReadyFunction: (output, line) => false,
          stderrReadyFunction: (output, data) {
            var lines = data is List ? data : [data];
            return lines.any((l) =>
                l.contains('mysqld: ready for connections') &&
                !l.contains('port: 0'));
          },
        ) {
    if (dbUser.trim().isEmpty) {
      throw ArgumentError('Invalid dbUser: $dbUser');
    }

    if (dbName.trim().isEmpty) {
      throw ArgumentError('Invalid dbName: $dbName');
    }

    if (dbPassword.isEmpty) {
      throw ArgumentError('Invalid dbPassword: $dbPassword');
    }
  }

  static List<String>? _buildImageArgs(
      String? version,
      bool forceNativePasswordAuthentication,
      List<String>? daemonArguments,
      Map<String, String>? settings,
      bool ephemeral) {
    var args = <String>[];

    var allSettings = <String, String>{
      if (ephemeral) ...ephemeralSettings,
      ...?settings,
    };

    for (var e in allSettings.entries) {
      args.add(e.value.isEmpty ? '--${e.key}' : '--${e.key}=${e.value}');
    }

    if (forceNativePasswordAuthentication) {
      if (_isVersionGreaterThan_9_0_0(version)) {
        // Not supported: ignore
      } else if (_isVersionGreaterThan_8_4_0(version)) {
        args.add('--mysql-native-password=ON');
      } else {
        args.add('--default-authentication-plugin=mysql_native_password');
      }
    }

    if (daemonArguments != null) {
      args.addAll(daemonArguments);
    }

    return args.isNotEmpty ? args : null;
  }

  static bool _isVersionGreaterThan_9_0_0(String? version) {
    version = version?.trim();

    if (version == null ||
        version.isEmpty ||
        version.toLowerCase() == 'latest') {
      return true;
    }

    try {
      var ver = Version.parse(version);
      return ver >= Version(9, 0, 0);
    } catch (_) {
      return false;
    }
  }

  static bool _isVersionGreaterThan_8_4_0(String? version) {
    version = version?.trim();

    if (version == null ||
        version.isEmpty ||
        version.toLowerCase() == 'latest') {
      return true;
    }

    try {
      var ver = Version.parse(version);
      return ver >= Version(8, 4, 0);
    } catch (_) {
      return false;
    }
  }

  @override
  MySQLContainer? instantiateDockerContainer(DockerRunner runner) =>
      MySQLContainer(this, runner);

  @override
  Future<bool> initializeContainer(MySQLContainer dockerContainer) async {
    var cmd =
        " GRANT ALL PRIVILEGES ON `$dbName`.* TO '$dbUser'@'%' WITH GRANT OPTION ;"
        " GRANT ALL ON *.* TO '$dbUser'@'%' WITH GRANT OPTION ;"
        " FLUSH PRIVILEGES ;";

    await dockerContainer.mysqlCMD(cmd);

    return true;
  }
}

class MySQLContainer extends DockerContainer {
  final MySQLContainerConfig config;

  MySQLContainer(this.config, DockerRunner runner) : super(runner);

  /// Runs a SQL. Note that [sqlInline] should be a inline [String], without line-breaks (`\n`).
  ///
  /// Calls [mysqlCMD].
  Future<String?> runSQL(String sqlInline) => _mysqlSQL(sqlInline);

  Future<String?> _mysqlSQL(String sql) {
    sql = _normalizeSQL(sql);
    return mysqlCMD(sql);
  }

  /// Runs a mysql command. Note that [cmdInline] should be a inline [String], without line-breaks (`\n`).
  ///
  /// Calls [execShell] executing `mysql` client inside the container.
  Future<String?> mysqlCMD(String cmdInline) => _mysqlCMD(cmdInline);

  Future<String?> _mysqlCMD(String cmd) async {
    cmd = cmd.replaceAll(r'`', r'\`');

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
/usr/bin/mysql -D ${config.dbName} --password=${config.dbPassword} -e $cmdQuoted
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
  ApacheHttpdContainerConfig({super.version = 'latest', int? hostPort})
      : super(
          'httpd',
          hostPorts: hostPort != null ? [hostPort] : null,
          containerPorts: [80],
          outputAsLines: true,
          stderrReadyFunction: (output, data) {
            var lines = data is List ? data : [data];
            var ready = lines
                .any((l) => l.contains('Apache') && l.contains('configured'));
            return ready;
          },
        );
}
