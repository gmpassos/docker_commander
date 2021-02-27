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
