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
