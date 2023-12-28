#!/bin/bash

set -e

function usage() {
    echo ""
    echo "This script is used to run integration tests for plugin installed on a remote OpenSearch/Dashboards cluster."
    echo "--------------------------------------------------------------------------"
    echo "Usage: $0 [args]"
    echo ""
    echo "Required arguments:"
    echo "None"
    echo ""
    echo "Optional arguments:"
    echo -e "-b BIND_ADDRESS\t, defaults to localhost | 127.0.0.1, can be changed to any IP or domain name for the cluster location."
    echo -e "-p BIND_PORT\t, defaults to 9200 or 5601 depends on OpenSearch or Dashboards, can be changed to any port for the cluster location."
    echo -e "-s SECURITY_ENABLED\t(true | false), defaults to true. Specify the OpenSearch/Dashboards have security enabled or not."
    echo -e "-c CREDENTIAL\t(usename:password), no defaults, effective when SECURITY_ENABLED=true."
    echo -e "-t TEST_COMPONENTS\t(OpenSearch-Dashboards reportsDashboards etc.), optional, specify test components, separate with space, else test everything."
    echo -e "-v VERSION\t, no defaults, indicates the OpenSearch version to test."
    echo -e "-o OPTION\t, no defaults, determine the TEST_TYPE value among(default, manifest) in test_finder.sh, optional."
    echo -e "-h\tPrint this message."
    echo "--------------------------------------------------------------------------"
}

while getopts ":hb:p:s:c:t:v:o:" arg; do
    case $arg in
        h)
            usage
            exit 1
            ;;
        b)
            BIND_ADDRESS=$OPTARG
            ;;
        p)
            BIND_PORT=$OPTARG
            ;;
        s)
            SECURITY_ENABLED=$OPTARG
            ;;
        c)
            CREDENTIAL=$OPTARG
            ;;
        t)
            TEST_COMPONENTS=$OPTARG
            ;;
        v)
            VERSION=$OPTARG
            ;;
        o)
            OPTION=$OPTARG
            ;;
        :)
            echo "-${OPTARG} requires an argument"
            usage
            exit 1
            ;;
        ?)
            echo "Invalid option: -${OPTARG}"
            exit 1
            ;;
    esac
done


if [ -z "$BIND_ADDRESS" ]
then
  BIND_ADDRESS="localhost"
fi

if [ -z "$BIND_PORT" ]
then
  BIND_PORT="5601"
fi

if [ -z "$SECURITY_ENABLED" ]
then
  SECURITY_ENABLED="true"
fi

if [ -z "$CREDENTIAL" ]
then
  CREDENTIAL="admin:admin"
  USERNAME=`echo $CREDENTIAL | awk -F ':' '{print $1}'`
  PASSWORD=`echo $CREDENTIAL | awk -F ':' '{print $2}'`
fi

# User can send custom browser path through env variable
if [ -z "$BROWSER_PATH" ]
then
  BROWSER_PATH="chromium"
fi

. ./test_finder.sh

npm install

TEST_FILES=`get_test_list $TEST_COMPONENTS`
echo -e "Test Files List:"
echo $TEST_FILES | tr ',' '\n'
echo "BROWSER_PATH: $BROWSER_PATH"

# Array to store remote cypress workflow background processes IDs when run in parallel
declare -a all_process_pids

run_remote_cypress() {
    local repo="$1"
    local workflow_name="$2"
    local os_url="$3"
    local osd_url="$4"
    local branch_ref="$5"

    # Call the remoteCypress.sh script with the required arguments
    source remoteCypress.sh -r "$repo" -w "$workflow_name" -o "$os_url" -d "$osd_url" -b "$branch_ref" &
    bg_process_pid=$!
    echo "PID for the repo $repo is : $bg_process_pid"
    all_process_pids+=($bg_process_pid)
}

# Read inputs from the manifest file using jq
REMOTE_MANIFEST_FILE="remote_cypress_manifest.json"

# Parse the JSON file using jq and iterate over the components array
components=$(jq -c '.components[]' "$REMOTE_MANIFEST_FILE")
release_version=$(jq -r '.build.version' "$REMOTE_MANIFEST_FILE")
echo "Components: $components"
echo "Release version: $release_version"

for component in $components; do
    echo "Processing for the component: $component"

    repo=$(echo "$component" | jq -r '.["repository"]')
    workflow_name=$(echo "$component" | jq -r '.["workflow-name"]')
    os_url=$(echo "$component" | jq -r '.["opensearch"]')
    osd_url=$(echo "$component" | jq -r '.["opensearch-dashboards"]')
    branch_ref=$(echo "$component" | jq -r '.["ref"]')

    # Set default values if the opensearch and opensearch-dahsboards are not set in the manifest
    os_url=${os_url:-https://artifacts.opensearch.org/releases/bundle/opensearch/$release_version/opensearch-$release_version-linux-x64.tar.gz}
    osd_url=${osd_url:-https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$release_version/opensearch-dashboards-$release_version-linux-x64.tar.gz}

    echo "repo: $repo"
    echo "workflow_name: $workflow_name"
    echo "os_url: $os_url"
    echo "osd_url: $osd_url"
    echo "branch_ref: $branch_ref"

    # Call the function for each component
    run_remote_cypress "$repo" "$workflow_name" "$os_url" "$osd_url" "$branch_ref" 
done

# Wait for all processes to finish
wait "${all_process_pids[@]}"

log_directory="/tmp/logfiles"

# Read log files in tmp folder and put the output to CI
find "$log_directory" -type f -name "*.txt" | while IFS= read -r log_file; do
    if [ -f "$log_file" ]; then
        echo "Log content for file: $log_file"
        cat "$log_file"
    else
        echo "Log file not found: $log_file"
    fi
done

# Delete the temporary log files and folder after writing to CI
rm -rf "$log_directory"

## WARNING: THIS LOGIC NEEDS TO BE THE LAST IN THIS FILE! ##
# Cypress returns back the test failure count in the error code
# The CI outputs the error code as test failure count.
#
# We need to ensure the cypress tests are the last execute process to
# the error code gets passed to the CI.

if [ $SECURITY_ENABLED = "true" ]; then
    echo "Running security enabled tests"
    yarn cypress:run-with-security --browser "$BROWSER_PATH" --spec "$TEST_FILES"
else
    echo "Running security disabled tests"
    yarn cypress:run-without-security --browser "$BROWSER_PATH" --spec "$TEST_FILES"
fi