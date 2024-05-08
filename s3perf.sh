#!/usr/bin/env bash
set -eux

__PID=$$
__RCLONE_OPTS="--log-level INFO --stats=10s --stats-log-level INFO --use-json-log"
__LOG_DIR="logs/${__PID}"

mkdir -p "${__LOG_DIR}"
rm -rfv /mnt/blockstorage/dist
trap 'rm -rf "/mnt/blockstorage/dist"' 1 2 3 15

set +x
for s3bucket in "e2-s3perf-20240501-sg" "e2-s3perf-20240501-sj22" "e2-s3perf-20240501-la" \
                "e2-s3perf-20240501-ph12" "e2-s3perf-20240501-or4" "e2-s3perf-20240501-da" \
                "e2-s3perf-20240501-ch" "e2-s3perf-20240501-va" "e2-s3perf-20240501-ca" \
                "e2-s3perf-20240501-mi" "e2-s3perf-20240501-ldn" "e2-s3perf-20240501-par" \
                "e2-s3perf-20240501-ie" "e2-s3perf-20240501-fra"
do

  for test in "00001m" "02000m" "10000m"
  do

    echo -e "upload /mnt/blockstorage/${test} to ${s3bucket}:${s3bucket}/${test}\n"
    set -x
    time rclone ${__RCLONE_OPTS} --log-file "${__LOG_DIR}/${s3bucket}-${test}-${__PID}-up.json" copy /mnt/blockstorage/${test} "${s3bucket}:${s3bucket}/${test}"
    set +x
    echo -e "upload /mnt/blockstorage/${test} to ${s3bucket}:${s3bucket}/${test}\n"
    echo -e "\n\n"

    echo -e "download ${s3bucket}:${s3bucket} to /mnt/blockstorage/${test}\n"
    mkdir -p /mnt/blockstorage/dist/${test}
    set -x
    time rclone ${__RCLONE_OPTS} --log-file "${__LOG_DIR}/${s3bucket}-${test}-${__PID}-dl.json" copy "${s3bucket}:${s3bucket}/${test}" /mnt/blockstorage/dist/${test}
    set +x
    echo -e "\n\n"

  done

  rm -rfv /mnt/blockstorage/dist

done

echo "Logging dir... ${__LOG_DIR}"

