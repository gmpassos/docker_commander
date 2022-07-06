import '../docker_commander_formulas.dart';

class GitLabFormulaSource extends DockerCommanderFormulaSource {
  GitLabFormulaSource() : super('dart', r'''
  
  class GitLabFormula {
  
      String imageGitlab = 'gitlab/gitlab-ce';
      String imageGitlabRunner = 'gitlab/gitlab-runner'; 
      String imageRunner = 'google/dart';
      
      String network = 'gitlab-net';
      String hostGitlabConfigPath = '/srv/gitlab-runner/config';
      
      String getVersion() {
        return '1.0';
      }
    
      void pull() {
        cmd('docker pull $imageGitlab:latest');
      }
      
      void pullRunner() {
        cmd('docker pull $imageGitlabRunner:latest');
        cmd('docker pull $imageRunner:latest');
      }
    
      void install() {
        pull();
        cmd('create-network $network');
        cmd('create-container gitlab $imageGitlab latest --ports 80,443 --hostname gitlab --network $network');
        start();
      }
      
      void installRunner() {
        pullRunner();
        cmd('create-container gitlab-runner $imageGitlabRunner latest --network $network --volumes $hostGitlabConfigPath:/etc/gitlab-runner|/var/run/docker.sock:/var/run/docker.sock --restart always');
      }
      
      void registerRunner(String gitlabHost, String token) {
        cmd('docker run --rm --net $network -v $hostGitlabConfigPath:/etc/gitlab-runner $imageGitlabRunner register --non-interactive --url http://$gitlabHost/ --registration-token $token --executor docker --docker-image $imageRunner:latest --description local --docker-network-mode $network');
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
