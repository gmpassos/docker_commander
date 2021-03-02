FROM google/dart

## Update the apt package index and install packages to allow apt to use a repository over HTTPS:
RUN \
  apt-get -q update && \
  apt-get install -y -q apt-transport-https ca-certificates curl gnupg-agent software-properties-common

## Add Docker’s official GPG key:
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -

## Set up Docker the stable repository:
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

## Install Docker Engine:
RUN \
  apt-get -q update && \
  apt-get install -y -q docker-ce docker-ce-cli containerd.io

RUN \
  usermod -aG docker $(/bin/whoami)

## Allow access to host Docker socket:
CMD chmod 777 /var/run/docker.sock

## Disable Dart anonymous reports, trought Google Analytics.
RUN dart --disable-analytics

EXPOSE 8099/tcp

## docker_commander project:
WORKDIR /app

ADD pubspec.* /app/
RUN pub get
ADD . /app
RUN pub get --offline

ENTRYPOINT ["/usr/bin/dart", "pub", "run", "bin/docker_commander_server.dart", "--public"]

## USAGE:
## docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock -p 8099:8099 docker_commander/server userx 123456

