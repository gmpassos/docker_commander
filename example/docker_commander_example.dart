import 'package:docker_commander/docker_commander_vm.dart';

void main() async {
  var dockerCommander = DockerCommander(DockerHostLocal());
  await dockerCommander.initialize();
  await dockerCommander.checkDaemon();

  print(dockerCommander);

  var dockerContainer = await dockerCommander.run('hello-world');

  print(dockerContainer);

  await dockerContainer.waitReady();

  var exitCode = await dockerContainer.waitExit();
  var output = dockerContainer.stdout.asString;

  print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
  print(output);
  print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');

  print('EXIT CODE: $exitCode');
}
