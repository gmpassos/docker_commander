import 'package:docker_commander/src/docker_commander_commands.dart';
import 'package:test/test.dart';

import 'logger_config.dart';

void main() {
  configureLogger();

  group('DockerCMD', () {
    setUp(() async {});

    tearDown(() async {});

    test('parseHostsFile', () async {
      expect(DockerCMD.parseHostsFile(''), isEmpty);
      expect(DockerCMD.parseHostsFile('   '), isEmpty);
      expect(DockerCMD.parseHostsFile('\n'), isEmpty);
      expect(DockerCMD.parseHostsFile('\n\n'), isEmpty);
      expect(DockerCMD.parseHostsFile('   \n#asdasd\n\n'), isEmpty);

      var parse1 = DockerCMD.parseHostsFile('''
127.0.0.1	localhost
::1	localhost ip6-localhost ip6-loopback
fe00::0	ip6-localnet
ff00::0	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters  
      ''');

      expect(parse1.length, equals(6));
      expect(parse1['127.0.0.1'], equals(['localhost']));
      expect(parse1['::1'],
          equals(['localhost', 'ip6-localhost', 'ip6-loopback']));
      expect(parse1['fe00::0'], equals(['ip6-localnet']));
      expect(parse1['ff00::0'], equals(['ip6-mcastprefix']));
      expect(parse1['ff02::1'], equals(['ip6-allnodes']));
      expect(parse1['ff02::2'], equals(['ip6-allrouters']));
      expect(parse1['10.0.0.1'], isNull);

      var parse2 = DockerCMD.parseHostsFile('''
127.0.0.1	localhost
172.25.0.2	apache
      ''');

      expect(parse2.length, equals(2));
      expect(parse2['127.0.0.1'], equals(['localhost']));
      expect(parse2['172.25.0.2'], equals(['apache']));
      expect(parse2['10.0.0.1'], isNull);

      var parse3 = DockerCMD.parseHostsFile('''
127.0.0.1	localhost
#172.25.0.2	apache
      ''');

      expect(parse3.length, equals(1));
      expect(parse3['127.0.0.1'], equals(['localhost']));
      expect(parse3['172.25.0.2'], isNull);
      expect(parse3['10.0.0.1'], isNull);

      var parse4 = DockerCMD.parseHostsFile('''
127.0.0.1	localhost
172.25.0.2	apache # comment x
      ''');

      expect(parse4.length, equals(2));
      expect(parse4['127.0.0.1'], equals(['localhost']));
      expect(parse4['172.25.0.2'], equals(['apache']));
      expect(parse4['10.0.0.1'], isNull);
    });
  });
}
