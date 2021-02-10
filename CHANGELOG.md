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
