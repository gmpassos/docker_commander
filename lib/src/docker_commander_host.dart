import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:swiss_knife/swiss_knife.dart';

/// Base class for Docker machine host.
abstract class DockerHost {
  final int session;

  DockerHost() : session = DateTime.now().millisecondsSinceEpoch;

  /// Initializes instance.
  Future<bool> initialize();

  /// Runs a Docker containers with [image] and optional [version].
  Future<DockerRunner> run(String image,
      {String version,
      String name,
      bool cleanContainer = true,
      bool outputAsLines = true,
      int outputLimit,
      OutputReadyFunction stdoutReadyFunction,
      OutputReadyFunction stderrReadyFunction});

  /// Checks if Docker daemon is running.
  Future<bool> checkDaemon();

  /// Returns a Docker container ID with [name].
  Future<String> getContainerIDByName(String name);

  /// Resolves a Docker image, composed by [imageName] and [version].
  static String resolveImage(String imageName, [String version]) {
    var image = imageName.trim();

    if (isNotEmptyString(version, trim: true)) {
      version = version.trim();
      var idx = image.lastIndexOf(':');
      if (idx > 0) {
        image = image.substring(0, idx);
      }
      image += ':$version';
    }

    return image;
  }

  /// Closes this instance, cleaning any resource.
  Future<void> close();
}

/// Represents a Docker container running.
abstract class DockerRunner {
  static int _instanceIDCounter = 0;

  static int incrementInstanceID() => ++_instanceIDCounter;

  final DockerHost dockerHost;
  final int instanceID;
  final String name;

  DockerRunner(this.dockerHost, this.instanceID, this.name);

  String get id;

  static final int DEFAULT_OUTPUT_LIMIT = 1000;

  Output _stdout;

  Output _stderr;

  Output get stdout => _stdout;

  Output get stderr => _stderr;

  void setupStdout(OutputStream outputStream) {
    _stdout = Output(outputStream);
  }

  void setupStderr(OutputStream outputStream) {
    _stderr = Output(outputStream);
  }

  Future<bool> waitReady();

  bool get isReady;

  Future<int> waitExit();

  @override
  String toString() {
    return 'DockerRunner{id: $id, instanceID: $instanceID, name: $name, ready: $isReady, dockerHost: $dockerHost}';
  }
}

/// Output wrapper of a Docker container.
class Output {
  final OutputStream _outputStream;

  Output(this._outputStream);

  /// Returns all the output as bytes.
  List<int> get asBytes => _outputStream.asBytes;

  /// Returns all the output as [String].
  String get asString => _outputStream.asString;

  /// Returns all the output as lines (List<String>).
  List<String> get asLines => _outputStream.asLines;

  /// Returns [true] if output is ready, based in
  /// the associated [OutputReadyFunction].
  bool get isReady => _outputStream.isReady;

  /// Waits the output to be ready.
  Future<bool> waitReady() => _outputStream.waitReady();
}

typedef OutputReadyFunction = bool Function(
    OutputStream outputStream, dynamic data);

/// Handles the output stream of a Docker container.
class OutputStream<T> {
  final bool lines;

  /// The limit of entries.
  int _limit;

  /// The functions that determines if this output is ready.
  /// Called for each output entry.
  final OutputReadyFunction outputReadyFunction;

  OutputStream(this.lines, this._limit, this.outputReadyFunction);

  bool _ready = false;
  final Completer<bool> _readyCompleter = Completer();

  bool get isReady => _ready;

  Future<bool> waitReady() async {
    if (isReady) {
      return true;
    }
    return await _readyCompleter.future;
  }

  /// Mars this output as ready.
  void markReady() {
    _ready = true;
    _readyCompleter.complete(true);
  }

  int get limit => _limit;

  set limit(int value) {
    _limit = value ?? 0;
  }

  /// The data buffer;
  final List<T> _data = <T>[];

  /// Adds an [entry] to the [_data] buffer.
  void add(T entry) {
    _data.add(entry);

    if (outputReadyFunction(this, entry)) {
      markReady();
    }

    if (_limit > 0) {
      while (_data.length > _limit) {
        _data.removeAt(0);
      }
    }
  }

  /// Adds all [entries] to the [_data] buffer.
  void addAll(Iterable<T> entries) {
    _data.addAll(entries);

    if (outputReadyFunction(this, entries)) {
      markReady();
    }

    if (_limit > 0) {
      var rm = _data.length - _limit;
      if (rm > 0) {
        _data.removeRange(0, rm);
      }
    }
  }

  /// Converts and returns [_data] entries as bytes.
  List<int> get asBytes {
    if (lines) {
      return utf8.encode(asString);
    } else {
      return List.unmodifiable(_data as List<int>);
    }
  }

  /// Converts and returns [_data] entries as [String].
  String get asString {
    if (lines) {
      return _data.join('\n');
    } else {
      return systemEncoding.decode(_data as List<int>);
    }
  }

  /// Converts and returns [_data] entries as lines [List<String>].
  List<String> get asLines {
    if (lines) {
      return List.unmodifiable(_data as List<String>);
    } else {
      return asString.split(RegExp(r'\r?\n'));
    }
  }
}
