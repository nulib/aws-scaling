# AWS Step Functions to Start/Stop the Staging Environment

## Description

This repository includes code and Terraform manifests for an AWS Lambda and AWS Step Functions to reliably start and stop resources within the NUL RDC staging environment as follows:

### Spin Down

- Scale all ECS tasks in `meadow`, `avr`, and `arch` clusters down to 0
- Perform incremental backup of `avr` and `arch` collections in Solr
- Scale all ECS tasks in `fcrepo` and `solrcloud` clusters down to 0
- Stop `meadow-db` and `stack-s-db` RDS instances

### Spin Up

- Start `meadow-db` and `stack-s-db` RDS instances if necessary
  - Wait for both instances to reach `available` state
- Scale `fcrepo` ECS service up to 1
- Scale up `solrcloud` ECS services
  - 3 Zookeeper nodes
  - 4 Solr nodes
- Wait for the Solr cluster to report 4 stable, live nodes
- Restore `avr` and `arch` Solr collections
- Start `meadow`, `avr`, and `arch` ECS services

## Execution

To spin the staging environment up or down, execute the `stack-s-spin-up-environment` or `stack-s-spin-down-environment` Step Function, respectively, with the following payload:

```json
{
  "solr": {
    "baseUrl": "http://solr.internal.rdc-staging.library.northwestern.edu:8983/solr/",
    "collections": ["arch", "avr"]
  },
  "rds": {
    "meadow": "meadow-db",
    "stack": "stack-s-db"
  }
}
```