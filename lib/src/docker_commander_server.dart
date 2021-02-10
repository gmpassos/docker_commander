import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:docker_commander/src/docker_commander_host.dart';
import 'package:docker_commander/src/docker_commander_local.dart';
import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

final _LOG = Logger('docker_commander/server');

typedef AuthenticationGrantor = Future<bool> Function(
    String username, String password);

/// A basic table of `username` and `password`.
class AuthenticationTable {
  final Map<String, String> usernamesAndPasswords;

  AuthenticationTable(this.usernamesAndPasswords);

  bool checkPassword(String username, String password) {
    var pass = usernamesAndPasswords[username];
    return pass != null && pass == password;
  }
}

/// A [DockerHost] Server, to be used by [DockerHostRemote].
class DockerHostServer {
  /// The [HttpServer] port.
  final int listenPort;

  /// If [true] will accept connections from any hostname.
  final bool public;

  /// If [true] will use IPv6.
  final bool ipv6;

  /// The authenticator, for username and password.
  final AuthenticationGrantor _authenticationGrantor;

  /// The authentication token timeout.
  final Duration authenticationTokenTimeout;

  DockerHostServer(this._authenticationGrantor, this.listenPort,
      {this.public = false,
      this.ipv6 = false,
      Duration authenticationTokenTimeout})
      : authenticationTokenTimeout =
            authenticationTokenTimeout ?? Duration(hours: 1);

  DockerHostLocal _dockerHostLocal;

  HttpServer _server;

  Completer _started;

  bool get isStarted => _started != null ? _started.isCompleted : false;

  Future<void> startAndWait() async {
    start();
    await waitStart();
  }

  void waitStart() async {
    if (isStarted) return;
    await _started.future;
  }

  void start() async {
    if (_started != null) return;

    _LOG.info('[SERVER]\tSTARTING...');

    _started = Completer();

    dynamic address;
    if (ipv6) {
      address = public ? InternetAddress.anyIPv6 : InternetAddress.loopbackIPv6;
    } else {
      address = public ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4;
    }

    _server = await HttpServer.bind(
      address,
      listenPort,
    );

    _LOG.info('[SERVER]\tSTARTED> port: $listenPort ; server: $_server');

    _started.complete(true);

    _acceptLoop();
  }

  void _acceptLoop() async {
    await for (HttpRequest request in _server) {
      if (request.method == 'OPTION') {
        await _processOptionRequest(request);
      } else {
        await _processRequest(request);
      }
    }
  }

  Future _processOptionRequest(HttpRequest request) async {
    request.response.statusCode = 204;
    _setResponseCORS(request);

    var remoteAddress = request.connectionInfo?.remoteAddress;

    print('[SERVER]\tOPTION>\t$remoteAddress\t${request.uri} ');

    await request.response.close();
  }

  void _setResponseCORS(HttpRequest request) {
    var origin = request.headers['Origin'] ??
        'http://${request.headers.host}:$listenPort/';

    request.response.headers
        .add('Access-Control-Allow-Origin', origin, preserveHeaderCase: true);

    request.response.headers.add('Access-Control-Allow-Methods',
        'GET,HEAD,PUT,POST,PATCH,DELETE,OPTIONS');
    request.response.headers.add('Access-Control-Allow-Credentials', 'true');

    request.response.headers.add('Access-Control-Allow-Headers',
        'Content-Type, Access-Control-Allow-Headers, Authorization, x-ijt');
    request.response.headers.add('Access-Control-Expose-Headers',
        'Content-Length, Content-Type, Last-Modified, X-Access-Token, X-Access-Token-Expiration');
  }

  Future<String> _decodeBody(
      ContentType contentType, HttpRequest request) async {
    if (contentType != null) {
      var charset = contentType.charset;

      if (charset != null) {
        charset = charset.trim().toLowerCase();

        if (charset == 'utf8' || charset == 'utf-8') {
          return utf8.decoder.bind(request).join();
        } else if (charset == 'latin1' ||
            charset == 'latin-1' ||
            charset == 'iso-8859-1') {
          return latin1.decoder.bind(request).join();
        }
      }
    }

    return latin1.decoder.bind(request).join();
  }

  void close() async {
    _LOG.info('[SERVER]\tCLOSE> $_server');
    await _server.close(force: true);
    _server = null;
    _started = null;
  }

  Future _processRequest(HttpRequest request) async {
    var operation = request.uri.pathSegments.last;
    var parameters = request.uri.queryParameters;

    var contentType = request.headers.contentType;
    var body = await _decodeBody(contentType, request);

    request.response.statusCode = HttpStatus.processing;

    dynamic response;
    try {
      response = await _processOperation(
          request, operation, parameters, contentType, body);
    } catch (e, s) {
      _LOG.severe(
          'Error processing request: $request > operation: $operation ; parameters: $parameters ; body: $body',
          e,
          s);
    }

    if (request.response.statusCode == HttpStatus.processing) {
      request.response.statusCode = response != null ? 200 : 404;
    }

    print(
        '[SERVER]\tRESPONSE> responseStatus: ${request.response.statusCode} ; body: $response');

    _setResponseCORS(request);

    if (response != null) {
      var json = encodeJSON(response);

      request.response.headers
          .add('Content-Type', 'application/json', preserveHeaderCase: true);
      request.response.headers
          .add('Content-Length', json.length, preserveHeaderCase: true);

      request.response.write(json);
    }

    await request.response.close();
  }

  final Map<String, int> _authenticationCount = {};

  final Map<String, int> _authenticationTime = {};

  void _cleanAuthentications(int now) {
    var timeout = Duration(minutes: 5).inMilliseconds;

    var del = <String>[];

    for (var entry in _authenticationTime.entries) {
      var elapsed = now - entry.value;

      if (elapsed > timeout) {
        del.add(entry.key);
      }
    }

    for (var user in del) {
      _authenticationCount.remove(user);
      _authenticationTime.remove(user);
    }
  }

  Future<bool> checkPassword(String username, String password) async {
    if (isEmptyString(username) || isEmptyString(password)) return false;

    var now = DateTime.now().millisecondsSinceEpoch;
    _cleanAuthentications(now);

    var count = _authenticationCount.putIfAbsent(username, () => 0);
    if (count > 5) return false;

    _authenticationCount[username] = count + 1;
    _authenticationTime[username] = now;

    var ok = (await _authenticationGrantor(username, password)) ?? false;
    return ok;
  }

  static final int _MAX_INT = 2147483647;

  final Random _random1 = Random();
  final Random _random2 = Random(Random().nextInt(_MAX_INT));

  int _tokenCounter = 0;

  String _generateToken() {
    var count = ++_tokenCounter;
    var now = DateTime.now().millisecondsSinceEpoch;

    var a = _random1.nextInt(_MAX_INT);
    var b = _random1.nextInt(_MAX_INT);

    var n1 = a ^ count ^ _random2.nextInt(_MAX_INT);
    var n2 = b ^ now ^ _random2.nextInt(_MAX_INT);

    var n3 = n1 ^ _random1.nextInt(_MAX_INT);
    var n4 = n2 ^ _random2.nextInt(_MAX_INT);

    if (a % 2 == 0) {
      return b % 2 == 0 ? 'TK$n1$n2$n3$n4' : 'TK$n2$n1$n4$n3';
    } else {
      return b % 2 == 0 ? 'TK$n4$n3$n2$n1' : 'TK$n3$n4$n1$n2';
    }
  }

  int _getParameterAsInt(
      Map<String, String> parameters, dynamic json, String key,
      [int def]) {
    var val = _getParameter(parameters, json, key);
    return parseInt(val, def);
  }

  dynamic _getParameter(
      Map<String, String> parameters, dynamic json, String key) {
    var value = parameters != null ? parameters[key] : null;
    if (value != null) return value;
    if (json is Map) {
      return json[key];
    }
    return null;
  }

  Future<dynamic> _processOperation(
      HttpRequest request,
      String operation,
      Map<String, String> parameters,
      ContentType contentType,
      String body) async {
    _LOG.info(
        '[SERVER]\tPROCESS OPERATION>\t operation: $operation ; parameters: $parameters ; body: $body');

    switch (operation) {
      case 'auth':
        return _processAuth(request, parameters, parseJSON(body));
      case 'initialize':
        return _processInitialize(request, parameters, parseJSON(body));
      case 'check_daemon':
        return _processCheckDaemon(request, parameters, parseJSON(body));
      case 'id_by_name':
        return _processIDByName(request, parameters, parseJSON(body));
      case 'close':
        return _processClose(request, parameters, parseJSON(body));
      case 'run':
        return _processRun(request, parameters, parseJSON(body));
      case 'stdout':
      case 'stderr':
        return _processOutput(request, operation, parameters, parseJSON(body));
      case 'runner_wait_ready':
        return _processRunnerWaitReady(request, parameters, parseJSON(body));
      case 'runner_wait_exit':
        return _processRunnerWaitExit(request, parameters, parseJSON(body));
      case 'runner_stop':
        return _processRunnerStop(request, parameters, parseJSON(body));
      default:
        return null;
    }
  }

  final Map<String, AccessToken> _usersTokens = {};

  bool validateToken(String token) {
    _checkTokens();
    var valid = _usersTokens.values.contains(token);
    return valid;
  }

  void _checkTokens() {
    var now = DateTime.now().millisecondsSinceEpoch;
    var timeout = authenticationTokenTimeout.inMilliseconds;
    _usersTokens.removeWhere((key, value) => !value.isValid(now, timeout));
  }

  Future<Map<String, String>> _processAuth(
      HttpRequest request, Map<String, String> parameters, dynamic json) async {
    var authorization = request.headers['Authorization']?.first?.trim();

    String username;
    String password;

    if (isNotEmptyString(authorization)) {
      var parts = authorization.split(RegExp(r'\s+'));
      var type = parts[0].toLowerCase();

      if (type == 'basic') {
        var base64 = parts[1];
        var userAndPass = Base64.decode(base64).split(':');
        username = userAndPass[0];
        password = userAndPass[1];
      } else if (type == 'bearer') {
        var token = parts[1];
        var ok = validateToken(token);

        if (ok) {
          return _setHeader_X_Access_Token(request, token);
        }
      }
    }

    username ??= _getParameter(parameters, json, 'username');
    password ??= _getParameter(parameters, json, 'password');

    var ok = await checkPassword(username, password);
    if (!ok) {
      request.response.statusCode = HttpStatus.unauthorized;
      return null;
    }

    _checkTokens();
    var token =
        _usersTokens.putIfAbsent(username, () => AccessToken(_generateToken()));

    return _setHeader_X_Access_Token(request, token.token);
  }

  Map<String, String> _setHeader_X_Access_Token(
      HttpRequest request, String token) {
    request.response.headers
        .add('X-Access-Token', token, preserveHeaderCase: true);

    return {'access_token': token};
  }

  Future<bool> _processInitialize(
      HttpRequest request, Map<String, String> parameters, json) async {
    _dockerHostLocal ??= DockerHostLocal();
    var ok = await _dockerHostLocal.initialize();
    return ok;
  }

  Future<bool> _processCheckDaemon(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;
    var ok = await _dockerHostLocal.checkDaemon();
    return ok;
  }

  Future<String> _processIDByName(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    var name = _getParameter(parameters, json, 'name');

    var id = await _dockerHostLocal.getContainerIDByName(name);
    return id;
  }

  Future<bool> _processClose(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;
    await _dockerHostLocal.close();
    return true;
  }

  Future<Map> _processRun(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    String imageName = _getParameter(parameters, json, 'image');
    String version = _getParameter(parameters, json, 'version');
    String imageArgsEncoded = _getParameter(parameters, json, 'imageArgs');
    String name = _getParameter(parameters, json, 'name');
    String portsLine = _getParameter(parameters, json, 'ports');
    String network = _getParameter(parameters, json, 'network');
    String hostname = _getParameter(parameters, json, 'hostname');
    String environmentLine = _getParameter(parameters, json, 'environment');
    String cleanContainer = _getParameter(parameters, json, 'cleanContainer');
    String outputAsLines = _getParameter(parameters, json, 'outputAsLines');
    String outputLimit = _getParameter(parameters, json, 'outputLimit');

    var ports = isNotEmptyString(portsLine) ? portsLine.split(',') : null;

    var environment = decodeQueryString(environmentLine);

    List<String> imageArgs;
    if (isNotEmptyString(imageArgsEncoded)) {
      imageArgs = parseJSON(imageArgsEncoded);
    }

    var runner = await _dockerHostLocal.run(imageName,
        version: version,
        imageArgs: imageArgs,
        name: name,
        ports: ports,
        network: network,
        hostname: hostname,
        environment: environment,
        cleanContainer: parseBool(cleanContainer),
        outputAsLines: parseBool(outputAsLines),
        outputLimit: parseInt(outputLimit));

    return {
      'instanceID': runner.instanceID,
      'name': runner.name,
      'id': runner.id,
    };
  }

  Future<bool> _processRunnerWaitReady(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;

    var instanceID = _getParameterAsInt(parameters, json, 'instanceID');

    var runner = _dockerHostLocal.getRunnerByInstanceID(instanceID);
    if (runner == null) return false;

    var ok = await runner.waitReady();
    return ok;
  }

  Future<int> _processRunnerWaitExit(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    var instanceID = _getParameterAsInt(parameters, json, 'instanceID');

    var runner = _dockerHostLocal.getRunnerByInstanceID(instanceID);
    if (runner == null) return null;

    var ok = await runner.waitExit();
    return ok;
  }

  Future<bool> _processRunnerStop(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;

    var instanceID = _getParameterAsInt(parameters, json, 'instanceID');

    var ok = await _dockerHostLocal.stopByInstanceID(instanceID);
    return ok;
  }

  Future<Map> _processOutput(HttpRequest request, String type,
      Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    var instanceID = _getParameterAsInt(parameters, json, 'instanceID');
    var realOffset = _getParameterAsInt(parameters, json, 'realOffset');

    var runner = _dockerHostLocal.getRunnerByInstanceID(instanceID);
    if (runner == null) return {'running': true};

    var output = type == 'stderr' ? runner.stderr : runner.stdout;

    var length = output.entriesLength;
    var removed = output.entriesRemoved;
    var entries = output.getEntries(realOffset: realOffset);

    return {
      'running': true,
      'length': length,
      'removed': removed,
      'entries': entries,
    };
  }
}

class AccessToken {
  final String token;

  final int time;

  AccessToken(this.token) : time = DateTime.now().millisecondsSinceEpoch;

  bool isValid(int now, int timeout) {
    var elapsed = now - time;
    return elapsed < timeout;
  }
}
