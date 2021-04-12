import 'package:docker_commander/docker_commander.dart';

class ApacheFormulaSource extends DockerCommanderFormulaSource {
  ApacheFormulaSource() : super('dart', '''
  
  class ApacheFormula {
  
      String getVersion() {
        return '1.0';
      }
    
      void install() {
        cmd('create-container apache httpd latest --port 80 --hostname apache');
        start();
      }
      
      void start() {
        cmd('start apache');
      }
      
      void stop() {
        cmd('stop apache');
      }
      
      void uninstall() {
        stop();
        cmd('remove-container apache --force');
      }
      
   }
   
   ''');
}
