#!/bin/bash
CONTAINER="metasploitable2"
KNOWN_PIDS_FILE="/tmp/known_pids.txt"
WAZUH_IP="172.18.0.4"
WAZUH_PORT="514"

docker top "$CONTAINER" -eo pid,cmd 2>/dev/null | tail -n +2 > /tmp/current_procs.txt

if [ ! -f "$KNOWN_PIDS_FILE" ]; then
    awk '{print $1}' /tmp/current_procs.txt > "$KNOWN_PIDS_FILE"
    echo "Baseline created with $(wc -l < "$KNOWN_PIDS_FILE") processes."
    exit 0
fi

NEW_FOUND=0
while read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    cmd=$(echo "$line" | cut -d' ' -f2-)
    if ! grep -qx "$pid" "$KNOWN_PIDS_FILE"; then
        logger -n "$WAZUH_IP" -P "$WAZUH_PORT" -d -p daemon.warning -t process_monitor "New process detected in $CONTAINER: PID=$pid CMD=$cmd"
        echo "$pid" >> "$KNOWN_PIDS_FILE"
        echo "[ALERT] New process: PID=$pid CMD=$cmd"
        NEW_FOUND=1
    fi
done < /tmp/current_procs.txt

if [ "$NEW_FOUND" -eq 0 ]; then
    echo "No new processes."
fi
