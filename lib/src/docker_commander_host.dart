import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:swiss_knife/swiss_knife.dart';

abstract class DockerHost {
  final int session;

  DockerHost() : session = DateTime.now().millisecondsSinceEpoch;

  Future<bool> initialize();

  Future<DockerRunner> run(String image,
      {String version,
      String name,
      bool cleanContainer = true,
      bool outputAsLines = true,
      int outputLimit,
      OutputReadyFunction stdoutReadyFunction,
      OutputReadyFunction stderrReadyFunction});

  Future<bool> checkDaemon();

  Future<String> getContainerIDByName(String name);

  String resolveImage(String imageName, String version) {
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

  Future<void> close();
}

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

class Output {
  final OutputStream _outputStream;

  Output(this._outputStream);

  List<int> get asBytes => _outputStream.asBytes;

  String get asString => _outputStream.asString;

  List<String> get asLines => _outputStream.asLines;

  bool get isReady => _outputStream.isReady;

  Future<bool> waitReady() => _outputStream.waitReady();
}

typedef OutputReadyFunction = bool Function(
    OutputStream outputStream, dynamic data);

class OutputStream<T> {
  final bool lines;

  int _limit;

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

  void markReady() {
    _ready = true;
    _readyCompleter.complete(true);
  }

  int get limit => _limit;

  set limit(int value) {
    _limit = value ?? 0;
  }

  final List<T> _data = <T>[];

  void add(T entry) {
    _data.add(entry);
    if (_limit > 0) {
      while (_data.length > _limit) {
        _data.removeAt(0);
      }
    }
  }

  void addAll(Iterable<T> entries) {
    _data.addAll(entries);
    if (_limit > 0) {
      var rm = _data.length - _limit;
      if (rm > 0) {
        _data.removeRange(0, rm);
      }
    }
  }

  List<int> get asBytes {
    if (lines) {
      return utf8.encode(asString);
    } else {
      return List.unmodifiable(_data as List<int>);
    }
  }

  String get asString {
    if (lines) {
      return _data.join('\n');
    } else {
      return systemEncoding.decode(_data as List<int>);
    }
  }

  List<String> get asLines {
    if (lines) {
      return List.unmodifiable(_data as List<String>);
    } else {
      return asString.split(RegExp(r'\r?\n'));
    }
  }
}
