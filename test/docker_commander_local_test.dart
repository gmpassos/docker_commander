@Timeout(Duration(minutes: 2))
@TestOn('vm')
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:test/test.dart';

import 'docker_commander_test_basics.dart';
import 'logger_config.dart';

void main() {
  configureLogger();

  doBasicTests((listenPort) => DockerHostLocal());
}
