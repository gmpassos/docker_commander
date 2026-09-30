@Timeout(Duration(minutes: 2))
@TestOn('vm')
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:swiss_knife/swiss_knife.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

void main() {
  configureLogger();

  group('DockerCommander Console', () {
    test('ConsoleCMD.parse: create-container', () {
      var cmd = ConsoleCMD.parse(
          'create-container apache httpd latest 80 --hostname apache --environment a=1|b=2 --cleanContainer');

      expect(cmd!.cmd, equals('createcontainer'));
      expect(cmd.args, equals(['apache', 'httpd', 'latest', '80']));
      expect(
          cmd.properties,
          equals(sortMapEntries({
            'hostname': 'apache',
            'cleancontainer': 'true',
            'environment': 'a=1|b=2',
          })));
    });

    test('ConsoleCMD.parse: create-container with run options', () {
      var cmd = ConsoleCMD.parse('create-container db postgres 16 '
          '--tmpfs /data=rw,size=64m|/tmp --labels owner=tests|env=ci '
          '--shm-size 256m --init --stop-timeout 3000 --pull missing '
          '--add-hosts api=10.0.0.5');

      expect(cmd!.args, equals(['db', 'postgres', '16']));

      var options = DockerRunOptions.fromProperties(cmd.properties);
      expect(
          options.toArgs(),
          equals([
            '--tmpfs', '/data:rw,size=64m', //
            '--tmpfs', '/tmp',
            '--shm-size', '256m',
            '--init',
            '--stop-timeout', '3',
            '--pull', 'missing',
            '--label', 'owner=tests',
            '--label', 'env=ci',
            '--add-host', 'api:10.0.0.5',
          ]));
    });

    test('ConsoleCMD.parse: start', () {
      var cmd = ConsoleCMD.parse('start foo');

      expect(cmd!.cmd, equals('start'));
      expect(cmd.args, equals(['foo']));
      expect(cmd.properties, isEmpty);
    });

    test('ConsoleCMD.parse: stop', () {
      var cmd = ConsoleCMD.parse('stop foo');

      expect(cmd!.cmd, equals('stop'));
      expect(cmd.args, equals(['foo']));
      expect(cmd.properties, isEmpty);
    });
  });
}
