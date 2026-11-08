// Same existing declared-data mock contract. This writes no project and issues
// no permission; the caller deliberately installs these independent files.
export function recordUpdateMockProjectFiles({connection, resource, alias,
  idField, valueField, recordId, previousValue, controlId, controlValue,
  updatePermission, observePermission}) {
  for (const value of [connection, resource, alias, idField, valueField, recordId,
    previousValue, controlId, controlValue, updatePermission, observePermission]) {
    if (typeof value !== 'string' || !value) throw new TypeError('InvalidRecordUpdateMockInput');
  }
  if (recordId === controlId || idField === valueField) throw new TypeError('AmbiguousRecordUpdateMockInput');
  const json = value => JSON.stringify(value, null, 2) + '\n';
  return {
    'actql.config.json': json({version: 'actql-config/0.1', connectors: './connectors.json',
      state_dir: './.actql', profile: 'mock',
      mock: {catalog: './mock/catalog.json', data: './mock/data.json', answers: {}}}),
    'connectors.json': json({version: 'actql-connectors/0.1',
      connections: {[connection]: {connector: connection}}}),
    'mock/catalog.json': json({connections: {[connection]: {
      views: [{resource, resource_kind: 'record', schema: {
        [idField]: {type: 'string', nullable: false}, [valueField]: {type: 'string', nullable: false}},
        facts: {relation_keys: {candidate_keys: [[idField]]}}}],
      query_aliases: [{name: alias, resource}],
      data: [{resource, items_path: [connection, resource, 'rows'],
        key_path: [connection, resource, 'key'], primary_identity: idField}],
      writes: [{resource, primary_identity: idField, writable_fields: [valueField],
        permission: updatePermission, observe_permission: observePermission,
        approval: 'required', aliases: [connection + '.' + resource]}],
    }}}),
    'mock/data.json': json({[connection]: {[resource]: {key: [idField], rows: [
      {[idField]: recordId, [valueField]: previousValue},
      {[idField]: controlId, [valueField]: controlValue},
    ]}}}),
  };
}
