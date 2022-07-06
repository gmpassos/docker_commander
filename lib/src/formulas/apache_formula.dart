import '../docker_commander_formulas.dart';

class ApacheFormulaSource extends DockerCommanderFormulaSource {
  ApacheFormulaSource() : super('dart', r'''
  
  class ApacheFormula {
  
      String name = 'apache';
      String hostname = 'apache';
      int port = 80;
  
      String getVersion() {
        return '1.1';
      }
    
      void install() {
        cmd('create-container $name httpd latest --port $port --hostname $hostname');
        start();
      }
      
      void start() {
        cmd('start $name');
      }
      
      void stop() {
        cmd('stop $name');
      }
      
      void uninstall() {
        stop();
        cmd('remove-container $name --force');
      }
      
   }
   
   ''');
}
