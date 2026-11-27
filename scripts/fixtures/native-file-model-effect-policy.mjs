// Independently derived from the declared File Relation and its typed View.
// The installed issuer supplies the actual evidence and both policy CIDs.
const dataPolicy = 'sha256:96fb9e334b987ad725901633886e3a81af77b1352b997e27ea08f5d8eb252152';
const response = 'sha256:0187c3746ea7811db5978a8d5e466a8b5f38e269b15c3f0a11675d3cb672d87f';
const view = 'sha256:6adb9500ec361c701d568825b2d32acf78fd74f88aa4c5b570487b24423f2ee8';

export function nativeFileModelEffectPolicy() {
  const expectedPolicy = () => ({
    version: 'actql-effective-data-policy/0.1', classification: 'unknown', unknown_provenance: true,
    source_data_policy_cids: [dataPolicy], source_response_policy_cids: [response],
  });
  return {modelRawDataPolicy: expectedPolicy(), finalResultPolicy: expectedPolicy(),
    modelRawResponseViews: new Map([[response, view]])};
}
