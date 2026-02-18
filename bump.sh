#!/bin/bash

APIKEY=$1
shift  # remove the first argument (API key) from "$@"

## dart pub global activate dart_bump

dart_bump . \
  --extra-file "lib/src/docker_commander_base.dart=static\\s+final\\s+String\\s+VERSION\\s+=\\s+['\"]([\\w.\\-]+)['\"]" \
  --api-key $APIKEY \
  "$@"
