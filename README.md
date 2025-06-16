# DTSSE Dashboard Grafana Version Control
N.B. This script was made whilst the Azure Managed Grafana dashboards were being managed under Grafana 10.

When this workflow is triggered, version restore is executed first. Then, from within the test script, version retrieval executes. The test script logs, in the workflow console, whether the workflow was a success or a failure.

The workflow is triggered on a cron schedule defined in `.github/workflows/cron.yml`; Grafana has no event signal for a change made to the dashboard from the UI, so a regular run of this script ensures all dashboard changes that will be stored in this GitHub repository are up-to-date.

# Restoring versions:
`grafana-versioning-restore.sh`

In `.github/workflows/cron.yml`, there is an environment variable called `VERSION_RESTORE`. This variable should point to an array of JSON objects.

Each object represents a version of a dashboard to restore. You can add or remove objects so long as they follow the format specified below.

The format of each object should follow this key/value pattern (example values for the UID and version number are being used here):<br>
`{ "RESTORE_DASHBOARD_UID": "000000003", "RESTORE_DASHBOARD_VERSION": 1 },`

Only include a comma if the JSON object is NOT the last object in the array.

Once the workflow is triggered, an attempt will be made to restore the dashboard with the UID specified (as a string in `RESTORE_DASHBOARD_UID`) to the version specified (as an integer in `RESTORE_DASHBOARD_VERSION`). This will be attempted for every JSON object in the array.

If there is a version restore failure, this will be logged in the workflow console. The rest of the workflow (version retrieval, testing) will execute.

The UID of your dashboard can be retrieved from within the URL of your dashboard if you navigate to it via the Grafana UI. It should come after the `/d/` attribute of the URL.

The directories in this GitHub repository, storing each version of their dashboards, are also named after the UID of their respective dashboards.

N.B. Grafana only retains 20 of the most recent versions of a dashboard.

This means if, for example, there are 25 versions of a dashboard, version 1 through to (and including) version 5 cannot be retrieved, but version 6 through to (and including) version 25 can.

Restoring beyond this limit must therefore be a manual process. This means opening the file of the dashboard version to be restored from the GitHub repository, navigating to the current dashboard via the Grafana UI, then:
Edit > Settings > JSON model

Replace the current JSON configuration, in the JSON model page, with the old version to be restored to. This cannot be a direct copy/paste of the entire GitHub file. However, replacing the content within the `panels[]` array inside the current JSON configuration, for example, with the content within the `panels[]` array inside the GitHub file, will successfully restore the panels from this old version. Please note, though, that this will not be logged as a version restoration in Grafana.

# Retrieving versions:
`grafana-versioning.sh`

When a user makes changes to a dashboard from the Grafana UI, the user must save the changes made. These saved changes are logged as a new version of that dashboard.

This script utilises the Grafana API to get every version of every dashboard (as written in JSON). 

It writes each version to it's own JSON file (named after the creator of the dashboard and the time at which the dashboard was updated).

Each version file is stored in a directory named after the unique identifier (UID) of the dashboard the version belongs to. These directories are stored here, in this GitHub repository, with use of the GitHub API.

# Testing:
`grafana-versioning-test.sh`

## Assumptions:
- A test dashboard will be created in Grafana for testing purposes.

- The user, via the UI, will make at least one change to the test dashboard content, such that the first and second version of the dashboard are different from each other.

Each time the test script is executed, the test dashboard is restored to the immediately previous version of itself. The test dashboard is effectively restored back and forth between two versions. This restoration is meant to simulate changes made to a dashboard overall.

This script executes the main script within itself, after restoring the test dashboard to it's previous version. 

After the main script has executed, the test script checks whether the changes made to the test dashboard have been saved to GitHub by the main script. 

The aforementioned check is executed via comparison of the test dashboard, as retrieved via the Grafana API, to the file saved in the current GitHub repository by the main script.

# Environment Variables:
`GRAFANA_SERVICE_TOKEN: ${{ secrets.GRAFANA_SERVICE_TOKEN }}`<br>
`GRAFANA_BASE_URL: ${{ secrets.GRAFANA_BASE_URL }}`<br>
`GRAFANA_TEST_DASHBOARD_UID: ${{ secrets.GRAFANA_TEST_DASHBOARD_UID }}`<br>
`GITHUB_BRANCH_NAME: "main"`<br>

A `GRAFANA_SERVICE_TOKEN` is created by a Grafana service account. This must always be read from a secret.<br>
The `GITHUB_BRANCH_NAME` may not necessarily be "main", but "master" instead.

If a GitHub PAT token has not yet been created for this repository, this should be done such that `GITHUB_TOKEN` can retrieve it via:<br>
`GITHUB_TOKEN: ${{ github.token }}`<br>
The permissions for this token should include read/write of `contents`.
