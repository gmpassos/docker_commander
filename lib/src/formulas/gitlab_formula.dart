import 'package:docker_commander/docker_commander.dart';

class GitLabFormulaSource extends DockerCommanderFormulaSource {
  GitLabFormulaSource() : super('dart', r'''
  
  class GitLabFormula {
  
      String getVersion() {
        return '1.0';
      }
    
      void install() {
        cmd('create-network gitlab-net');
        cmd('create-container gitlab gitlab/gitlab-ce latest --ports 80,443 --hostname gitlab --network gitlab-net');
        start();
      }
      
      void installRunner() {
        cmd('create-container gitlab-runner gitlab/gitlab-runner latest --network gitlab-net --volumes /srv/gitlab-runner/config:/etc/gitlab-runner|/var/run/docker.sock:/var/run/docker.sock --restart always');
      }
      
      void registerRunner(String gitlabHost, String token) {
        cmd('docker run --rm -v /srv/gitlab-runner/config:/etc/gitlab-runner gitlab/gitlab-runner register --non-interactive --url http://$gitlabHost/ --registration-token $token --executor docker --docker-image google/dart:latest --description local --docker-network-mode gitlab-net');
      }
      
      void start() {
        cmd('start gitlab');
        startRunner();
      }
     
      void stop() {
        stopRunner();
        cmd('stop gitlab');
      }
      
      void startRunner() {
        cmd('start gitlab-runner');
      }
      
      void stopRunner() {
        cmd('stop gitlab-runner');
      }
      
      void uninstall() {
        stop();
        uninstallRunner();
        cmd('remove-container gitlab --force');
      }
      
      void uninstallRunner() {
        stopRunner();
        cmd('remove-container gitlab-runner --force');
      }
      
   }
   
   ''');
}
