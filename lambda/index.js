const AWS = require('aws-sdk');
const SolrCluster = require('./solr_cluster');

const rdsReady = async (instanceId) => {
  const RDS = new AWS.RDS();
  const response = await RDS.describeDBInstances({ DBInstanceIdentifier: instanceId }).promise();
  return response.DBInstances[0].DBInstanceStatus == 'available';
}

const solrReady = async () => {
  const cluster = new SolrCluster(process.env.SOLR_BASE_URL);
  const desiredNodes = Number(process.env.SOLR_NODES);
  const liveNodes = await cluster.liveNodeCount();
  return liveNodes == desiredNodes;
}

const setInstanceCount = async (cluster, service, desiredCount) => {
  const ECS = new AWS.ECS();
  const { service } = await ECS.updateService({ cluster, service, desiredCount }).promise();
  return service;
}

module.exports = { rdsReady, solrReady, setInstanceCount };