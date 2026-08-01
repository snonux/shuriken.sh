#!/usr/bin/env bash
set -euo pipefail

# Container entrypoint for the shuriken image.
#
# Two modes:
#
#   1. Ad-hoc: any arguments are passed straight to shuriken, so the image still
#      works one-shot, e.g.:
#        docker run --rm shuriken --version
#        docker run --rm -v "$PWD/album:/work" shuriken --generate \
#            --incoming /work/incoming --dist /work/dist \
#            --template /usr/share/shuriken/templates/default
#
#   2. Multi-site (default, no args): run `shuriken --generate --config <conf>`
#      once per *.conf found in $CONFIGS_DIR (default /configs). This lets one
#      container generate several photo albums sequentially against a shared
#      volume -- the K8s CronJob mounts a ConfigMap of per-site shuriken.conf
#      files there, each pointing INCOMING_DIR/DIST_DIR at subpaths of the NFS
#      mount. A non-zero exit from any site aborts the run (errexit), so a
#      broken site is surfaced instead of silently skipped.

if (( $# > 0 )); then
    exec shuriken "$@"
fi

config_dir="${CONFIGS_DIR:-/configs}"
shopt -s nullglob
configs=( "$config_dir"/*.conf )
shopt -u nullglob

if (( ${#configs[@]} == 0 )); then
    printf 'shuriken-entrypoint: no .conf files in %s; nothing to generate\n' \
        "$config_dir" >&2
    exit 1
fi

for conf in "${configs[@]}"; do
    printf 'shuriken-entrypoint: generating album from %s\n' "$conf"
    # Default to a single image job in the container: the N100 hosts running the
    # k3s cluster are passively cooled, and a parallel ImageMagick burst would
    # spike CPU/thermals for a batch job with no latency budget. An operator can
    # raise it per-run with SHURIKEN_IMAGE_JOBS (e.g. 2). The CLI flag wins over
    # any IMAGE_JOBS in the site conf, intentional for the container default.
    shuriken --generate --image-jobs "${SHURIKEN_IMAGE_JOBS:-1}" \
        --config "$conf"
    printf 'shuriken-entrypoint: finished %s\n' "$conf"
done

printf 'shuriken-entrypoint: all %d site(s) generated\n' "${#configs[@]}"