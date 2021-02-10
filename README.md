# docker_commander

[![pub package](https://img.shields.io/pub/v/docker_commander.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/docker_commander)
[![CI](https://img.shields.io/github/workflow/status/gmpassos/docker_commander/Dart%20CI/master?logo=github-actions&logoColor=white)](https://github.com/gmpassos/docker_commander/actions)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/docker_commander?logo=git&logoColor=white)](https://github.com/gmpassos/docker_commander/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/docker_commander/latest?logo=git&logoColor=white)](https://github.com/gmpassos/docker_commander/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/docker_commander?logo=git&logoColor=white)](https://github.com/gmpassos/docker_commander/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/docker_commander?logo=github&logoColor=white)](https://github.com/gmpassos/docker_commander/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/docker_commander?logo=github&logoColor=white)](https://github.com/gmpassos/docker_commander)
[![License](https://img.shields.io/github/license/gmpassos/docker_commander?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/docker_commander/blob/master/LICENSE)

Docker manager, for personalized containers and pre-configured popular containers.

## Usage

Here's a simple usage example:

```dart
import 'package:docker_commander/docker_commander.dart';
import 'package:docker_commander/src/docker_commander_host_io.dart';

void main() async {
  // Creates a `DockerCommander` for local host machine:
  var dockerCommander = DockerCommander(DockerHostLocal());
  
  // Initialize `DockerCommander`:
  await dockerCommander.initialize();
  // Ensure that Docker daemon is running.
  await dockerCommander.checkDaemon();

  // Run Docker image `hello-world`:
  var dockerContainer = await dockerCommander.run('hello-world');

  // Waits container to be ready (ensure that the container started).
  await dockerContainer.waitReady();

  /// Waits the container to exit, and gets the exit code:
  var exitCode = await dockerContainer.waitExit();
  
  /// Gets all the STDOUT as [String]. 
  var output = dockerContainer.stdout.asString;
  
  print(output);
  print('EXIT CODE: $exitCode');
}

```

## See Also

See [package docker_commander_test][docker_commander_test], for unit test framework with [Docker][docker] containers.

[docker_commander_test]:https://github.com/gmpassos/docker_commander_test
[docker]:https://www.docker.com/

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/gmpassos/docker_commander/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
