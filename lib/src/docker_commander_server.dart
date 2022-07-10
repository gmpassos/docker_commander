import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_host.dart';
import 'docker_commander_local.dart';

final _log = Logger('docker_commander/server');

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

  @override
  String toString() {
    return 'AuthenticationTable{users: ${usernamesAndPasswords.length}}';
  }
}

class Authentication {
  final String? username;

  final String? token;

  final bool grant;

  Authentication({this.username, this.token, this.grant = false});
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
      Duration? authenticationTokenTimeout})
      : authenticationTokenTimeout =
            authenticationTokenTimeout ?? Duration(hours: 1);

  static const Set<String> weakUsernames = {
    'user',
    'user1',
    'user2',
    'userx',
    'usery',
    'username',
    'usernamex',
    'usernamey',
    'nick',
    'nickname',
    'foo',
    'bar',
    'baz',
    'me',
  };

  static const Set<String> weakPasswords = {
    '',
    '1',
    '12',
    '123',
    '1234',
    '12345',
    '123456',
    '1234567',
    '12345678',
    '123456789',
    '1234567890',
    'a',
    'ab',
    'abc',
    'abcd',
    'abcde',
    'abcdef',
    'abcdefg',
    'abcdefgh',
    'abcdefghi',
    'abcdefghij',
    'abcdefghijk',
    'pass',
    'password',
    'pass123',
    'pass123456',
    'abc123',
    '123abc',
  };

  Future<bool> checkAuthenticationBasicSecurity() async {
    var usernames =
        weakUsernames.expand((e) => [e, e.toLowerCase(), e.toUpperCase()]);
    var passwords =
        weakPasswords.expand((e) => [e, e.toLowerCase(), e.toUpperCase()]);

    var all = <String>{...usernames, ...passwords};

    var weak = false;

    USERNAMES_LOOP:
    for (var user in all) {
      for (var pass in all) {
        var grant = await _authenticationGrantor(user, pass);

        if (grant) {
          weak = true;
          break USERNAMES_LOOP;
        }
      }
    }

    if (weak) {
      _log.warning(
          'AUTHENTICATOR GRANTOR ACCEPTING WEAK CREDENTIALS!!! DO NOT DEPLOY THIS IN PRODUCTION OR PUBLIC NETWORKS!!!');
    }

    return !weak;
  }

  DockerHostLocal? _dockerHostLocal;

  HttpServer? _server;

  Completer? _started;

  bool get isStarted => _started != null ? _started!.isCompleted : false;

  Future<void> startAndWait() async {
    await start();
    await waitStart();
  }

  Future<void> waitStart() async {
    if (isStarted) return;
    await _started!.future;
  }

  Future<void> start() async {
    if (_started != null) return;

    _log.info('[SERVER]\tSTARTING...');

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

    _log.info('[SERVER]\tSTARTED> port: $listenPort ; server: $_server');

    _started!.complete(true);

    _acceptLoop();
  }

  void _closeServer({Duration? delay}) {
    delay ??= Duration(milliseconds: 100);

    Future.delayed(delay, () {
      try {
        _server!.close(force: true);
      } catch (e) {
        _log.severe('Error closing server', e);
      }
    });
  }

  void _acceptLoop() async {
    await for (HttpRequest request in _server!) {
      try {
        if (request.method == 'OPTION') {
          await _processOptionRequest(request);
        } else {
          await _processRequest(request);
        }
      } catch (e, s) {
        print(e);
        print(s);
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

    setResponseHeader(request, 'Access-Control-Allow-Origin', '$origin');
    setResponseHeader(request, 'Access-Control-Allow-Methods',
        'GET,HEAD,PUT,POST,PATCH,DELETE,OPTIONS');
    setResponseHeader(request, 'Access-Control-Allow-Credentials', 'true');
    setResponseHeader(request, 'Access-Control-Allow-Headers',
        'Content-Type, Access-Control-Allow-Headers, Authorization, x-ijt');
    setResponseHeader(request, 'Access-Control-Expose-Headers',
        'Content-Length, Content-Type, Last-Modified, X-Access-Token, X-Access-Token-Expiration');
  }

  Future<String> _decodeBody(
      ContentType? contentType, HttpRequest request) async {
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
    _log.info('[SERVER]\tCLOSE> $_server');
    await _server!.close(force: true);
    _server = null;
    _started = null;
  }

  Future<void> _processRequest(HttpRequest request) async {
    if (request.uri.pathSegments.isEmpty) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }

    var operation = request.uri.pathSegments.last;
    var requestParameters = request.uri.queryParameters;

    var requestContentType = request.headers.contentType;
    var requestBody = await _decodeBody(requestContentType, request);

    request.response.statusCode = HttpStatus.processing;

    dynamic response;
    try {
      response = await _processOperation(request, operation, requestParameters,
          requestContentType, requestBody);
    } catch (e, s) {
      _log.severe(
          'Error processing request: $request > operation: $operation ; parameters: $requestParameters ; body: $requestBody',
          e,
          s);
    }

    if (request.response.statusCode == HttpStatus.processing) {
      request.response.statusCode = response != null ? 200 : 404;
    }

    if (operation != 'stdout' && operation != 'stderr') {
      var responseBody = _bodyToShortString(response);

      print(
          '[SERVER]\tRESPONSE> responseStatus: ${request.response.statusCode} ; body: ${responseBody.length < 10 ? responseBody : responseBody.length} >> operation: $operation ; parameters: $requestParameters');
    }

    _setResponseCORS(request);

    if (response != null) {
      var json = encodeJSON(response);

      request.response.headers.add(
          'Content-Type', 'application/json; charset=utf-8',
          preserveHeaderCase: true);

      request.response.write(json);
    }

    await request.response.close();
  }

  String _bodyToShortString(response) {
    String? responseBody;

    if (response == null || response is int || response is bool) {
      responseBody = '$response';
    } else if (response is String) {
      responseBody =
          response.length <= 10 ? response : 'String#${response.length}';
    } else if (response is List) {
      responseBody = 'List#${response.length}';
    } else if (response is Map) {
      responseBody = 'Map#${response.length}';
    } else {
      responseBody = responseBody.runtimeType.toString();
    }
    return responseBody;
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

  Future<bool> checkPassword(String? username, String? password) async {
    if (isEmptyString(username) || isEmptyString(password)) return false;

    var now = DateTime.now().millisecondsSinceEpoch;
    _cleanAuthentications(now);

    var count = _authenticationCount.putIfAbsent(username!, () => 0);
    if (count > 10) return false;

    _authenticationCount[username] = count + 1;
    _authenticationTime[username] = now;

    var ok = await _authenticationGrantor(username, password!);
    return ok;
  }

  static final int _maxInt = 2147483647;

  final Random _random1 = Random();
  final Random _random2 = Random(Random().nextInt(_maxInt));

  int _tokenCounter = 0;

  String _generateToken() {
    var count = ++_tokenCounter;
    var now = DateTime.now().millisecondsSinceEpoch;

    var a = _random1.nextInt(_maxInt);
    var b = _random1.nextInt(_maxInt);

    var n1 = a ^ count ^ _random2.nextInt(_maxInt);
    var n2 = b ^ now ^ _random2.nextInt(_maxInt);

    var n3 = n1 ^ _random1.nextInt(_maxInt);
    var n4 = n2 ^ _random2.nextInt(_maxInt);

    if (a % 2 == 0) {
      return b % 2 == 0 ? 'TK$n1$n2$n3$n4' : 'TK$n2$n1$n4$n3';
    } else {
      return b % 2 == 0 ? 'TK$n4$n3$n2$n1' : 'TK$n3$n4$n1$n2';
    }
  }

  int? _getParameterAsInt(
      Map<String, String> parameters, dynamic json, String key,
      [int? def]) {
    var val = _getParameter(parameters, json, key);
    return parseInt(val, def);
  }

  dynamic _getParameter(
      Map<String, String> parameters, dynamic json, String key) {
    var value = parameters[key];
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
      ContentType? contentType,
      String body) async {
    if (operation != 'stdout' && operation != 'stderr') {
      _log.info(
          '[SERVER]\tPROCESS OPERATION>\t operation: $operation ; parameters: $parameters ; body: $body');
    }

    if (operation == 'auth') {
      return _processAuth(request, parameters, parseJSON(body));
    }

    var authentication = await checkAuthentication(request, parameters);

    if (!authentication.grant) {
      request.response.statusCode = HttpStatus.unauthorized;
      return null;
    }

    switch (operation) {
      case 'initialize':
        return _processInitialize(request, parameters, parseJSON(body));
      case 'check_daemon':
        return _processCheckDaemon(request, parameters, parseJSON(body));
      case 'id_by_name':
        return _processIDByName(request, parameters, parseJSON(body));
      case 'close':
        return _processClose(request, parameters, parseJSON(body));
      case 'create':
        return _processCreate(request, parameters, parseJSON(body));
      case 'run':
        return _processRun(request, parameters, parseJSON(body));
      case 'exec':
        return _processExec(request, parameters, parseJSON(body));
      case 'command':
        return _processCommand(request, parameters, parseJSON(body));
      case 'stdout':
      case 'stderr':
        return _processOutput(request, operation, parameters, parseJSON(body));
      case 'wait_ready':
        return _processWaitReady(request, parameters, parseJSON(body));
      case 'wait_exit':
        return _processWaitExit(request, parameters, parseJSON(body));
      case 'stop':
        return _processStop(request, parameters, parseJSON(body));
      case 'list-formulas':
        return _processListFormulas(request, parameters);
      case 'get-formulas-class-name':
        return _processGetFormulaClassName(
            request, parameters, parseJSON(body));
      case 'get-formulas-fields':
        return _processGetFormulaFields(request, parameters, parseJSON(body));
      case 'list-formula-functions':
        return _processListFormulaFunctions(
            request, parameters, parseJSON(body));
      case 'formula-exec':
        return _processFormulaExec(request, parameters, parseJSON(body));
      default:
        return null;
    }
  }

  Future<List<String>> _processListFormulas(
      HttpRequest request, Map<String, String> parameters) {
    return _dockerHostLocal!.listFormulasNames();
  }

  Future<String?> _processGetFormulaClassName(
      HttpRequest request, Map<String, String> parameters, json) async {
    var formulaName = _getParameter(parameters, json, 'formula')!;
    return _dockerHostLocal!.getFormulaClassName(formulaName);
  }

  Future<Map<String, Object>?> _processGetFormulaFields(
      HttpRequest request, Map<String, String> parameters, json) async {
    var formulaName = _getParameter(parameters, json, 'formula')!;
    return _dockerHostLocal!.getFormulaFields(formulaName);
  }

  Future<List<String>> _processListFormulaFunctions(
      HttpRequest request, Map<String, String> parameters, json) async {
    var formulaName = _getParameter(parameters, json, 'formula');
    return _dockerHostLocal!.listFormulasFunctions(formulaName);
  }

  Future<dynamic> _processFormulaExec(
      HttpRequest request, Map<String, String> parameters, json) async {
    var formulaName = _getParameter(parameters, json, 'formula');
    var fName = _getParameter(parameters, json, 'function');
    String? argsEncoded = _getParameter(parameters, json, 'args');
    String? fieldsEncoded = _getParameter(parameters, json, 'fields');

    var args = _decodeArgs(argsEncoded);
    var fields = _decodeProperties(fieldsEncoded);

    var ok =
        await _dockerHostLocal!.formulaExec(formulaName, fName, args, fields);

    return ok;
  }

  Future<Authentication> checkAuthentication(
      HttpRequest request, Map<String, String> parameters) async {
    var authorization = request.headers['Authorization']?.first.trim();

    String? username;
    String? password;

    if (isNotEmptyString(authorization)) {
      var parts = authorization!.split(RegExp(r'\s+'));
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
          setResponseHeader(request, 'X-Access-Token', token);
          return Authentication(token: token, grant: true);
        }
      }
    }

    username ??= _getParameter(parameters, json, 'username');
    password ??= _getParameter(parameters, json, 'password');

    var ok = await checkPassword(username, password);
    if (!ok) {
      request.response.statusCode = HttpStatus.unauthorized;
      return Authentication(username: username, grant: false);
    }

    _checkTokens();
    var accessToken = _usersTokens.putIfAbsent(
        username!, () => AccessToken(_generateToken()));

    var token = accessToken.token;

    setResponseHeader(request, 'X-Access-Token', token);
    return Authentication(username: username, token: token, grant: true);
  }

  void setResponseHeader(HttpRequest request, String key, String value) {
    request.response.headers.add(key, value, preserveHeaderCase: true);
  }

  final Map<String, AccessToken> _usersTokens = {};

  bool validateToken(String token) {
    _checkTokens();
    var valid = _usersTokens.values.where((a) => a.token == token).isNotEmpty;
    return valid;
  }

  void _checkTokens() {
    var now = DateTime.now().millisecondsSinceEpoch;
    var timeout = authenticationTokenTimeout.inMilliseconds;
    _usersTokens.removeWhere((key, value) => !value.isValid(now, timeout));
  }

  Future<Map<String, String>?> _processAuth(
      HttpRequest request, Map<String, String> parameters, dynamic json) async {
    var authentication = await checkAuthentication(request, parameters);

    if (!authentication.grant) {
      request.response.statusCode = HttpStatus.unauthorized;
      return null;
    }

    return {'access_token': authentication.token!};
  }

  Future<bool> _processInitialize(
      HttpRequest request, Map<String, String> parameters, json) async {
    _dockerHostLocal ??= DockerHostLocal();

    var dockerHostLocal = _dockerHostLocal!;
    if (dockerHostLocal.isInitialized) {
      return dockerHostLocal.isSuccessfullyInitialized;
    }

    var dockerCommander = DockerCommander(dockerHostLocal);
    var ok = await dockerHostLocal.initialize(dockerCommander);
    return ok;
  }

  Future<bool> _processCheckDaemon(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;
    var ok = await _dockerHostLocal!.checkDaemon();
    return ok;
  }

  Future<String?> _processIDByName(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    var name = _getParameter(parameters, json, 'name');

    var id = await _dockerHostLocal!.getContainerIDByName(name);
    return id;
  }

  Future<bool> _processClose(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;
    await _dockerHostLocal!.close();
    _closeServer(delay: Duration(seconds: 2));
    return true;
  }

  Future<Map?> _processCreate(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    String imageName = _getParameter(parameters, json, 'image');
    String? version = _getParameter(parameters, json, 'version');
    String containerName = _getParameter(parameters, json, 'name');
    String? portsLine = _getParameter(parameters, json, 'ports');
    String? network = _getParameter(parameters, json, 'network');
    String? hostname = _getParameter(parameters, json, 'hostname');
    String? environmentLine = _getParameter(parameters, json, 'environment');
    String? volumesLine = _getParameter(parameters, json, 'volumes');
    String? cleanContainer = _getParameter(parameters, json, 'cleanContainer');

    String? healthCmd = _getParameter(parameters, json, 'healthCmd');
    String? healthInterval = _getParameter(parameters, json, 'healthInterval');
    String? healthRetries = _getParameter(parameters, json, 'healthRetries');
    String? healthStartPeriod =
        _getParameter(parameters, json, 'healthStartPeriod');
    String? healthTimeout = _getParameter(parameters, json, 'healthTimeout');

    String? restart = _getParameter(parameters, json, 'restart');

    var ports = isNotEmptyString(portsLine) ? portsLine!.split(',') : null;

    var environment = decodeQueryString(environmentLine);

    var volumes = decodeQueryString(volumesLine);

    var containerInfos = await _dockerHostLocal!.createContainer(
      containerName,
      imageName,
      version: version,
      ports: ports,
      network: network,
      hostname: hostname,
      environment: environment,
      volumes: volumes,
      cleanContainer: parseBool(cleanContainer)!,
      healthCmd: healthCmd,
      healthInterval: _parseDurationInMs(healthInterval),
      healthRetries: parseInt(healthRetries),
      healthStartPeriod: _parseDurationInMs(healthStartPeriod),
      healthTimeout: _parseDurationInMs(healthTimeout),
      restart: restart,
    );

    if (containerInfos == null) return null;

    return {
      'containerName': containerInfos.containerName,
      'id': containerInfos.id,
      'image': imageName,
      'ports': ports,
      'network': network,
      'hostname': hostname,
    };
  }

  Duration? _parseDurationInMs(dynamic duration) {
    var ms = parseInt(duration);
    return ms != null ? Duration(milliseconds: ms) : null;
  }

  Future<Map?> _processRun(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    String imageName = _getParameter(parameters, json, 'image');
    String? version = _getParameter(parameters, json, 'version');
    String? imageArgsEncoded = _getParameter(parameters, json, 'imageArgs');
    String? name = _getParameter(parameters, json, 'name');
    String? portsLine = _getParameter(parameters, json, 'ports');
    String? network = _getParameter(parameters, json, 'network');
    String? hostname = _getParameter(parameters, json, 'hostname');
    String? environmentLine = _getParameter(parameters, json, 'environment');
    String? volumesLine = _getParameter(parameters, json, 'volumes');
    String? cleanContainer = _getParameter(parameters, json, 'cleanContainer');

    String? healthCmd = _getParameter(parameters, json, 'healthCmd');
    String? healthInterval = _getParameter(parameters, json, 'healthInterval');
    String? healthRetries = _getParameter(parameters, json, 'healthRetries');
    String? healthStartPeriod =
        _getParameter(parameters, json, 'healthStartPeriod');
    String? healthTimeout = _getParameter(parameters, json, 'healthTimeout');

    String? restart = _getParameter(parameters, json, 'restart');

    String? outputAsLines = _getParameter(parameters, json, 'outputAsLines');
    String? outputLimit = _getParameter(parameters, json, 'outputLimit');

    var ports = isNotEmptyString(portsLine) ? portsLine!.split(',') : null;

    var environment = decodeQueryString(environmentLine);

    var volumes = decodeQueryString(volumesLine);

    List<String>? imageArgs;
    if (isNotEmptyString(imageArgsEncoded)) {
      imageArgs = parseJSON(imageArgsEncoded);
    }

    var runner = await _dockerHostLocal!.run(imageName,
        version: version,
        imageArgs: imageArgs,
        containerName: name,
        ports: ports,
        network: network,
        hostname: hostname,
        environment: environment,
        volumes: volumes,
        cleanContainer: parseBool(cleanContainer)!,
        healthCmd: healthCmd,
        healthInterval: _parseDurationInMs(healthInterval),
        healthRetries: parseInt(healthRetries),
        healthStartPeriod: _parseDurationInMs(healthStartPeriod),
        healthTimeout: _parseDurationInMs(healthTimeout),
        restart: restart,
        outputAsLines: parseBool(outputAsLines),
        outputLimit: parseInt(outputLimit));

    return {
      'instanceID': runner.instanceID,
      'containerName': runner.containerName,
      'id': runner.id,
    };
  }

  Future<Map?> _processExec(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    _log.info('_processExec> parameters: $parameters');

    String cmd = _getParameter(parameters, json, 'cmd');
    String? argsEncoded = _getParameter(parameters, json, 'args');
    String containerName = _getParameter(parameters, json, 'name');
    String? outputAsLines = _getParameter(parameters, json, 'outputAsLines');
    String? outputLimit = _getParameter(parameters, json, 'outputLimit');

    var args = _decodeArgsOfStrings(argsEncoded)!;

    var dockerProcess = await _dockerHostLocal!.exec(
      containerName,
      cmd,
      args,
      outputAsLines: parseBool(outputAsLines),
      outputLimit: parseInt(outputLimit),
    );

    if (dockerProcess == null) return null;

    return {
      'instanceID': dockerProcess.instanceID,
      'containerName': dockerProcess.containerName,
    };
  }

  Future<Map?> _processCommand(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    String cmd = _getParameter(parameters, json, 'cmd');
    String? argsEncoded = _getParameter(parameters, json, 'args');
    String? outputAsLines = _getParameter(parameters, json, 'outputAsLines');
    String? outputLimit = _getParameter(parameters, json, 'outputLimit');

    var args = _decodeArgsOfStrings(argsEncoded)!;

    var dockerProcess = await _dockerHostLocal!.command(
      cmd,
      args,
      outputAsLines: parseBool(outputAsLines)!,
      outputLimit: parseInt(outputLimit),
    );

    return {'instanceID': dockerProcess.instanceID};
  }

  List? _decodeArgs(String? argsEncoded) {
    if (isNotEmptyString(argsEncoded)) {
      var list = parseJSON(argsEncoded) as List;
      return list;
    }
    return null;
  }

  List<String>? _decodeArgsOfStrings(String? argsEncoded) {
    if (isNotEmptyString(argsEncoded)) {
      var list = parseJSON(argsEncoded) as List;
      return list.cast<String>().toList();
    }
    return null;
  }

  Map<String, dynamic>? _decodeProperties(String? argsEncoded) {
    if (isNotEmptyString(argsEncoded)) {
      var map = parseJSON(argsEncoded) as Map;
      return map.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  Future<bool> _processWaitReady(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;

    var instanceID = _getParameterAsInt(parameters, json, 'instanceID');

    var runner = _dockerHostLocal!.getProcessByInstanceID(instanceID);
    runner ??= _dockerHostLocal!.getRunnerByInstanceID(instanceID);
    if (runner == null) return false;

    var ok = await runner.waitReady();
    return ok;
  }

  Future<int?> _processWaitExit(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    var instanceID = _getParameterAsInt(parameters, json, 'instanceID');
    var timeoutMs = _getParameterAsInt(parameters, json, 'timeout');

    var runner = _dockerHostLocal!.getProcessByInstanceID(instanceID);
    runner ??= _dockerHostLocal!.getRunnerByInstanceID(instanceID);
    if (runner == null) return null;

    var timeout = timeoutMs != null ? Duration(milliseconds: timeoutMs) : null;

    var code = await runner.waitExit(timeout: timeout);
    return code;
  }

  Future<bool> _processStop(
      HttpRequest request, Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return false;

    var name = _getParameter(parameters, json, 'name');
    var timeout = _getParameterAsInt(parameters, json, 'timeout');

    var timeoutDuration =
        timeout != null && timeout > 0 ? Duration(seconds: timeout) : null;

    var ok = await _dockerHostLocal!.stopByName(
      name,
      timeout: timeoutDuration,
    );
    return ok;
  }

  Future<Map?> _processOutput(HttpRequest request, String type,
      Map<String, String> parameters, json) async {
    if (_dockerHostLocal == null) return null;

    var instanceID = _getParameterAsInt(parameters, json, 'instanceID');
    var realOffset = _getParameterAsInt(parameters, json, 'realOffset');

    var process = _dockerHostLocal!.getProcessByInstanceID(instanceID);
    process ??= _dockerHostLocal!.getRunnerByInstanceID(instanceID);

    if (process == null) return {'running': false};

    var output = type == 'stderr' ? process.stderr! : process.stdout!;

    var length = output.entriesLength;
    var removed = output.entriesRemoved;
    var entries = output.getEntries(realOffset: realOffset);
    var exitCode = process.exitCode;

    return {
      'running': true,
      'length': length,
      'removed': removed,
      'entries': entries,
      'exit_code': exitCode,
    };
  }

  @override
  String toString() {
    return 'DockerHostServer{listenPort: $listenPort, public: $public, ipv6: $ipv6}';
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
