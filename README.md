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

### Local Docker

Here's a simple usage example for a local host machine:

```dart
import 'package:docker_commander/docker_commander_vm.dart';

void main() async {
  // Creates a `DockerCommander` for a local host machine:
  var dockerCommander = DockerCommander(DockerHostLocal());
  
  // Initialize `DockerCommander`:
  await dockerCommander.initialize();
  // Ensure that Docker daemon is running.
  await dockerCommander.checkDaemon();

  // Run Docker image `hello-world`:
  var dockerContainer = await dockerCommander.run('hello-world');

  // Waits container to be ready (ensure that the container started).
  await dockerContainer.waitReady();

  // Waits the container to exit, and gets the exit code:
  var exitCode = await dockerContainer.waitExit();
  
  // Gets all the STDOUT as [String]. 
  var output = dockerContainer.stdout.asString;
  
  print(output);
  print('EXIT CODE: $exitCode');
}

```


### Remote Docker

Here's another usage example for a remote host machine:

#### Server

Start `DockerHostServer`:

```dart
import 'package:docker_commander/docker_commander_vm.dart';

void main() async {
  
  // A simple username and password table:
  var authenticationTable = AuthenticationTable({'admin': '123'});

  // A `DockerHost` Server at port 8099:
  var hostServer = DockerHostServer(
          (user, pass) async => authenticationTable.checkPassword(user, pass),
      8099);

  // Starts the server and wait initialization:
  await hostServer.startAndWait();
  
}

```

#### Client

Client side using `DockerHostRemote`:

```dart
import 'package:docker_commander/docker_commander_vm.dart';

void main() async {

  // Connect to a `DockerHost` running at '10.0.0.52:8099'
  var dockerHostRemote = DockerHostRemote('10.0.0.52', 8099, username: 'admin', password: '123');

  // Creates a `DockerCommander` for a remote host machine:
  var dockerCommander = DockerCommander(dockerHostRemote);
  
  // Initialize `DockerCommander` (at remote server):
  await dockerCommander.initialize();
  // Ensure that Docker daemon is running (at remote server):
  await dockerCommander.checkDaemon();

  // Run Docker image `hello-world` (at remote server):
  var dockerContainer = await dockerCommander.run('hello-world');

  // Behavior is the same of example using `DockerHostLocal`.
  // Internal `DockerRunner` will sync remote output automatically!

  // ...
  
  // Gets all the STDOUT as [String]. 
  var output = dockerContainer.stdout.asString;
  print(output);
  
  // ...
  
}

```

## PostgreSQLContainer

A pre-configured PostgreSQL Container:

```dart
import 'package:docker_commander/docker_commander_vm.dart';

void main() async {

  // Creates a `DockerCommander` for a local host machine:
  var dockerCommander = DockerCommander(DockerHostLocal());
  
  // Start PostgreSQL container:
  var dockerContainer = await PostgreSQLContainer().run(dockerCommander);

  // Wait PostgreSQL to start and be ready to receive requests:
  await dockerContainer.waitReady();

  // Print the current STDOUT of the container:
  var output = dockerContainer.stdout.asString;
  print(output);

  // Execute inside the container a `psql` command:
  var execPsql = await dockerContainer.exec('/usr/bin/psql',
      ['-d','postgres', '-U','postgres', '-c','\\l']);

  // Wait command to execute:
  var execPsqlExitCode = await execPsql.waitExit();

  // Command output:
  print( execPsql.stdout.asString );
  
  // Stops PostgreSQL, with a timeout of 20s:
  await dockerContainer.stop(timeout: Duration(seconds: 20));

  // Wait PostgreSQL to exit and get exit code:
  var exitCode = await dockerContainer.waitExit();

  // ...

}

```

## ApacheHttpdContainer

A pre-configured container for the famous Apache HTTPD:

```dart
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:mercury_client/mercury_client.dart';

void main() async {
    var dockerCommander = DockerCommander(DockerHostLocal());
  
    // The host port to map internal container port (httpd at port 80).
    var apachePort = 8081;
    
    var dockerContainer = await ApacheHttpdContainer()
        .run(dockerCommander, hostPorts: [apachePort]);
    
    // Wait Apache to be ready...
    await dockerContainer.waitReady();

    // Get HTTPD configuration file:
    var httpdConf = await dockerContainer.execCat('/usr/local/apache2/conf/httpd.conf');

    // Get the host port of Apache HTTPD.
    var hostPort = dockerContainer.hostPorts[0];
    // Request a HTTP GET using hostPort:
    var response = await HttpClient('http://localhost:$hostPort/').get('index.html');
    
    // The body of the response
    var content = response.bodyAsString;
    print(content);
    
    // Stop Apache HTTPD:
    await dockerContainer.stop(timeout: Duration(seconds: 5));

}

```

## See Also

See [package docker_commander_test][docker_commander_test], for unit test framework with [Docker][docker] containers.

Thanks to [isoos@GitHub][github_isoos], author of the precursor package `docker_process`, that was substituted by this one. 

[docker_commander_test]:https://github.com/gmpassos/docker_commander_test
[docker]:https://www.docker.com/
[github_isoos]: https://github.com/isoos

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/gmpassos/docker_commander/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github_gmp].

[github_gmp]: https://github.com/gmpassos

## License

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
