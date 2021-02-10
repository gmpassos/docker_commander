import 'package:docker_commander/src/docker_commander_local.dart';
import 'package:logging/logging.dart';

import 'docker_commander_test_basics.dart';

void main() {
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.time}\t[${record.level.name}]\t${record.message}');
  });

  doBasicTests(() => DockerHostLocal());
}
