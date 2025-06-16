#!/bin/bash -x

echo "Initialising tests..."
# 1. GET test dashboard from Grafana
TEST_DASHBOARD_URL="${GRAFANA_BASE_URL}dashboards/uid/${GRAFANA_TEST_DASHBOARD_UID}"
RESTORE_TEST_DASHBOARD_URL="${GRAFANA_BASE_URL}dashboards/uid/${GRAFANA_TEST_DASHBOARD_UID}/restore"

TEST_DASHBOARD_OBJECT=$(curl -s -H "Authorization: Bearer ${GRAFANA_SERVICE_TOKEN}" "${TEST_DASHBOARD_URL}" | jq '.')

#  2. POST a different version of the test dashboard
TEST_DASHBOARD_LATEST_VERSION=$(jq -r '.dashboard.version' <<< "${TEST_DASHBOARD_OBJECT}")
# An odd version number is for the version with only one panel, an even version number is for the version with multiple panels
VERSION=$((TEST_DASHBOARD_LATEST_VERSION - 1))

curl -H "Authorization: Bearer ${GRAFANA_SERVICE_TOKEN}" --json "{\"version\": ${VERSION}}" "${RESTORE_TEST_DASHBOARD_URL}"

# 3. GET the POSTed test dashboard details to ascertain the file name it would have on GitHub
UPDATED_TEST_DASHBOARD_OBJECT=$(curl -s -H "Authorization: Bearer ${GRAFANA_SERVICE_TOKEN}" "${TEST_DASHBOARD_URL}" | jq '.')
CREATED=$(jq -r '.meta.updated' <<< "${UPDATED_TEST_DASHBOARD_OBJECT}")
CREATED_BY=$(jq -r '.meta.createdBy' <<< "${UPDATED_TEST_DASHBOARD_OBJECT}" | sed 's/ /-/g')

# Format the date (YYYY-MM-DD_HH-MM-SS) - macOS compatible approach
# Extract date parts from the ISO format
YEAR=${CREATED%%-*}
MONTH=${CREATED:5:2}
DAY=${CREATED:8:2}
TIME=${CREATED#*T}
TIME=${TIME%%[.+Z]*}
HOUR=${TIME:0:2}
MINUTE=${TIME:3:2}
SECOND=${TIME:6:2}

FORMATTED_DATE="${YEAR}-${MONTH}-${DAY}_${HOUR}-${MINUTE}-${SECOND}"

GITHUB_FILE_PATH="${GRAFANA_TEST_DASHBOARD_UID}/${GRAFANA_TEST_DASHBOARD_UID}_${FORMATTED_DATE}_${CREATED_BY}.json"

# 4. Run grafana-versioning.sh
chmod +x ./scripts/grafana-versioning.sh
./scripts/grafana-versioning.sh

# 5. GET new test file from GitHub repository
GITHUB_UPDATED_TEST_DASHBOARD_OBJECT=$(curl -H "Accept: application/vnd.github.v3.raw" -H "Authorization: token ${GITHUB_TOKEN}" -L "https://api.github.com/repos/${GITHUB_REPO_OWNER_AND_NAME}/contents/${GITHUB_FILE_PATH}?ref=${GITHUB_BRANCH_NAME}" | jq '.')

# 6. Compare the GitHub JSON object to the Grafana JSON object
UPDATED_TEST_DASHBOARD=$(echo "${UPDATED_TEST_DASHBOARD_OBJECT}" | jq -S '.dashboard | del(.id)')
GITHUB_UPDATED_TEST_DASHBOARD=$(echo "${GITHUB_UPDATED_TEST_DASHBOARD_OBJECT}" | jq -S .data)

# 7. Exit the test with exit code 0 (success) if the dashboards are equal, otherwise kill the script with exit code 1 (failure)
error_color="\033[0;31m" # Red color for error messages
success_color="\033[0;32m" # Green color for success messages
reset_color="\033[0m" # Reset color

if [ "$(echo "${UPDATED_TEST_DASHBOARD}" | jq -S .)" == "$(echo "${GITHUB_UPDATED_TEST_DASHBOARD}" | jq -S .)" ]; then
    echo -e "${success_color}Testing: Passed${reset_color}"
    exit 0
else
    echo -e "${error_color}Testing: Failed${reset_color}"
    exit 1
fi
