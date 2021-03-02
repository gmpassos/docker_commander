import 'package:docker_commander/docker_commander_vm.dart';
import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

const int DEFAULT_SERVER_PORT = 8099;

bool _loggerConfigured = false;
void configureLogger() {
  if (_loggerConfigured) return;
  _loggerConfigured = true;

  Logger.root.level = Level.ALL; // defaults to Level.INFO

  Logger.root.onRecord.listen((record) {
    print('${record.time}\t[${record.level.name}]\t${record.message}');

    if (record.error != null) {
      print(record.error);
    }

    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  });
}

void showHelp() {
  print(
      '-----------------------------------------------------------------------------');
  print('| docker_commander/server - version ${DockerCommander.VERSION}');
  print(
      '-----------------------------------------------------------------------------');
  print('');
  print('USAGE:\n');
  print(
      '  \$> docker_commander_server %username %password %port? --public --ipv6');
  print('');
  print('## Default Server port: $DEFAULT_SERVER_PORT');
  print('');
}

void main(List<String> args) async {
  print('ARGS: $args');

  if (args.length < 2) {
    showHelp();
    return;
  }

  configureLogger();

  var public = args.contains('--public');
  var ipv6 = args.contains('--ipv6');

  args.removeWhere((a) => a.startsWith('--'));

  var username = args[0];
  var password = args[1];

  if (isEmptyString(username, trim: true) ||
      isEmptyString(password, trim: true)) {
    showHelp();
    return;
  }

  var port = args.length > 2 && isInt(args[2])
      ? parseInt(args[2], DEFAULT_SERVER_PORT)
      : DEFAULT_SERVER_PORT;

  var authenticationTable = AuthenticationTable({username: password});
  print('authenticationTable');
  print('- username $username');

  var hostServer = DockerHostServer(
    (user, pass) async => authenticationTable.checkPassword(user, pass),
    port,
    public: public,
    ipv6: ipv6,
  );

  await hostServer.startAndWait();

  print('RUNNING $hostServer');
}
