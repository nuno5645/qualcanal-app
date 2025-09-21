#!/usr/bin/env sh
set -o errexit
set -o nounset
set -o pipefail

python manage.py migrate --noinput
exec "$@"
