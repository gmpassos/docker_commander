import 'package:logging/logging.dart';

bool _loggerConfigured = false;
void configureLogger() {
  if (_loggerConfigured) return;
  _loggerConfigured = true;

  Logger.root.level = Level.ALL; // defaults to Level.INFO

  Logger.root.onRecord.listen((record) {
    print('${record.time}\t[${record.level.name}]\t${record.message}');
  });
}

void logTitle(Logger log, String title) {
  log.info('');
  log.info('-----------------------------------------------------------------');
  log.info('| $title');
  log.info('-----------------------------------------------------------------');
  log.info('');
}
