import 'package:logging/logging.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_containers.dart';
import 'docker_commander_host.dart';

final _log = Logger('docker_commander/NginxContainer');

class DockerContainerNginx extends DockerContainer {
  final NginxContainer containerConfig;

  DockerContainerNginx(DockerRunner runner, this.containerConfig)
      : super(runner);

  String get config => containerConfig.config;

  String get configPath => containerConfig.configPath;

  Future<bool> testConfiguration() async {
    var nginxBin = await execWhich('nginx');
    var processTestConfig = await exec(nginxBin!, ['-t']);
    var testConfigExit = await processTestConfig!.waitExitAndConfirm(0);
    return testConfigExit;
  }

  Future<bool> reloadConfiguration() async {
    var nginxBin = await execWhich('nginx');
    var reloadExit = await execAndWaitExit(nginxBin!, ['-s', 'reload']);
    return reloadExit == 0;
  }
}

/// NGINX pre-configured container.
class NginxContainer extends DockerContainerConfig<DockerContainerNginx> {
  final String config;

  final String configPath;

  NginxContainer(this.config, {List<int>? hostPorts, String? configPath})
      : configPath = configPath ?? '/etc/nginx/nginx.conf',
        super(
          'nginx',
          version: 'latest',
          hostPorts: hostPorts,
          containerPorts: [80],
          outputAsLines: true,
          stdoutReadyFunction: (output, line) =>
              line.contains('Configuration complete; ready for start up'),
        );

  @override
  DockerContainerNginx instantiateDockerContainer(DockerRunner runner) =>
      DockerContainerNginx(runner, this);

  @override
  Future<bool> initializeContainer(DockerContainerNginx dockerContainer) async {
    if (isEmptyString(config)) return true;

    var putOK =
        await dockerContainer.putFileContent(configPath, config, sudo: true);
    if (!putOK) {
      _log.severe(
          "Can't put int container `${dockerContainer.name}` config file at: $configPath");
      return false;
    }

    var testOK = await dockerContainer.testConfiguration();
    if (!testOK) {
      _log.severe(
          'Nginx configuration test failed! container: `${dockerContainer.name}` ; path: $configPath');
      return false;
    }

    var reloadOK = await dockerContainer.reloadConfiguration();
    if (!reloadOK) {
      _log.severe(
          'Error reloading NGINX configuration! container: `${dockerContainer.name}` ; path: $configPath');
      return false;
    }

    // Some delay to reload NGINX configuration.
    await Future.delayed(Duration(seconds: 1));

    return true;
  }
}

/// NGINX reverse proxy configurer.
class NginxReverseProxyConfigurer {
  static const String _templateMain = '''

user                 nginx;
pid                  /var/run/nginx.pid;
worker_processes     auto;
worker_rlimit_nofile 65535;

events {
    multi_accept       on;
    worker_connections 65535;
}

http {
    charset                utf-8;
    sendfile               on;
    tcp_nopush             on;
    tcp_nodelay            on;
    server_tokens          off;
    log_not_found          off;
    types_hash_max_size    2048;
    types_hash_bucket_size 64;
    client_max_body_size   16M;

    # MIME
    include                /etc/nginx/mime.types;
    default_type           application/octet-stream;

    # Logging
    access_log             /var/log/nginx/access.log;
    error_log              /var/log/nginx/error.log warn;

    # SSL
    ssl_session_timeout    1d;
    ssl_session_cache      shared:SSL:10m;
    ssl_session_tickets    off;

    # Diffie-Hellman parameter for DHE ciphersuites
    ssl_dhparam            /etc/nginx/dhparam.pem;

    # Mozilla Intermediate configuration
    ssl_protocols          TLSv1.2 TLSv1.3;
    ssl_ciphers            ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    # OCSP Stapling
    ssl_stapling           on;
    ssl_stapling_verify    on;
    resolver               1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 208.67.222.222 208.67.220.220 valid=60s;
    resolver_timeout       2s;

    # Connection header for WebSocket reverse proxy
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ""      close;
    }
    
    @include_servers@

}

''';

  static const String _templateProxy = r'''
  
        proxy_http_version                 1.1;
        proxy_cache_bypass                 $http_upgrade;
        
        # Proxy headers
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        $connection_upgrade;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-Port  $server_port;
        
        # Proxy timeouts
        proxy_connect_timeout              60s;
        proxy_send_timeout                 60s;
        proxy_read_timeout                 60s;

''';

  static const String _templateSecurity = r'''

      # security headers
      add_header X-Frame-Options           "SAMEORIGIN" always;
      add_header X-XSS-Protection          "1; mode=block" always;
      add_header X-Content-Type-Options    "nosniff" always;
      add_header Referrer-Policy           "no-referrer-when-downgrade" always;
      add_header Content-Security-Policy   "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
      
      # . files
      location ~ /\.(?!well-known) {
          deny all;
      }

''';

  static const String _templateLetsEncryptChallenge = r'''

      # ACME-challenge
      location ^~ /.well-known/acme-challenge/ {
          root /var/www/_letsencrypt;
      }

''';

  static const String _templateGeneral = r'''

      # favicon.ico
      location = /favicon.ico {
          log_not_found off;
          access_log    off;
      }
      
      # robots.txt
      location = /robots.txt {
          log_not_found off;
          access_log    off;
      }
      
      # assets, media
      location ~* \.(?:css(\.map)?|js(\.map)?|jpe?g|png|gif|ico|cur|heic|webp|tiff?|mp3|m4a|aac|ogg|midi?|wav|mp4|mov|webm|mpe?g|avi|ogv|flv|wmv)$ {
          expires    7d;
          access_log off;
      }
      
      # svg, fonts
      location ~* \.(?:svgz?|ttf|ttc|otf|eot|woff2?)$ {
          add_header Access-Control-Allow-Origin "*";
          expires    7d;
          access_log off;
      }
      
      # gzip
      gzip              on;
      gzip_vary         on;
      gzip_proxied      any;
      gzip_comp_level   4;
      gzip_types        text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
      
''';

  static const String _templateServerHTTPS = r'''
  
  server {
      listen                  443 ssl http2;
      listen                  [::]:443 ssl http2;
      server_name             @domain@;
      
      # SSL
      ssl_certificate         /etc/letsencrypt/live/@domain@/fullchain.pem;
      ssl_certificate_key     /etc/letsencrypt/live/@domain@/privkey.pem;
      ssl_trusted_certificate /etc/letsencrypt/live/@domain@/chain.pem;
  
      # security
      @template_security@
  
      # reverse proxy
      location / {
          proxy_pass http://@container_host@:@container_port@;
          @template_proxy@
      }
  
      # additional config
      @template_general@
  }
  
  # HTTP redirect to HTTPS
  server {
      listen      80;
      listen      [::]:80;
      server_name @domain@;
      @template_letsencrypt_challenge@
  
      location / {
          return 301 https://@domain@$request_uri;
      }
  }

''';

  static const String _templateServerHTTP = r'''
  
  server {
      listen      80;
      listen      [::]:80;
      server_name @domain@;
      
      # security
      @template_security@
      
      # reverse proxy
      location / {
          proxy_pass http://@container_host@:@container_port@;
          @template_proxy@
      }
  
      # additional config
      @template_general@
  }

''';

  final Set<NginxServerConfig> _servers;

  NginxReverseProxyConfigurer(Iterable<NginxServerConfig> servers)
      : _servers = Set.from(servers);

  String _buildTemplateServerHTTPS(NginxServerConfig serverConfig) {
    var template =
        _templateServerHTTPS.replaceAll('@domain@', serverConfig.domain);
    template = template.replaceAll('@template_security@', _templateSecurity);
    template = template.replaceAll('@template_proxy@', _templateProxy);
    template = template.replaceAll('@template_general@', _templateGeneral);
    template = template.replaceAll(
        '@template_letsencrypt_challenge@', _templateLetsEncryptChallenge);

    template =
        template.replaceAll('@container_host@', serverConfig.containerHost);
    template = template.replaceAll(
        '@container_port@', '${serverConfig.containerPort}');

    return template;
  }

  String _buildTemplateServerHTTP(NginxServerConfig serverConfig) {
    var template =
        _templateServerHTTP.replaceAll('@domain@', serverConfig.domain);
    template = template.replaceAll('@template_security@', _templateSecurity);
    template = template.replaceAll('@template_proxy@', _templateProxy);
    template = template.replaceAll('@template_general@', _templateGeneral);

    template =
        template.replaceAll('@container_host@', serverConfig.containerHost);
    template = template.replaceAll(
        '@container_port@', '${serverConfig.containerPort}');

    return template;
  }

  String _buildTemplateMain(List<NginxServerConfig> servers) {
    var serversConfigText = servers
        .map((s) => s.https
            ? _buildTemplateServerHTTPS(s)
            : _buildTemplateServerHTTP(s))
        .join('\n\n');
    var template =
        _templateMain.replaceAll('@include_servers@', serversConfigText);
    return template;
  }

  String build() {
    return _buildTemplateMain(_servers.toList());
  }
}

class NginxServerConfig {
  final String domain;
  final String containerHost;
  final int containerPort;
  final bool https;

  NginxServerConfig(
      this.domain, this.containerHost, this.containerPort, this.https);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NginxServerConfig &&
          runtimeType == other.runtimeType &&
          domain == other.domain;

  @override
  int get hashCode => domain.hashCode;
}
