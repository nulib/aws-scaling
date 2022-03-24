const AWS = require('aws-sdk');
const SolrCluster = require('./solr_cluster');

const handler = async (event, _context) => {
  switch (event.operation) {
    case 'flatten':
      return event.input.flat();
    case 'length':
      return event.input.length;
    case 'flat-length':
      return event.input.flat().length;
    case 'backup':
      return await solrBackup(event);
    case 'restore':
      return await solrRestore(event);
    case 'ready':
      return await solrReady(event);
  }
};

const solrBackup = async (event) => {
  const cluster = new SolrCluster(event.solr.baseUrl);
  if (event.collection) {
    return await cluster.backup(event.collection);
  } else if (event.collections) {
    return await backupMultiple(cluster, collections);
  } else {
    const state = await cluster.status();
    const collections = Object.keys(state.cluster.collections);
    return await backupMultiple(cluster, collections);
  }
};

const backupMultiple = async (cluster, collections) => {
  const result = {};
  for (const collection of collections) {
    result[collection] = await cluster.backup(collection);
  }
  return result;
};

const solrRestore = async (event) => {
  const cluster = new SolrCluster(event.solr.baseUrl);
  const collection = event.collection;
  const name = event.name || collection;
  return await cluster.restore(collection, name, event.backupId);
}

const solrReady = async (event) => {
  const cluster = new SolrCluster(event.solr.baseUrl);
  const desiredNodes = Number(event.solr.nodeCount);
  const liveNodes = await cluster.liveNodeCount();
  return liveNodes == desiredNodes;
};

module.exports = { handler };