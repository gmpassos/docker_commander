# docker_commander

[![pub package](https://img.shields.io/pub/v/docker_commander.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/docker_commander)
[![CI](https://img.shields.io/github/workflow/status/gmpassos/docker_commander/Dart%20CI/master?logo=github-actions&logoColor=white)](https://github.com/gmpassos/docker_commander/actions)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/docker_commander?logo=git&logoColor=white)](https://github.com/gmpassos/docker_commander/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/docker_commander/latest?logo=git&logoColor=white)](https://github.com/gmpassos/docker_commander/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/docker_commander?logo=git&logoColor=white)](https://github.com/gmpassos/docker_commander/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/docker_commander?logo=github&logoColor=white)](https://github.com/gmpassos/docker_commander/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/docker_commander?logo=github&logoColor=white)](https://github.com/gmpassos/docker_commander)
[![License](https://img.shields.io/github/license/gmpassos/docker_commander?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/docker_commander/blob/master/LICENSE)

[Docker][docker] manager to easily automate a Docker Daemon:
  - Supports personalized containers. 
  - Helpers to build a Docker network.
  - Helpers to manipulate files inside a running container.
  - Built-in pre-configured popular containers:
    - [PostgreSQL][postgresql]
    - [Apache HTTPD][apache]
    - [NGINX][nginx]

[docker]:https://www.docker.com/

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

  // The behavior is the same of the example using `DockerHostLocal`.
  // The internal `DockerRunner` will sync remote output (stdout/sdterr) automatically!

  // ...
  
  // Gets all the STDOUT as [String]. 
  var output = dockerContainer.stdout.asString;
  print(output);
  
  // ...
  
}

```

## PostgreSQLContainer

A pre-configured [PostgreSQL][postgresql] Container:

```dart
import 'package:docker_commander/docker_commander_vm.dart';

void main() async {

  // Creates a `DockerCommander` for a local host machine:
  var dockerCommander = DockerCommander(DockerHostLocal());
  // Initialize `DockerCommander`:
  await dockerCommander.initialize();
  
  // Start PostgreSQL container:
  var dockerContainer = await PostgreSQLContainer().run(dockerCommander);

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

[postgresql]:https://www.postgresql.org/

## ApacheHttpdContainer

A pre-configured container for the famous [Apache HTTPD][apache]:

```dart
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:mercury_client/mercury_client.dart';

void main() async {
    var dockerCommander = DockerCommander(DockerHostLocal());
    // Initialize `DockerCommander`:
    await dockerCommander.initialize();
    
    // The host port to map internal container port (httpd at port 80).
    var apachePort = 8081;
    
    var dockerContainer = await ApacheHttpdContainer()
        .run(dockerCommander, hostPorts: [apachePort]);
    
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

[apache]:https://httpd.apache.org/

## NginxContainer

A pre-configured container for the famous [NGINX][nginx] proxy server.

This example shows a [NGINX][nginx] reverse proxy, that redirects HTTP requests at `localhost:4082`
to the internal Apache container, with hostname `apache`, at port `80`.

```dart
import 'package:docker_commander/docker_commander_vm.dart';
import 'package:mercury_client/mercury_client.dart';

void main() async {
  var dockerCommander = DockerCommander(DockerHostLocal());
  // Initialize `DockerCommander`:
  await dockerCommander.initialize();

  // Docker Network for Apache HTTPD and NGINX containers:
  var network = await dockerCommander.createNetwork();

  // Start Apache HTTPD, mapping port 80 to 4081.
  var apacheContainer = await ApacheHttpdContainer().run(dockerCommander,
      hostPorts: [4081], network: network, hostname: 'apache');

  // Generate a NGINX configuration, mapping domain `localhost` to
  // docker host `apache` at port 80 (without HTTPS).
  var nginxConfig = NginxReverseProxyConfigurer(
      [NginxServerConfig('localhost', 'apache', 80, false)]).build();

  // Start a NGINX container using generated configuration.
  var nginxContainer = await NginxContainer(nginxConfig, hostPorts: [4082])
      .run(dockerCommander, network: network, hostname: 'nginx');

  // Request apache:80 (mapped in the host machine to localhost:4081)
  // trough NGINX reverse proxy at localhost:4082
  var response = await HttpClient('http://localhost:4082/').get('');

  // The Apache HTTPD response content:
  var apacheContent = response.bodyAsString;

  print(apacheContent);

  // Stop NGINX:
  await nginxContainer.stop(timeout: Duration(seconds: 5));

  // Apache Apache HTTPD:
  await apacheContainer.stop(timeout: Duration(seconds: 5));

  // Remove Docker network:
  await dockerCommander.removeNetwork(network);
}
```

[nginx]:https://www.nginx.com/

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
