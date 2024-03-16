#!/usr/bin/env bash
set -eu

cd ./tmp
find -type f -name "*.json" | while read -r fname
do
  echo "${fname}"
  __dir="${fname#./}"
  mkdir -p "../data/${__dir%/*}"
  jq '.' "${fname}" > "../data/${fname#./}"
done

find -type f -name "*.csv,*.log" | while read -r fname
do
  echo "${fname}"
  __dir="${fname#./}"
  mkdir -p "../data/${__dir%/*}"
  mv -v "${fname}" "../data/${fname#./}"
done
exit $?
