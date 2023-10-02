#!/bin/bash

# This script calls the Vault Activity Export API 
# to count Vault clients for a particular date range
# and add human-readable attributes to the values
# Must set $VAULT_ADDR and $VAULT_TOKEN
# Must provide a start date argument as YYYY-MM-DD
# Must provide an end date argument as YYYY-MM-DD
# usage: human-readable-clients.sh 2023-09-01 2023-10-01
# should return json elements for each client in the date range

set -e
trap 'echo "An error occurred. Check json files for errors. Exiting."; exit 1' ERR

# Define a list of environment variables to check
variables_to_check=("VAULT_ADDR" "VAULT_TOKEN")

# Loop through each and check if it's set
for var in "${variables_to_check[@]}"; do
    if [ -z "${!var+x}" ]; then  # Use indirect variable reference with "${!var}"
        echo "$var is not set."
        exit 1
    fi
done

# check to see if require values for start and end dates were passed as arugments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 'YYYY-MM-DD' 'YYYY-MM-DD'"
    exit 1
fi

function clear_attributes() {
  client_id=""
  mount_accessor=""
  mount_path=""
  mount_type=""
  namespace_path=""
  auth_name=""
}

function get_namespace() {
    local namespace_id="$1"
    curl -sS \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      -X LIST \
      $VAULT_ADDR/v1/sys/namespaces | jq . > namespaces.json
    
    echo $(jq -r ".data.key_info | to_entries | .[] | select(.value.id == \"$namespace_id\") | .value.path" namespaces.json)
}

function get_auth_method() {

    curl -sS \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --header "X-Vault-Namespace: $namespace_path" \
      $VAULT_ADDR/v1/identity/entity/id/$client_id | jq . > entity.json

    jq ".data.aliases[] | select(.mount_accessor == \"$2\")" entity.json > auth.json
}

function date_to_epoch() {
  # Check if an argument is provided
  if [[ -z "$1" ]]; then
      echo "Usage: $0 'YYYY-MM-DD'"
      exit 1
  fi

  cmd="date"
  args=()
  # Check for GNU date
  if date --version &> /dev/null; then   
    args+=("-d")
  # Assume BSD date
  else
    args+=("-jf" "%Y-%m-%d")
  fi

  args+=("$1" "+%s")

  "$cmd" "${args[@]}"
}

start_time=$(date_to_epoch $1)
end_time=$(date_to_epoch $2)

# call the activity export api and save it to a file
# use https://unixtime.org/ to get the appropriate epoch values
curl -sS \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request GET \
    "$VAULT_ADDR/v1/sys/internal/counters/activity/export?start_time=$start_time&end_time=$end_time&format=json" | jq . > clients-no-array.json

client_id=""
mount_accessor=""
mount_path=""
mount_type=""
namespace_path=""
auth_name=""

# make the separate json elements file into a json array
jq -s '.' clients-no-array.json > clients.json
size=$(jq 'length' clients.json)

# for each client
for ((i=0; i<$size; i++)); do

    #reset attribute variables from prior loop iterations
    clear_attributes

    #write the current client to client.json
    jq ".[$i] | ." clients.json > client.json

    #get the timestamp
    timestamp=$(jq -r ".timestamp" client.json)
    #convert timestamp to human readable
    timestamp_human=$(date -r $timestamp)
    #read other machine identity attributes
    client_id=$(jq -r ".client_id" client.json)
    client_type=$(jq -r ".client_type" client.json)
    mount_accessor=$(jq -r ".mount_accessor" client.json)

    #get the namespace info
    namespace_id=$(jq -r ".namespace_id" client.json)
    namespace_path=""
    if [ "$namespace_id" == "root" ]; then
        namespace_path=""
    else
        # get the human readable namespace path
        namespace_path=$(get_namespace $namespace_id)
    fi

    # non-entity tokens do not have additional entity attributes available
    if [ "$client_type" == "non-entity-token" ]; then
      # if this is a non-entity token, print out limited info
      jq ". + {\"timestamp_human\": \"$timestamp_human\"} \
        + {\"namespace_path\": \"$namespace_path\"} \
        + {\"mount_type\": \"token\"} \
        | to_entries | sort_by(.key) | from_entries " client.json
      continue
    fi

    # get human readable attributes from the entity alias that matches the mount_path into auth.json
    get_auth_method $client_id $mount_accessor $namespace_path
    # read the human-readable attributes from auth.json
    mount_path=$(jq -r ".mount_path" auth.json)
    mount_type=$(jq -r ".mount_type" auth.json)
    auth_name=$(jq -r ".name" auth.json)

    #print the element with new attributes sorted alphabetically
    jq ". + {\"timestamp_human\": \"$timestamp_human\"} \
      + {\"namespace_path\": \"$namespace_path\"} \
      + {\"mount_path\": \"$mount_path\"} \
      + {\"mount_type\": \"$mount_type\"} \
      + {\"auth_name\": \"$auth_name\"} \
      | to_entries | sort_by(.key) | from_entries " client.json
    
done
