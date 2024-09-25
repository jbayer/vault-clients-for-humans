# vault-clients-for-humans
This is a bash script that uses `curl`, `jq`, and `bash` to supplement the [Vault Activity Export API](https://developer.hashicorp.com/vault/api-docs/system/internal-counters#activity-export) (Use this script with Vault 1.17.x and prior. The Vault 1.18 Activity Export API has similar data in the standard API response and this script is not necessary). The API will return machine identities for each Vault Client that contributes to the data range provided. These client identifiers are machine identities and this script will call the Vault Entity API and Vault Entity Lookup API to supplement the data with human-readable attributes.

## Example Usage
```shell
./human-readable-clients.sh 2023-09-01 2023-11-05
{
  "auth_name": "jbayer",
  "client_id": "58b2e25e-f6c6-d236-e3ce-36811f9ca0ca",
  "client_type": "entity",
  "group_ids": [
    "c7e49717-0812-1ec1-d3f7-f398e98079cf"
  ],
  "metadata": {
    "cost_center": "foo",
    "email": "jbayer@example.com"
  },
  "mount_accessor": "auth_userpass_fd43786e",
  "mount_path": "auth/userpass/",
  "mount_type": "userpass",
  "namespace_id": "root",
  "namespace_path": "",
  "policies": [
    "secret-read"
  ],
  "role_name": "null",
  "timestamp": 1695253958,
  "timestamp_human": "Wed Sep 20 16:52:38 PDT 2023"
}
{
  "auth_name": "ebayer",
  "client_id": "b3f111b4-2083-137e-d7cf-dfca00253cf1",
  "client_type": "entity",
  "group_ids": [
    "c7e49717-0812-1ec1-d3f7-f398e98079cf"
  ],
  "metadata": {
    "cost_center": "bar",
    "email": "ebayer@example.com"
  },
  "mount_accessor": "auth_userpass_fd43786e",
  "mount_path": "auth/userpass/",
  "mount_type": "userpass",
  "namespace_id": "root",
  "namespace_path": "",
  "policies": [],
  "role_name": "null",
  "timestamp": 1695734058,
  "timestamp_human": "Tue Sep 26 06:14:18 PDT 2023"
}
{
  "client_id": "lgDIkUv4EWOevwTfW0BlSF71t7q/U38kem05S9PQCkE=",
  "client_type": "non-entity-token",
  "mount_accessor": "auth_token_a2c0009b",
  "mount_type": "token",
  "namespace_id": "root",
  "namespace_path": "",
  "non_entity": true,
  "timestamp": 1695752531,
  "timestamp_human": "Tue Sep 26 11:22:11 PDT 2023"
}
{
  "auth_name": "jbayer",
  "client_id": "b090c4ba-4eb8-ac86-da3f-a8df8954f668",
  "client_type": "entity",
  "group_ids": [
    "ff69c888-cc76-0343-3e85-8632d178e3e5"
  ],
  "metadata": null,
  "mount_accessor": "auth_userpass_f8701475",
  "mount_path": "auth/userpass/",
  "mount_type": "userpass",
  "namespace_id": "NWU9T",
  "namespace_path": "james/",
  "policies": [],
  "role_name": "null",
  "timestamp": 1696081359,
  "timestamp_human": "Sat Sep 30 06:42:39 PDT 2023"
}
{
  "auth_name": "ffc01dd2-668a-a56b-3313-937b56f629c3",
  "client_id": "2f5d6c05-98c3-63ce-ce19-a1b3629a34d0",
  "client_type": "entity",
  "group_ids": [],
  "metadata": null,
  "mount_accessor": "auth_approle_c6ae28ec",
  "mount_path": "auth/approle/",
  "mount_type": "approle",
  "namespace_id": "root",
  "namespace_path": "",
  "policies": [],
  "role_name": "application1",
  "timestamp": 1699135522,
  "timestamp_human": "Sat Nov  4 15:05:22 PDT 2023"
}
```

## Requirements
* jq
* curl
* The Vault environment variables `VAULT_ADDR` and `VAULT_TOKEN` are set
* The token has Vault policy that enables it to call several Vault APIs at /sys
* argument1 is start date expressed as YYYY-MM-DD
* argument2 is end date expressed as YYYY-MM-DD
* The script user can write json files to the current working directory

## Activity Export API Example
The Acitivity Export API data by itself only returns machine identifiers. 
Once you have a `client_id`, you can call the Entity API and look at the matching Entity Alias information 
to find more human-readable information. The script automates putting that together.

```shell
# use https://unixtime.org/ to get the appropriate epoch values
curl \
    -sS --header "X-Vault-Token: $VAULT_TOKEN" \
    --request GET \
    "$VAULT_ADDR/v1/sys/internal/counters/activity/export?start_time=1672560000&end_time=1696081469&format=json" | jq .
{
  "client_id": "58b2e25e-f6c6-d236-e3ce-36811f9ca0ca",
  "namespace_id": "root",
  "timestamp": 1695253958,
  "mount_accessor": "auth_userpass_fd43786e",
  "client_type": "entity"
}
{
  "client_id": "b3f111b4-2083-137e-d7cf-dfca00253cf1",
  "namespace_id": "root",
  "timestamp": 1695734058,
  "mount_accessor": "auth_userpass_fd43786e",
  "client_type": "entity"
}
{
  "client_id": "lgDIkUv4EWOevwTfW0BlSF71t7q/U38kem05S9PQCkE=",
  "namespace_id": "root",
  "timestamp": 1695752531,
  "non_entity": true,
  "mount_accessor": "auth_token_a2c0009b",
  "client_type": "non-entity-token"
}
{
  "client_id": "b090c4ba-4eb8-ac86-da3f-a8df8954f668",
  "namespace_id": "NWU9T",
  "timestamp": 1696081359,
  "mount_accessor": "auth_userpass_f8701475",
  "client_type": "entity"
}

curl -sS \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --header "X-Vault-Namespace: james/" \
    $VAULT_ADDR/v1/identity/entity/id/b090c4ba-4eb8-ac86-da3f-a8df8954f668 | jq .

{
  "request_id": "e6e2eedd-d4cc-0854-2679-269399e9b0cb",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": {
    "aliases": [
      {
        "canonical_id": "b090c4ba-4eb8-ac86-da3f-a8df8954f668",
        "creation_time": "2023-09-30T13:31:43.865762Z",
        "custom_metadata": null,
        "id": "5218c7bb-1a83-9835-6c7d-b9613ab05548",
        "last_update_time": "2023-09-30T13:31:43.865762Z",
        "local": false,
        "merged_from_canonical_ids": null,
        "metadata": null,
        "mount_accessor": "auth_userpass_f8701475",
        "mount_path": "auth/userpass/",
        "mount_type": "userpass",
        "name": "jbayer"
      }
    ],
    "creation_time": "2023-09-30T13:31:43.865759Z",
    "direct_group_ids": [
      "ff69c888-cc76-0343-3e85-8632d178e3e5"
    ],
    "disabled": false,
    "group_ids": [
      "ff69c888-cc76-0343-3e85-8632d178e3e5"
    ],
    "id": "b090c4ba-4eb8-ac86-da3f-a8df8954f668",
    "inherited_group_ids": [],
    "last_update_time": "2023-09-30T13:31:43.865759Z",
    "merged_entity_ids": null,
    "metadata": null,
    "mfa_secrets": {},
    "name": "entity_6524d8c9",
    "namespace_id": "NWU9T",
    "policies": []
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}

```
