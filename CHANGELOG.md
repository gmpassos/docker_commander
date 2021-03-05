## 1.0.20

- `Dockerfile`: `--server` and `--console` modes.
- `README.md`: improved Docker image usage.

## 1.0.19

- Improve console commands.
- Dart 2.12.0+ compliant: change DockerFile to use `dart run` instead of `dart pub run`.

## 1.0.18

- Added executable `docker_commander_console`: a console terminal to control a `docker_commander_server`.
- Fix `DockerHostRemote` output consumer.
- README: Improve Docker Image usage.
- Dart 2.12.0+ compliant: `dartfmt` and `dartanalyzer`.
- swiss_knife: ^2.5.26
- mercury_client: ^1.1.19

## 1.0.17

- `docker_commander_server.dart`: better console output.
- Fixed `path` dependency.
- README: Added Docker Image usage.

## 1.0.16

- Improve live mapping of hosts in the same network: avoid mapping of already mapped hosts. 
- Added executable `docker_commander_server`.
- Added Dockerfile for Docker Hub integration and `docker_commander/server` image.
- Fixed server response issue to encode UTF-8 characters.

## 1.0.15

- Added support to containers and services logs.
- `DockerProcess`: now has a `dispose` method, to finish any stdout/stderr consumer/client.

## 1.0.14

- Force usage of `cidfile` for better id resolution.
- Add Swarm mode and Services support.
- Added Swarm tests.

## 1.0.13

- Add support to create a container and start it.
- Add volume parameters for `run` and `createContainer`.

## 1.0.12

- Improve example.
- Improve README.
- Improve documentation.
- Fix typo.

## 1.0.11

- Improve NGINX integration.
- Improve README.
- `DockerHostRemote`: ensure that `waitReady` is called in initialization.

## 1.0.10

- `NginxContainer`: NGINX container with a `NginxReverseProxyConfigurer`.
- Added support to include in each container of the same network the IP of other hosts.
- Added command helpers `execShell`, `putFile` and `appendFile`. 
- Added helpers to wait data in stdout/stderr: `waitData` `waitForDataMatch`.
- Fix remote operations: `wait_ready` and `wait_exit`.

## 1.0.9

- `DockerHost.run` and `DockerHost.exec`: 
  - exposed parameter `outputReadyType`.
- Fixed `DockerProcessRemote` and `DockerRunnerRemote` to use
  local resolution of output ready state.
- Fixed sync of outputs of `DockerProcessRemote`:
  - now retries in case of network error and also finalizes sync loop,
    also checking if `DockerProcessRemote` was finished.
- Fixed read of `--cidfile`: now waits for the CID file to exist.
- Added `ApacheHttpdContainer` example to `README.md`.

## 1.0.8

- Fix `stop` command for `DockerHostRemote` and `DockerHostServer`.

## 1.0.7

- Added support for Docker exec.
  - `DockerProcess`: to handle `exec` calls.
  - `execWhich`: to facilitate binary path resolution inside containers.
  - `execCat`: to `cat` a file inside the container.
- Added `ApacheHttpdContainer`, to run a pre-configure Apache HTTPD.
- Improved `Output` and `OutputStream`:
  - Correctly detects that associated `DockerProcess` exited.
  - Improved ready state with `OutputReadyType`.
  - `DockerHostRemote`: `OutputClient` now sleeps when sync doesn't receive data,
    to reduce number of calls.
    
## 1.0.6

- Change libraries:
  - `docker_commander.dart`: standard and portable, even works in the browser through `DockerHostRemote`.
  - `docker_commander_vm.dart`: VM exclusive features, like `DockerHostLocal` and `DockerHostServer`.
- Fix Server token validation and ensure authentication in all operations. 

## 1.0.5

- Fix libraries names.

## 1.0.4

- Fix library exports.
- Added `timeout` parameters to stop methods.
- Organize imports.
- Improved README.md examples.

## 1.0.3

- Added support to be used in the browser (only with `DockerHostRemote`).
- `DockerHost.run()` new parameters:
  - imageArgs
  - ports
  - network
  - hostname
  - environment
- Added `DockerContainerConfig`, for pre-configured containers.
- Added `PostgreSQLContainer`, using pre-configured `DockerContainerConfig`.

## 1.0.2

- Added `DockerHostRemote` and `DockerHostServer`.
- `DockerHost`:
  - getRunnersInstanceIDs
  - getRunnersNames
  - getRunnerByInstanceID
  - getRunnerByName
  - stopByInstanceID
  - stopByName
  - stopRunners
- `DockerRunner`: 
  - isRunning
- Tests now runs with `loca` and `remote` contexts. 

## 1.0.1

- Fix README.

## 1.0.0

- Initial version.
