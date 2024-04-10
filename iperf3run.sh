#!/usr/bin/env bash
# licence A-GPL3.0 Created by naa0yama
set -e

if [ -z "$1" ]; then
    echo "Comment is required."
    echo "Usage: $(basename "${0}") comment [ all | tcp | udp | th | th_byte ] (192.0.2.1)"
    exit 1
fi

set -eu
COMMENT="${1}"
ARGS="${2:-all}"
IP="${3:-192.0.2.1}"

for cmd in "date" "jq" "ip" "routel" "tracepath" "iperf3" "tar" "sort" "gnuplot"
do
  type "${cmd}"
done

INTERVAL_SECOND=60
PARALLEL_INT=5
WAIT_SECOND=5
TEST_TIME=$(date '+%Y-%m-%dT%H%M')
mapfile -t THROUGHPUT_BANDWIDTH < <(seq 100 10 190)
MTUS=(128 146 256 354 512 1024 1280 1360 1400 1440 1460 1500)
CMD_OPTIONS=(
  "--json"
  "--get-server-output"
  "--parallel" "${PARALLEL_INT}"
)

mkdir -p "${TEST_TIME}"
cd "${TEST_TIME}"

# Gather
set -x
ip -j link                > "_ip-link.json"
ip    link                > "_ip-link.txt"
ip -j route               > "_ip-route.json"
ip    route               > "_ip-route.txt"
routel                    > "_routel.txt"
tracepath -m 5 -n -b "${IP}" | tee "_tracepath.txt"
set +x

set +e
if ping -c 1 "${IP}" > /dev/null 2>&1
then
  echo "[OK] Server IP Reachable -> ${IP}"
else
  echo "[NG] Server IP Reachable -> ${IP}"
  set -e
  exit 1
fi

function __trap() {
    set +x
    echo "terminated by user !!!"
    rm -rf "../${TEST_TIME}"
    exit 1
}

function time_calc() {
  eta_time_int=0
  case "${1}" in
    ("all")
      local eta_time_int_tcp=$(( ${#MTUS[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      local eta_time_int_udp=$(( ${#MTUS[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      local eta_time_int_th=$(( ${#THROUGHPUT_BANDWIDTH[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      local eta_time_int_th_byte=$(( ${#MTUS[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      eta_time_int=$(( eta_time_int_tcp + eta_time_int_udp + eta_time_int_th + eta_time_int_th_byte ))

      ;;
    ("tcp")
      local eta_time_int_tcp=$(( ${#MTUS[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      eta_time_int=$(( eta_time_int_tcp ))

      ;;
    ("udp")
      local eta_time_int_udp=$(( ${#MTUS[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      eta_time_int=$(( eta_time_int_udp ))

      ;;
    ("th")
      local eta_time_int_th=$(( ${#THROUGHPUT_BANDWIDTH[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      eta_time_int=$(( eta_time_int_th ))

      ;;
    ("th_byte")
      local eta_time_int_th_byte=$(( ${#MTUS[@]} * $(( INTERVAL_SECOND + WAIT_SECOND )) * 2 ))
      eta_time_int=$(( eta_time_int_th_byte ))

      ;;
    (*)
      exit 1
      ;;
  esac

  echo "#- -----------------------------------------------------------------------------"
  echo "#- "
  echo "#- Time now          :    ${TEST_TIME}"
  echo "#- Estimated Time    :    $( date +'%Y-%m-%dT%H:%M' -d "${eta_time_int} second" ) \
  $(awk -vsecond=${eta_time_int} 'BEGIN{print strftime("%Hh%Mm%Ss",second,1)}'), ($(( eta_time_int / 60 )) minutes)"
  echo "#- "
  echo "#- -----------------------------------------------------------------------------"
}

#- -----------------------------------------------------------------------------
#- - wait loop
#- - display wait count down
#- -
#- - $1 ${WAIT_SECOND}
#- -----------------------------------------------------------------------------
function wait_interval() {
  echo -n "sleep....... "
  for wait in $(seq ${WAIT_SECOND} -1 1)
  do
    echo -n "${wait}"
    sleep 1
  done
  eta_time_int=$(( eta_time_int - $(( INTERVAL_SECOND + WAIT_SECOND ))))
  echo -e "\nETA: $(awk -vsecond=${eta_time_int} \
    'BEGIN{print strftime("%Hh%Mm%Ss",second,1)}')\n"
}

function gen_csv_tcp() {
  # TCP UP Cleint -> Server
  jq --arg COMMENT "${COMMENT}" -r '[
    $COMMENT,
    .title,
    .start.test_start.protocol,
    .start.tcp_mss,
    .start.test_start.num_streams,
    .start.test_start.duration,
    .server_output_json.end.sum_received.bits_per_second*0.000001,
    .end.sum_sent.bits_per_second*0.000001,
    "",
    (1 - (.server_output_json.end.sum_received.bits_per_second / .end.sum_sent.bits_per_second))*100,
    ([.end.streams[]?.sender?.min_rtt] | add),
    ([.end.streams[]?.sender?.mean_rtt] | add),
    ([.end.streams[]?.sender?.max_rtt] | add),
    .start.version] | @csv' TCP_UP_MTU*.json | sort -n >> results.csv
  sleep 2

  # TCP DL Server -> Client
  jq --arg COMMENT "${COMMENT}" -r '[
    $COMMENT,
    .title,
    .start.test_start.protocol,
    .start.tcp_mss,
    .start.test_start.num_streams,
    .start.test_start.duration,
    .server_output_json.end.sum_sent.bits_per_second*0.000001,
    .end.sum_received.bits_per_second*0.000001,
    "",
    (1 - (.end.sum_received.bits_per_second / .server_output_json.end.sum_sent.bits_per_second))*100,
    ([.server_output_json.end.streams[]?.sender?.min_rtt] | add),
    ([.server_output_json.end.streams[]?.sender?.mean_rtt] | add),
    ([.server_output_json.end.streams[]?.sender?.max_rtt] | add),
    .start.version] | @csv' TCP_DL_MTU*.json | sort -n >> results.csv
  sleep 2
}

function gen_csv_udp() {
  # UDP UP Cleint -> Server
  jq --arg COMMENT "${COMMENT}" -r '[
  $COMMENT,
  .title,
  .start.test_start.protocol,
  .start.test_start.blksize,
  .start.test_start.num_streams,
  .start.test_start.duration,
  (.end.sum.bits_per_second - ((.end.sum.lost_percent*0.01)*.end.sum.bits_per_second))*0.000001,
  .end.sum.bits_per_second*0.000001,
  .server_output_json.end.sum.jitter_ms,
  .server_output_json.end.sum.lost_percent,
  "", "", "",
  .start.version] | @csv' UDP_UP_MTU*.json | sort -n >> results.csv
  sleep 2

  # UDP DL Server -> Client
  jq --arg COMMENT "${COMMENT}" -r '[
    $COMMENT,
    .title,
    .start.test_start.protocol,
    .start.test_start.blksize,
    .start.test_start.num_streams,
    .start.test_start.duration,
    .end.sum.bits_per_second*0.000001,
    (.end.sum.bits_per_second - ((.end.sum.lost_percent*0.01)*.end.sum.bits_per_second))*0.000001,
    .end.sum.jitter_ms,
    .end.sum.lost_percent,
    "", "", "",
    .start.version] | @csv' UDP_DL_MTU*.json | sort -n >> results.csv
  sleep 2
}

function gen_csv_th() {
  # TCP TH
  jq --arg COMMENT "${COMMENT}" -r '[
    $COMMENT,
    .title,
    .start.test_start.protocol,
    1460,
    .start.test_start.num_streams,
    .start.test_start.duration,
    ([.end.streams[] | select(.sender.sender == true) | .sender?.bits_per_second*0.000001] | add),
    ([.end.streams[] | select(.receiver.sender == false) | .receiver?.bits_per_second*0.000001] | add),
    "","",
    ([.end.streams[]?.sender?.min_rtt] | add),
    ([.end.streams[]?.sender?.mean_rtt] | add),
    ([.end.streams[]?.sender?.max_rtt] | add),
    .start.version] | @csv' TH*M_TCP.json | sort -n >> results.csv
  sleep 2


  # UDP TH
  jq --arg COMMENT "${COMMENT}" -r '[
    $COMMENT,
    .title,
    .start.test_start.protocol,
    .start.test_start.blksize,
    .start.test_start.num_streams,
    .start.test_start.duration,
    ([.end.streams[] | select(.udp.sender == false) | .udp?.bits_per_second*0.000001] | add),
    ([.end.streams[] | select(.udp.sender == true) | .udp?.bits_per_second*0.000001] | add),
    ([.end.streams[] | .udp?.jitter_ms] | add),
    "", "", "", "",
    .start.version] | @csv' TH*M_UDP.json | sort -n >> results.csv
  sleep 2
}

function gen_csv_th_byte() {
  # TCP TH byte
  jq --arg COMMENT "${COMMENT}" -r '[
    $COMMENT,
    .title,
    .start.test_start.protocol,
    1460,
    .start.test_start.num_streams,
    .start.test_start.duration,
    ([.end.streams[] | select(.sender.sender == true) | .sender?.bits_per_second*0.000001] | add),
    ([.end.streams[] | select(.receiver.sender == false) | .receiver?.bits_per_second*0.000001] | add),
    "","",
    ([.end.streams[]?.sender?.min_rtt] | add),
    ([.end.streams[]?.sender?.mean_rtt] | add),
    ([.end.streams[]?.sender?.max_rtt] | add),
    .start.version] | @csv' TH_TCP_MTU*.json | sort -n >> results.csv
  sleep 2


  # UDP TH byte
  jq --arg COMMENT "${COMMENT}" -r '[
    $COMMENT,
    .title,
    .start.test_start.protocol,
    .start.test_start.blksize,
    .start.test_start.num_streams,
    .start.test_start.duration,
    ([.end.streams[] | select(.udp.sender == false) | .udp?.bits_per_second*0.000001] | add),
    ([.end.streams[] | select(.udp.sender == true) | .udp?.bits_per_second*0.000001] | add),
    ([.end.streams[] | .udp?.jitter_ms] | add),
    "", "", "", "",
    .start.version] | @csv' TH_UDP_MTU*.json | sort -n >> results.csv
  sleep 2
}

function gen_csv() {
  echo "Comment,Title,Protocol,Packetsize(byte),Streams(num),Duration(s),Received(Mbps),Send(Mbps),Jitter(ms),Lost(%),RTT_min(ms),RTT_avg(ms),RTT_max(ms),version" > results.csv

  case "${1}" in
    ("all")
      gen_csv_tcp
      gen_csv_udp
      gen_csv_th

      ;;
    ("tcp")
      gen_csv_tcp

      ;;
    ("udp")
      gen_csv_udp

      ;;
    ("th")
      gen_csv_th

      ;;
    ("th_byte")
      gen_csv_th_byte

      ;;
    (*)
      exit 1
      ;;
  esac
}

function iperf3_tcp() {
  for i in "${MTUS[@]}"
  do
    local __mtu="0000${i}"
    echo -e "================================================================================"
    echo -e "= TCP MTU: ${__mtu: -4}\n\n"
    set -x
    # Client -> Server
    iperf3 "${CMD_OPTIONS[@]}" -c "${IP}" -t "${INTERVAL_SECOND}" -M $(( i - 40 )) \
      -T "$(date '+%Y-%m-%d %H:%M') TCP UP MTU${__mtu: -4}" --logfile "TCP_UP_MTU${__mtu: -4}.json"
    set +x
    wait_interval

    set -x
    # Server -> Client
    iperf3 "${CMD_OPTIONS[@]}" -c "${IP}" -t "${INTERVAL_SECOND}" -M $(( i - 40 )) \
      -T "$(date '+%Y-%m-%d %H:%M') TCP DL MTU${__mtu: -4}" --logfile "TCP_DL_MTU${__mtu: -4}.json" -R
    set +x
    wait_interval
  done
}

function iperf3_udp() {
  for i in "${MTUS[@]}"
  do
    local __mtu="0000${i}"
    echo -e "================================================================================"
    echo -e "= UDP MTU: ${__mtu: -4}\n\n"
    set -x
    # Client -> Server
    iperf3 "${CMD_OPTIONS[@]}" -c "${IP}" -t "${INTERVAL_SECOND}" -l $(( i - 28 )) \
      -T "$(date '+%Y-%m-%d %H:%M') UDP UP MTU${__mtu: -4}" -u -b 200M --logfile "UDP_UP_MTU${__mtu: -4}.json"
    set +x
    wait_interval

    set -x
    # Server -> Client
    iperf3 "${CMD_OPTIONS[@]}" -c "${IP}" -t "${INTERVAL_SECOND}" -l $(( i - 28 )) \
      -T "$(date '+%Y-%m-%d %H:%M') UDP DL MTU${__mtu: -4}" -u -b 200M --logfile "UDP_DL_MTU${__mtu: -4}.json" -R
    set +x
    wait_interval
  done
}

function iperf3_th() {
  for th_bandwidth in "${THROUGHPUT_BANDWIDTH[@]}"
  do
    local __th_bandwidth="0000$(( th_bandwidth * PARALLEL_INT ))"
    echo -e "================================================================================"
    echo -e "= TCP throughput: ${__th_bandwidth: -4}M\n\n"
    set -x
    iperf3 "${CMD_OPTIONS[@]}" --bidir -c "${IP}" -t "${INTERVAL_SECOND}" -M $(( 1500 - 40 )) \
      -T "$(date '+%Y-%m-%d %H:%M') TCP TH${__th_bandwidth: -4}M" \
      -b "${th_bandwidth}M" --logfile "TH${__th_bandwidth: -4}M_TCP.json"
    set +x
    wait_interval

    echo -e "UDP throughput: ${__th_bandwidth: -4}M\n\n"
    set -x
    iperf3 "${CMD_OPTIONS[@]}" --bidir -c "${IP}" -t "${INTERVAL_SECOND}" -l $(( 1500 - 28 )) \
      -T "$(date '+%Y-%m-%d %H:%M') UDP TH${__th_bandwidth: -4}M" -u \
      -b "${th_bandwidth}M" --logfile "TH${__th_bandwidth: -4}M_UDP.json"
    set +x
    wait_interval
  done
}

function iperf3_th_byte() {
  for i in "${MTUS[@]}"
  do
    local __mtu="0000${i}"
    echo -e "================================================================================"
    echo -e "= TH Byte MTU: ${__mtu: -4}\n\n"
    set -x
    iperf3 "${CMD_OPTIONS[@]}" --bidir -c "${IP}" -t "${INTERVAL_SECOND}" -M $(( i - 40 )) \
      -T "$(date '+%Y-%m-%d %H:%M') TCP TH UP MTU${__mtu: -4}" --logfile "TH_TCP_MTU${__mtu: -4}.json"
    set +x
    wait_interval

    set -x
    iperf3 "${CMD_OPTIONS[@]}" --bidir -c "${IP}" -t "${INTERVAL_SECOND}" -l $(( i - 28 )) \
      -T "$(date '+%Y-%m-%d %H:%M') UDP TH DL MTU${__mtu: -4}" -u --logfile "TH_UDP_MTU${__mtu: -4}.json"
    set +x
    wait_interval
  done
}

function main() {

  time_calc "${ARGS}"

  case "${ARGS}" in
    ("all")
      iperf3_tcp
      iperf3_udp
      iperf3_th
      iperf3_th_byte
      gen_csv "${ARGS}"
      ;;

    ("tcp")
      iperf3_tcp
      gen_csv "${ARGS}"
      ;;

    ("udp")
      iperf3_udp
      gen_csv "${ARGS}"
      ;;

    ("th")
      iperf3_th
      gen_csv "${ARGS}"
      ;;

    ("th_byte")
      iperf3_th_byte
      gen_csv "${ARGS}"
      ;;

    (*)
      echo "Error: type emum [ all | tcp | udp | th | th_byte ]"
      exit 1
      ;;
  esac

  echo "Archive... ${TEST_TIME}_iperf3_test.tar.gz"
  set -x
  cd ../
  tar -zcvf "${TEST_TIME}_iperf3_test.tar.gz" "${TEST_TIME}" "$(basename "${0}")"
}

main "${ARGS}" 2>&1 | tee "$(basename "${0}" .sh).log"
