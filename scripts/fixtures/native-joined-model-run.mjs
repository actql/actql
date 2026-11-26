import assert from 'node:assert/strict';

// Two adopted File relations, two independently selected Model Tasks, one Result.
export function nativeJoinedModelRun(firstTask, secondTask) {
  const connection = 'files/native-fixture';
  const field = type => ({type, nullable: false});
  const views = [
    {resource: 'accounts', schema: {id: field('string'), notes: field('string')}},
    {resource: 'usage', schema: {id: field('string'), active_users: field('int64'), trend: field('string')}},
  ].map(view => ({...view, resource_kind: 'record', data_classification: 'internal',
    facts: {relation_keys: {candidate_keys: [['id']]}}}));
  const connections = {version: 'actql-connectors/0.1', connections: {[connection]: {connector: connection}}};
  const catalog = {connections: {[connection]: {views, query_aliases: views.map(({resource}) => ({
    name: resource, resource,
  })), data: views.map(({resource}) => ({resource, items_path: [connection, resource, 'rows'],
    key_path: [connection, resource, 'key'], primary_identity: 'id'}))}}};
  const payload = {[connection]: {
    accounts: {key: ['id'], rows: [{id: 'joined-1', notes: 'account notes from the declared File'}]},
    usage: {key: ['id'], rows: [{id: 'joined-1', active_users: '17', trend: 'declining usage from the declared File'}]},
  }};
  const expectedInput = {
    active_users: '17', notes: 'account notes from the declared File',
    trend: 'declining usage from the declared File',
  };
  const modelRawDataPolicy = {
    classification: 'unknown',
    source_data_policy_cids: [
      'sha256:530c120715b6538c2b5afa3431f0eaee463b593ce24d5323d48332b72bf4af70',
      'sha256:780d5be079a2364b02d5c51448101bfed3220aa3f176f6300a8e6d25eef196a8',
    ],
    source_response_policy_cids: [
      'sha256:03d4a4c3e6d268665495515859a5e87ee33a737469c9b642db6433f557ef3599',
      'sha256:e30171f43cd510506568f1ee10f0e0baa013bba5723cb69967f9b18d9154dd21',
    ],
    unknown_provenance: true,
    version: 'actql-effective-data-policy/0.1',
  };
  const modelRawResponseViews = new Map([
    ['sha256:e30171f43cd510506568f1ee10f0e0baa013bba5723cb69967f9b18d9154dd21',
      'sha256:53523f86c2abd066cb72f721f5d7bd9e2ea6249c9387c8757827b63fb6e24b13'],
    ['sha256:03d4a4c3e6d268665495515859a5e87ee33a737469c9b642db6433f557ef3599',
      'sha256:3f300c394be6861870871a168e2f9e5a56185a73993ca8c81bbd6ae35e219afb'],
  ]);
  const answers = [{level: 'low', reason: 'independent first Model reply'},
    {level: 'high', reason: 'independent second Model reply'}];
  const result = stage => ({result: {stage, result: 'rows'}});
  const on = [{left: 'id', right: 'id'}];
  const infer = (id, contract) => ({
    id, inputs: {rows: result('source')}, steps: [
      {from: 'rows', assert_rows: {unique_by: ['id']}},
      {infer: {contract, key: 'id', input: {notes: {field: 'notes'}, active_users: {field: 'active_users'},
        trend: {field: 'trend'}}}, as: 'inferred'},
    ], results: {rows: {from: 'inferred', fields: ['id', 'outcome', 'value']}},
  });
  const program = {version: 'actql/0.1', id: 'native-file-two-model-join', stages: [
    {id: 'source', inputs: {account: {connector: connection, resource: 'accounts', view: 'records'},
      usage: {connector: connection, resource: 'usage', view: 'records'}}, steps: [{
      from: 'account', join: {with: 'usage', kind: 'inner', on, select: {
        id: 'left.id', notes: 'left.notes', active_users: 'right.active_users', trend: 'right.trend',
      }}, as: 'joined',
    }], results: {rows: {from: 'joined', fields: ['id', 'notes', 'active_users', 'trend']}}},
    infer('first', firstTask),
    infer('second', secondTask),
    {id: 'combined', inputs: {first: result('first'), second: result('second')}, steps: [{
      from: 'first', join: {with: 'second', kind: 'inner', on, select: {
        id: 'left.id', first_outcome: 'left.outcome', first_value: 'left.value',
        second_outcome: 'right.outcome', second_value: 'right.value',
      }}, as: 'joined',
    }], results: {rows: {from: 'joined',
      fields: ['id', 'first_outcome', 'first_value', 'second_outcome', 'second_value']}}},
  ], results: {answer: {from: {stage: 'combined', result: 'rows'}}}};
  return {connection, resources: views.map(({resource}) => resource), connections, catalog, payload, expectedInput,
    answers, program, modelRawDataPolicy, modelRawResponseViews, expectedRows: [{
      id: 'joined-1',
      first_outcome: 'ok', first_value: {level: 'low', reason: 'independent first Model reply'},
      second_outcome: 'ok', second_value: {level: 'high', reason: 'independent second Model reply'},
    }]};
}

// Every individual Task has one input row and one admitted attempt. Events
// from independent Tasks can interleave, so compare progression per attempt.
export function requireModelAttempts(events, count) {
  const attempts = new Map();
  for (const {identity, tag, ordinal} of events) {
    assert.match(identity, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(ordinal, 0);
    if (!attempts.has(identity)) attempts.set(identity, []);
    attempts.get(identity).push(tag);
  }
  assert.equal(attempts.size, count);
  for (const tags of attempts.values()) assert.deepEqual(tags, [0, 1, 2]);
  return [...attempts.keys()];
}
