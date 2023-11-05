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

function init_namespaces_file() {
    curl -sS \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      -X LIST \
      $VAULT_ADDR/v1/sys/namespaces | jq . > namespaces.json

    if $(jq 'has("errors")' namespaces.json); then
      echo "Error calling $VAULT_ADDR/v1/sys/namespaces"
      cat namespaces.json
      exit 1;
    fi
}

function init_clients_file() {
  # call the activity export api and save it to a file
  # use https://unixtime.org/ to get the appropriate epoch values
  curl -sS \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --request GET \
      "$VAULT_ADDR/v1/sys/internal/counters/activity/export?start_time=$1&end_time=$2&format=json" | jq . > clients-no-array.json

  if $(jq 'has("errors")' clients-no-array.json); then
    echo "Error calling $VAULT_ADDR/v1/sys/internal/counters/activity/export"
    cat clients-no-array.json
    exit 1;
  fi
}

function init_entity_lookup_file() {
  # use the lookup api to get metadata, group, and policy info
  echo "{\"id\": \"$1\" }" > lookup.json

  # call the entity lookup api and save it to a file
  curl -sS \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --header "X-Vault-Namespace: $namespace_path" \
      --request POST \
      --data @lookup.json \
      $VAULT_ADDR/v1/identity/lookup/entity | jq . > lookup_result.json

  if $(jq 'has("errors")' lookup_result.json); then
    echo "Error calling entity lookup api"
    cat lookup_result.json
    exit 1;
  fi
}



function get_namespace() {
    local namespace_id="$1"
    echo $(jq -r ".data.key_info | to_entries | .[] | select(.value.id == \"$namespace_id\") | .value.path" namespaces.json)
}

function get_auth_method() {

    curl -sS \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --header "X-Vault-Namespace: $namespace_path" \
      $VAULT_ADDR/v1/identity/entity/id/$client_id | jq . > entity.json

    if $(jq 'has("errors")' entity.json); then
      echo "Error calling $VAULT_ADDR/v1/identity/entity/id/$client_id"
      cat entity.json
      exit 1;
    fi

    jq ".data.aliases[] | select(.mount_accessor == \"$2\")" entity.json > auth.json
}

function date_to_epoch() {
  # Get the human-readable date from the arguments
  human_date="$*"

  if [[ -z "$human_date" ]]; then
      echo "Usage: date_to_epoch 2023-09-01"
      exit 1
  fi

  # Check if date supports the GNU/Linux style invocation
  if date --version &>/dev/null; then
      # GNU/Linux style
      date -d "$human_date" +%s
  else
      # macOS (BSD) style
    date -jf "%Y-%m-%d" "$human_date" +%s 2>/dev/null || \
    date -jf "%a %b %d %T %Z %Y" "$human_date" +%s 2>/dev/null || \
    date -jf "%Y-%m-%d %H:%M:%S" "$human_date" +%s  
  fi
}

function epoch_to_date() {
  # Get the epoch timestamp from the argument
  epoch_timestamp="$1"

  if [[ -z "$epoch_timestamp" ]]; then
      echo "Usage: epoch_to_date 1234567890"
      exit 1
  fi

  # Check if date supports the GNU/Linux style invocation
  if date --version &>/dev/null; then
      # GNU/Linux style
      date -d "@$epoch_timestamp"
  else
      # macOS (BSD) style
      date -r "$epoch_timestamp"
  fi
}

# init all variables to empty state
client_id=""
mount_accessor=""
mount_path=""
mount_type=""
namespace_path=""
auth_name=""

# get the active clients in a date range and save it to clients-no-array.json
start_time=$(date_to_epoch $1)
end_time=$(date_to_epoch $2)
init_clients_file $start_time $end_time

# make the separate json elements from clients-no-array.json into a json array in clients.json
jq -s '.' clients-no-array.json > clients.json
size=$(jq 'length' clients.json)

# create a namespaces.json file
init_namespaces_file

# for each client in the clients 
for ((i=0; i<$size; i++)); do

    # reset attribute variables from prior loop iterations
    clear_attributes

    # write the current client to client.json
    jq ".[$i] | ." clients.json > client.json

    # get the timestamp
    timestamp=$(jq -r ".timestamp" client.json)
    # convert timestamp to human readable
    timestamp_human=$(epoch_to_date $timestamp)
    # read other machine identity attributes
    client_id=$(jq -r ".client_id" client.json)
    client_type=$(jq -r ".client_type" client.json)
    mount_accessor=$(jq -r ".mount_accessor" client.json)

    # get the namespace info
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
    role_name=$(jq -r ".metadata.role_name" auth.json)

    init_entity_lookup_file $client_id
    lookup=$(jq '.data | {metadata: .metadata, group_ids: .group_ids, policies: .policies}' lookup_result.json)

    # print the element with new attributes sorted alphabetically
    jq ". + {\"timestamp_human\": \"$timestamp_human\"} \
      + {\"namespace_path\": \"$namespace_path\"} \
      + {\"mount_path\": \"$mount_path\"} \
      + {\"mount_type\": \"$mount_type\"} \
      + {\"auth_name\": \"$auth_name\"} \
      + {\"role_name\": \"$role_name\"} \
      + $lookup \
      | to_entries | sort_by(.key) | from_entries " client.json
    
done
