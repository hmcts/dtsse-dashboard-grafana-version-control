#!/bin/bash

# 0. Clean-up script for error handling
cleanup () {
    exit_code=$?
    error_message="$1"
    error_color="\033[0;31m" # Red text for error messages
    reset_color="\033[0m" # Resets the text color
    
    echo -e "${error_color}An error occurred with exit code ${exit_code}: ${error_message}.${reset_color}"
    echo "Cleaning up temporary files and directories..."

    # Remove the downloaded ZIP file if it exists
    if [ -f "${ZIP_FILE_PATH}" ]; then
        rm "${ZIP_FILE_PATH}"
    fi
    # Remove the unzipped directory if it exists
    if [ -d "${UNZIPPED_FILE_PATH}" ]; then
        rm -rf "${UNZIPPED_FILE_PATH}"
    fi
    # Remove the temporary versions file if it exists
    if [ -f "${TEMP_VERSIONS_FILE}" ]; then
        rm "${TEMP_VERSIONS_FILE}"
    fi
    echo "Cleanup completed."
    exit 1
}

trap 'cleanup "Script interrupted by user"' SIGINT
# 1. Download existing version history from GitHub
GITHUB_REPO="${GITHUB_REPO_OWNER_AND_NAME#*/}"
GITHUB_BASE_URL="https://api.github.com/repos/"

# GitHub API URL for downloading repo ZIP
GITHUB_REPO_URL="${GITHUB_BASE_URL}${GITHUB_REPO_OWNER_USERNAME}/${GITHUB_REPO}/zipball/${GITHUB_BRANCH_NAME}"
# Name of the ZIP (and where it is saved locally)
ZIP_FILE_PATH="${GITHUB_PARENT_DIRECTORY}/temp.zip"

trap 'cleanup "Could not download content from GitHub"' ERR
# Download content from the GitHub repo
curl -H "Authorization: Bearer ${GITHUB_TOKEN}" -L "${GITHUB_REPO_URL}" -o "${ZIP_FILE_PATH}"

trap 'cleanup "Could not unzip GitHub repo file"' ERR
# Extract the ZIP contents from the GitHub repo
unzip -q "${ZIP_FILE_PATH}" -d "${GITHUB_PARENT_DIRECTORY}"

# Remove the ZIP file itself (because this file is not needed, the directory has been extracted)
rm "${ZIP_FILE_PATH}"

# 2. Find the name of the directory storing the GitHub repository content
SEARCH_STRING="${GITHUB_REPO_OWNER_USERNAME}-${GITHUB_REPO}-"
trap 'cleanup "Could not find the unzipped GitHub directory"' ERR
UNZIPPED_FILE_PATH=$(find "${GITHUB_PARENT_DIRECTORY}" -type d -name "*${SEARCH_STRING}*" | head -n 1)
# Extract just the directory name without the full path
UNZIPPED_DIR_NAME=$(basename "${UNZIPPED_FILE_PATH}")

# 3. Collect all dashboard UIDs
# URL for getting all existing dashboard UIDs
DASHBOARDS_URL="${GRAFANA_BASE_URL}search?type=dash-db"
# URL prefix for getting all versions of a dashboard
DASHBOARD_VERSION_PREFIX_URL="${GRAFANA_BASE_URL}dashboards/uid/"
# URL suffix for getting all versions of a dashboard
DASHBOARD_VERSION_SUFFIX_URL="/versions"

trap 'cleanup "Could not fetch dashboard IDs"' ERR
DASHBOARD_IDS=$(curl -s -H "Authorization: Bearer ${GRAFANA_SERVICE_TOKEN}" "${DASHBOARDS_URL}" | jq -r '.[].uid')

# 4. GET every version of every dashboard
# Create a temporary file to store all dashboard versions
TEMP_VERSIONS_FILE=$(mktemp)

for DASHBOARD_ID in ${DASHBOARD_IDS}; do
    DASHBOARD_VERSION_URL="${DASHBOARD_VERSION_PREFIX_URL}${DASHBOARD_ID}${DASHBOARD_VERSION_SUFFIX_URL}"
    # API call returns a list of every version for one provided dashboard; it does not return a version one by one
    trap 'cleanup "Could not fetch dashboard versions for ${DASHBOARD_VERSION_URL}"' ERR
    curl -s -H "Authorization: Bearer ${GRAFANA_SERVICE_TOKEN}" "${DASHBOARD_VERSION_URL}" | jq -c '.versions[]' >> "${TEMP_VERSIONS_FILE}"
done

# For each dashboard version...
while IFS= read -r VERSION_JSON; do
    trap 'cleanup "Could not process dashboard version"' ERR
    # Extract the fields from JSON required to compose the file name
    DASHBOARD_UID=$(jq -r '.uid' <<< "${VERSION_JSON}")
    CREATED=$(jq -r '.created' <<< "${VERSION_JSON}")
    CREATED_BY=$(jq -r '.createdBy' <<< "${VERSION_JSON}" | sed 's/ /-/g')
    
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
    
    GITHUB_FILE_PATH="${DASHBOARD_UID}/${DASHBOARD_UID}_${FORMATTED_DATE}_${CREATED_BY}.json"
    CURRENT_FILE_PATH="${GITHUB_PARENT_DIRECTORY}/${UNZIPPED_DIR_NAME}/${GITHUB_FILE_PATH}"
    
    trap 'cleanup "Could not create directory or file for dashboard version"' ERR
    # 5. Create a directory of the dashboard (named after the UID) if it does not exist
    mkdir -p "${GITHUB_PARENT_DIRECTORY}/${UNZIPPED_DIR_NAME}/${DASHBOARD_UID}"
    
    # 6. Create a new file for the dashboard version if it does not exist
    if [ ! -f "${CURRENT_FILE_PATH}" ]; then
        trap 'cleanup "Could not write version JSON to file"' ERR
        # 7. Write the version JSON to file
        echo "${VERSION_JSON}" | jq '.' > "${CURRENT_FILE_PATH}"

        # 8. Commit & push the new version file to GitHub
        COMMIT_MESSAGE="add new dashboard version to ${DASHBOARD_UID}, created on ${FORMATTED_DATE} by ${CREATED_BY}"
        
        trap 'cleanup "Could not encode file content to base64"' ERR
        # Use cat instead of direct file path with base64 on macOS
        FILE_CONTENT=$(cat "${CURRENT_FILE_PATH}" | base64 | tr -d '\n')
        
        # Determine the file path relative to the repo root
        RELATIVE_PATH="${GITHUB_FILE_PATH}"
        
        trap 'cleanup "Could not create JSON payload for GitHub API"' ERR
        # Create JSON payload for GitHub API
        JSON_PAYLOAD=$(jq -n \
            --arg message "${COMMIT_MESSAGE}" \
            --arg content "${FILE_CONTENT}" \
            '{message: $message, content: $content}')
        
        # Push to GitHub
        API_URL="${GITHUB_BASE_URL}${GITHUB_REPO_OWNER_USERNAME}/${GITHUB_REPO}/contents/${RELATIVE_PATH}"
        trap 'cleanup "Could not push changes to GitHub"' ERR
        curl -s -X PUT \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "${JSON_PAYLOAD}" \
            "${API_URL}" > /dev/null
    fi
done < "${TEMP_VERSIONS_FILE}"

# 9. Clean up temporary files (unzipped ZIP excluded from successful run)
rm "${TEMP_VERSIONS_FILE}"
rm -rf "${UNZIPPED_FILE_PATH}"

echo -e "\nGrafana dashboard versioning completed successfully"
