import 'package:swiss_knife/swiss_knife.dart';

/// When `docker run` pulls the image (`--pull`).
enum DockerPullPolicy { always, missing, never }

/// The options of a `docker run` or `docker create` command.
///
/// This is the one place that turns container options into Docker CLI
/// arguments ([toArgs]) and into JSON ([toJson] and
/// [DockerRunOptions.fromJson]), so a local host, a remote host and the
/// console all accept the same options.
///
/// For anything not modelled here, use [extraArgs].
class DockerRunOptions {
  /// Label with the [DockerHost.session] that started a container.
  static const String labelSession = 'docker_commander.session';

  /// Label with the hash of the options of a reusable container.
  /// See [reuse].
  static const String labelConfigHash = 'docker_commander.config_hash';

  /// Mapped ports, as `hostPort:containerPort` (or `ip:hostPort:containerPort`).
  ///
  /// A host port of `0` publishes the container port on a free host port
  /// chosen by Docker. After the container starts, the chosen port is
  /// returned by `DockerContainer.hostPortFor`.
  final List<String>? ports;

  /// The network to connect the container to (`--net`).
  final String? network;

  /// The container hostname (`-h`).
  final String? hostname;

  /// Environment variables (`-e KEY=value`).
  final Map<String, String>? environment;

  /// Volumes, as host path (or volume name) → container path (`-v`).
  final Map<String, String>? volumes;

  /// Removes the container when it exits (`--rm`).
  final bool? cleanContainer;

  /// The restart policy (`--restart`): `no`, `on-failure[:max-retries]`,
  /// `always` or `unless-stopped`.
  ///
  /// Docker refuses a policy other than `no` together with `--rm`, so it
  /// requires [cleanContainer] `false` (see [validate]).
  final String? restart;

  /// The health check command (`--health-cmd`).
  final String? healthCmd;

  /// Time between health checks (`--health-interval`).
  final Duration? healthInterval;

  /// Consecutive failures to report unhealthy (`--health-retries`).
  final int? healthRetries;

  /// Start period before failures count (`--health-start-period`).
  final Duration? healthStartPeriod;

  /// Maximum time of one health check (`--health-timeout`).
  final Duration? healthTimeout;

  /// In-memory mounts, as container path → mount options (`--tmpfs`).
  /// An empty value uses Docker's default options.
  final Map<String, String>? tmpfs;

  /// Size of `/dev/shm` (`--shm-size`), e.g. `256m`.
  final String? shmSize;

  /// Memory limit (`--memory`), e.g. `512m`.
  final String? memory;

  /// Number of CPUs (`--cpus`), e.g. `1.5`.
  final String? cpus;

  /// Resource limits, as name → `soft[:hard]` (`--ulimit`).
  final Map<String, String>? ulimits;

  /// The user to run as (`--user`).
  final String? user;

  /// The working directory (`--workdir`).
  final String? workdir;

  /// Overrides the image entrypoint (`--entrypoint`).
  final String? entrypoint;

  /// Runs an init process as PID 1 (`--init`).
  final bool? init;

  /// The signal that stops the container (`--stop-signal`).
  final String? stopSignal;

  /// Time to wait before killing the container on stop (`--stop-timeout`).
  final Duration? stopTimeout;

  /// The image platform (`--platform`), e.g. `linux/amd64`.
  final String? platform;

  /// When to pull the image (`--pull`).
  final DockerPullPolicy? pull;

  /// Container labels (`--label`).
  final Map<String, String>? labels;

  /// Extra `/etc/hosts` entries, as hostname → IP (`--add-host`).
  final Map<String, String>? addHosts;

  /// Arguments passed as they are, before the image name.
  final List<String>? extraArgs;

  /// Reuses a running container started with the same image and options,
  /// instead of starting a new one. Not a Docker flag: the container is
  /// found by its [labelConfigHash] label.
  ///
  /// - Only for `run`: `createContainer` ignores it.
  /// - A reused container belongs to the session that started it, and
  ///   stopping any of its runners stops it for all of them.
  /// - Two runs starting at the same moment can both find none, and start
  ///   two containers.
  final bool? reuse;

  const DockerRunOptions({
    this.ports,
    this.network,
    this.hostname,
    this.environment,
    this.volumes,
    this.cleanContainer,
    this.restart,
    this.healthCmd,
    this.healthInterval,
    this.healthRetries,
    this.healthStartPeriod,
    this.healthTimeout,
    this.tmpfs,
    this.shmSize,
    this.memory,
    this.cpus,
    this.ulimits,
    this.user,
    this.workdir,
    this.entrypoint,
    this.init,
    this.stopSignal,
    this.stopTimeout,
    this.platform,
    this.pull,
    this.labels,
    this.addHosts,
    this.extraArgs,
    this.reuse,
  });

  /// Returns `true` if no option is set.
  bool get isEmpty => toJson().isEmpty;

  /// The [network] name, trimmed, or `null` if empty.
  String? get networkName => _trimOrNull(network);

  /// The [hostname], trimmed, or `null` if empty.
  String? get hostName => _trimOrNull(hostname);

  /// The [ports], normalized. See [normalizePorts].
  List<String>? get normalizedPorts => normalizePorts(ports);

  /// Returns `true` if a port has a host port of `0`. See [ports].
  bool get hasEphemeralPorts =>
      (normalizedPorts ?? []).any((p) => p.startsWith('0:'));

  /// Returns a copy with the options of [other] over these:
  /// - Values set in [other] replace these.
  /// - Maps are merged, [other] winning on the same key.
  /// - [ports] are merged, and [extraArgs] are appended.
  DockerRunOptions merge(DockerRunOptions? other) {
    if (other == null) return this;

    return DockerRunOptions(
      ports: _mergeLists(ports, other.ports, unique: true),
      network: other.network ?? network,
      hostname: other.hostname ?? hostname,
      environment: _mergeMaps(environment, other.environment),
      volumes: _mergeMaps(volumes, other.volumes),
      cleanContainer: other.cleanContainer ?? cleanContainer,
      restart: other.restart ?? restart,
      healthCmd: other.healthCmd ?? healthCmd,
      healthInterval: other.healthInterval ?? healthInterval,
      healthRetries: other.healthRetries ?? healthRetries,
      healthStartPeriod: other.healthStartPeriod ?? healthStartPeriod,
      healthTimeout: other.healthTimeout ?? healthTimeout,
      tmpfs: _mergeMaps(tmpfs, other.tmpfs),
      shmSize: other.shmSize ?? shmSize,
      memory: other.memory ?? memory,
      cpus: other.cpus ?? cpus,
      ulimits: _mergeMaps(ulimits, other.ulimits),
      user: other.user ?? user,
      workdir: other.workdir ?? workdir,
      entrypoint: other.entrypoint ?? entrypoint,
      init: other.init ?? init,
      stopSignal: other.stopSignal ?? stopSignal,
      stopTimeout: other.stopTimeout ?? stopTimeout,
      platform: other.platform ?? platform,
      pull: other.pull ?? pull,
      labels: _mergeMaps(labels, other.labels),
      addHosts: _mergeMaps(addHosts, other.addHosts),
      extraArgs: _mergeLists(extraArgs, other.extraArgs),
      reuse: other.reuse ?? reuse,
    );
  }

  /// Throws an [ArgumentError] for options Docker would refuse:
  /// - A [restart] policy other than `no` with [cleanContainer] (`--rm`).
  void validate() {
    var restart = _trimOrNull(this.restart);
    if ((cleanContainer ?? false) &&
        restart != null &&
        restart.toLowerCase() != 'no') {
      throw ArgumentError.value(
          restart,
          'restart',
          "A restart policy can't be combined with `cleanContainer` "
              '(`--rm`, the default of `run`): pass `cleanContainer: false`');
    }
  }

  /// The Docker CLI arguments of these options, without the command,
  /// the container name and the image. Calls [validate].
  List<String> toArgs() {
    validate();

    var args = <String>[];

    if (cleanContainer ?? false) {
      args.add('--rm');
    }

    var restart = _trimOrNull(this.restart);
    if (restart != null) {
      args.addAll(['--restart', restart]);
    }

    for (var pair in normalizedPorts ?? const <String>[]) {
      // Host port `0`: publish on a free host port chosen by Docker.
      var port = pair.startsWith('0:') ? pair.substring(2) : pair;
      args.addAll(['-p', port]);
    }

    var network = networkName;
    if (network != null) {
      args.addAll(['--net', network]);
    }

    var hostname = hostName;
    if (hostname != null) {
      args.addAll(['-h', hostname]);
    }

    volumes?.forEach((k, v) {
      if (isNotEmptyString(k) && isNotEmptyString(v)) {
        args.addAll(['-v', '$k:$v']);
      }
    });

    environment?.forEach((k, v) {
      if (isNotEmptyString(k)) {
        args.addAll(['-e', '$k=$v']);
      }
    });

    var healthCmd = _trimOrNull(this.healthCmd);
    if (healthCmd != null) {
      args.addAll(['--health-cmd', healthCmd]);
    }

    if (healthInterval != null) {
      args.addAll(['--health-interval', _formatDuration(healthInterval!)]);
    }

    if (healthRetries != null) {
      args.addAll(['--health-retries', '$healthRetries']);
    }

    if (healthStartPeriod != null) {
      args.addAll(
          ['--health-start-period', _formatDuration(healthStartPeriod!)]);
    }

    if (healthTimeout != null) {
      args.addAll(['--health-timeout', _formatDuration(healthTimeout!)]);
    }

    tmpfs?.forEach((path, options) {
      if (isNotEmptyString(path, trim: true)) {
        var opts = options.trim();
        args.addAll(['--tmpfs', opts.isEmpty ? path.trim() : '$path:$opts']);
      }
    });

    _addValue(args, '--shm-size', shmSize);
    _addValue(args, '--memory', memory);
    _addValue(args, '--cpus', cpus);

    ulimits?.forEach((name, limit) {
      if (isNotEmptyString(name, trim: true)) {
        args.addAll(['--ulimit', '${name.trim()}=${limit.trim()}']);
      }
    });

    _addValue(args, '--user', user);
    _addValue(args, '--workdir', workdir);
    _addValue(args, '--entrypoint', entrypoint);

    if (init ?? false) {
      args.add('--init');
    }

    _addValue(args, '--stop-signal', stopSignal);

    if (stopTimeout != null) {
      args.addAll(['--stop-timeout', '${stopTimeout!.inSeconds}']);
    }

    _addValue(args, '--platform', platform);

    if (pull != null) {
      args.addAll(['--pull', pull!.name]);
    }

    labels?.forEach((k, v) {
      if (isNotEmptyString(k, trim: true)) {
        args.addAll(['--label', v.isEmpty ? k.trim() : '${k.trim()}=$v']);
      }
    });

    addHosts?.forEach((host, ip) {
      if (isNotEmptyString(host, trim: true) && isNotEmptyString(ip)) {
        args.addAll(['--add-host', '${host.trim()}:${ip.trim()}']);
      }
    });

    if (extraArgs != null) {
      args.addAll(extraArgs!);
    }

    return args;
  }

  /// These options as JSON. Durations are in milliseconds.
  Map<String, dynamic> toJson() => {
        if (ports != null) 'ports': ports,
        if (network != null) 'network': network,
        if (hostname != null) 'hostname': hostname,
        if (environment != null) 'environment': environment,
        if (volumes != null) 'volumes': volumes,
        if (cleanContainer != null) 'cleanContainer': cleanContainer,
        if (restart != null) 'restart': restart,
        if (healthCmd != null) 'healthCmd': healthCmd,
        if (healthInterval != null)
          'healthInterval': healthInterval!.inMilliseconds,
        if (healthRetries != null) 'healthRetries': healthRetries,
        if (healthStartPeriod != null)
          'healthStartPeriod': healthStartPeriod!.inMilliseconds,
        if (healthTimeout != null)
          'healthTimeout': healthTimeout!.inMilliseconds,
        if (tmpfs != null) 'tmpfs': tmpfs,
        if (shmSize != null) 'shmSize': shmSize,
        if (memory != null) 'memory': memory,
        if (cpus != null) 'cpus': cpus,
        if (ulimits != null) 'ulimits': ulimits,
        if (user != null) 'user': user,
        if (workdir != null) 'workdir': workdir,
        if (entrypoint != null) 'entrypoint': entrypoint,
        if (init != null) 'init': init,
        if (stopSignal != null) 'stopSignal': stopSignal,
        if (stopTimeout != null) 'stopTimeout': stopTimeout!.inMilliseconds,
        if (platform != null) 'platform': platform,
        if (pull != null) 'pull': pull!.name,
        if (labels != null) 'labels': labels,
        if (addHosts != null) 'addHosts': addHosts,
        if (extraArgs != null) 'extraArgs': extraArgs,
        if (reuse != null) 'reuse': reuse,
      };

  /// Parses options from [json] (see [toJson]).
  ///
  /// Also accepts values as strings, as they come from the console:
  /// maps as `key=value|key2=value2` (see [parseInlineMap]), [ports] as
  /// `a:b,c:d` and [extraArgs] separated by spaces.
  factory DockerRunOptions.fromJson(Map json) {
    return DockerRunOptions(
      ports: _parseList(json['ports'], RegExp(r'\s*[,;|]\s*')),
      network: _parseString(json['network']),
      hostname: _parseString(json['hostname']),
      environment: _parseMap(json['environment']),
      volumes: _parseMap(json['volumes']),
      cleanContainer: _parseBool(json['cleanContainer']),
      restart: _parseString(json['restart']),
      healthCmd: _parseString(json['healthCmd']),
      healthInterval: _parseDuration(json['healthInterval']),
      healthRetries: parseInt(json['healthRetries']),
      healthStartPeriod: _parseDuration(json['healthStartPeriod']),
      healthTimeout: _parseDuration(json['healthTimeout']),
      tmpfs: _parseMap(json['tmpfs']),
      shmSize: _parseString(json['shmSize']),
      memory: _parseString(json['memory']),
      cpus: _parseString(json['cpus']),
      ulimits: _parseMap(json['ulimits']),
      user: _parseString(json['user']),
      workdir: _parseString(json['workdir']),
      entrypoint: _parseString(json['entrypoint']),
      init: _parseBool(json['init']),
      stopSignal: _parseString(json['stopSignal']),
      stopTimeout: _parseDuration(json['stopTimeout']),
      platform: _parseString(json['platform']),
      pull: _parsePull(json['pull']),
      labels: _parseMap(json['labels']),
      addHosts: _parseMap(json['addHosts']),
      extraArgs: _parseList(json['extraArgs'], RegExp(r'\s+')),
      reuse: _parseBool(json['reuse']),
    );
  }

  /// The console property names of the options (kebab-case), by JSON key.
  static const Map<String, String> consoleProperties = {
    'tmpfs': 'tmpfs',
    'shm-size': 'shmSize',
    'memory': 'memory',
    'cpus': 'cpus',
    'ulimits': 'ulimits',
    'user': 'user',
    'workdir': 'workdir',
    'entrypoint': 'entrypoint',
    'init': 'init',
    'stop-signal': 'stopSignal',
    'stop-timeout': 'stopTimeout',
    'platform': 'platform',
    'pull': 'pull',
    'labels': 'labels',
    'add-hosts': 'addHosts',
    'extra-args': 'extraArgs',
    'reuse': 'reuse',
  };

  /// Parses options from console properties (see [consoleProperties]).
  /// Unknown properties are ignored.
  factory DockerRunOptions.fromProperties(Map<String, String?> properties) {
    var json = <String, dynamic>{};
    for (var e in consoleProperties.entries) {
      var value = properties[e.key];
      if (isNotEmptyString(value, trim: true)) {
        json[e.value] = value!.trim();
      }
    }
    return DockerRunOptions.fromJson(json);
  }

  /// Normalizes [ports] to `hostPort:containerPort`, removing duplicates.
  /// An entry with a single port maps it to the same host port. An entry
  /// bound to an IP (`ip:hostPort:containerPort`) is kept as it is.
  static List<String>? normalizePorts(List<String>? ports) {
    if (ports == null) return null;

    var portsSet = ports
        .where((e) => isNotEmptyString(e, trim: true))
        .map((e) => e.trim())
        .map((pair) {
      var parts = pair.split(':');
      if (parts.length > 2) return pair;
      var p1 = parseInt(parts[0]);
      var p2 = parts.length > 1 ? parseInt(parts[1], p1) : p1;
      return '$p1:$p2';
    }).toSet();

    return portsSet.isNotEmpty ? portsSet.toList() : null;
  }

  /// Replaces the host port `0` of each of [ports] with the host port
  /// Docker chose, from [mappings] (container port → host port, see
  /// `DockerCMD.getContainerPortMappings`). With no [ports], returns all the
  /// [mappings] as `hostPort:containerPort`.
  static List<String> applyPortMappings(
      List<String>? ports, Map<int, int> mappings) {
    if (ports == null) {
      return mappings.entries.map((e) => '${e.value}:${e.key}').toList();
    }

    return ports.map((p) {
      if (!p.startsWith('0:')) return p;
      var containerPort = parseInt(p.substring(2));
      var hostPort = mappings[containerPort];
      return hostPort != null ? '$hostPort:$containerPort' : p;
    }).toList();
  }

  /// Parses an inline map: entries separated by `|` or `;`, each entry
  /// split at its first `=`. For example `a=1|b=x=y` is `{a: 1, b: x=y}`.
  static Map<String, String>? parseInlineMap(String? s) {
    if (s == null) return null;
    s = s.trim();
    if (s.isEmpty) return null;

    var map = <String, String>{};
    for (var entry in s.split(RegExp(r'[|;]'))) {
      entry = entry.trim();
      if (entry.isEmpty) continue;
      var idx = entry.indexOf('=');
      if (idx < 0) {
        map[entry] = '';
      } else {
        map[entry.substring(0, idx).trim()] = entry.substring(idx + 1).trim();
      }
    }
    return map;
  }

  static String? _trimOrNull(String? s) {
    if (s == null) return null;
    s = s.trim();
    return s.isEmpty ? null : s;
  }

  static void _addValue(List<String> args, String flag, String? value) {
    var v = _trimOrNull(value);
    if (v != null) {
      args.addAll([flag, v]);
    }
  }

  static String _formatDuration(Duration d) => '${d.inMilliseconds}ms';

  static Map<String, String>? _mergeMaps(
      Map<String, String>? a, Map<String, String>? b) {
    if (a == null) return b;
    if (b == null) return a;
    return {...a, ...b};
  }

  static List<String>? _mergeLists(List<String>? a, List<String>? b,
      {bool unique = false}) {
    if (a == null) return b;
    if (b == null) return a;
    var list = [...a, ...b];
    return unique ? list.toSet().toList() : list;
  }

  static String? _parseString(Object? o) => o?.toString();

  static bool? _parseBool(Object? o) => o == null ? null : parseBool(o);

  static Duration? _parseDuration(Object? o) {
    var ms = parseInt(o);
    return ms != null ? Duration(milliseconds: ms) : null;
  }

  static DockerPullPolicy? _parsePull(Object? o) {
    var s = o?.toString().trim().toLowerCase();
    if (s == null || s.isEmpty) return null;
    for (var p in DockerPullPolicy.values) {
      if (p.name == s) return p;
    }
    throw ArgumentError('Invalid pull policy: $o');
  }

  static Map<String, String>? _parseMap(Object? o) {
    if (o == null) return null;
    if (o is Map) {
      return o.map((k, v) => MapEntry('$k', v?.toString() ?? ''));
    }
    return parseInlineMap(o.toString());
  }

  static List<String>? _parseList(Object? o, Pattern separator) {
    if (o == null) return null;
    if (o is List) return o.map((e) => '$e').toList();
    var s = o.toString().trim();
    if (s.isEmpty) return null;
    return s.split(separator).where((e) => e.isNotEmpty).toList();
  }

  @override
  String toString() => 'DockerRunOptions${toJson()}';
}
