#!/bin/bash

# URL prefix for restoring a specified dashboard version
RESTORE_DASHBOARD_URL_PREFIX="${GRAFANA_BASE_URL}dashboards/uid/"
# URL suffix for restoring a specified dashboard version
RESTORE_DASHBOARD_URL_SUFFIX="/restore"
# URL prefix for getting all versions of a dashboard
DASHBOARD_VERSION_PREFIX_URL="${GRAFANA_BASE_URL}dashboards/uid/"
# URL suffix for getting all versions of a dashboard
DASHBOARD_VERSION_SUFFIX_URL="/versions"

# Maximum number of versions that Grafana keeps for each dashboard
VERSION_LIMIT=20

# Read from VERSION_RESTORE in YAML file
VERSIONS_TO_RESTORE=$(echo "${VERSION_RESTORE}" | jq -c '.[]')

index=0
for VERSION_TO_RESTORE in ${VERSIONS_TO_RESTORE[@]}; do
    (( index++ ))
    echo "VERSION_RESTORE INPUT ${index}"

    UID_TO_RESTORE=$(echo "${VERSION_TO_RESTORE}" | jq -r .'RESTORE_DASHBOARD_UID')
    VERSION_TO_RESTORE=$(echo "${VERSION_TO_RESTORE}" | jq -r '.RESTORE_DASHBOARD_VERSION')

    LATEST_VERSION=$(curl -s -H "Authorization: Bearer ${GRAFANA_SERVICE_TOKEN}" "${DASHBOARD_VERSION_PREFIX_URL}${UID_TO_RESTORE}${DASHBOARD_VERSION_SUFFIX_URL}" | jq -r '.versions[0].version')

    OLDEST_VERSION_SAVED_TO_GRAFANA=$((LATEST_VERSION - VERSION_LIMIT))

    if [ -z "${VERSION_TO_RESTORE}" ]; then
        echo "Skipping restore as version number is not defined."
        continue
    elif [ -z "${UID_TO_RESTORE}" ]; then
        echo "Skipping restore as dashboard is not defined"
        continue
    elif [ ${VERSION_TO_RESTORE} -le ${OLDEST_VERSION_SAVED_TO_GRAFANA} ]; then
        echo "Skipping restore for UID ${UID_TO_RESTORE} version ${VERSION_TO_RESTORE} as it is older than the latest version minus the limit of ${VERSION_LIMIT} of the most recent versions that Grafana retains."
        continue
    else
        echo "Attempting restoration of UID ${UID_TO_RESTORE} version ${VERSION_TO_RESTORE}."

        RESTORE_DASHBOARD_URL="${RESTORE_DASHBOARD_URL_PREFIX}${UID_TO_RESTORE}${RESTORE_DASHBOARD_URL_SUFFIX}"

        curl -s -H "Authorization: Bearer ${GRAFANA_SERVICE_TOKEN}" --json "{\"version\": ${VERSION_TO_RESTORE}}" "${RESTORE_DASHBOARD_URL}"
    fi
    echo -e "\n"
done