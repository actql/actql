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
  const inputMarkers = ['account notes from the declared File', 'declining usage from the declared File'];
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
    {id: 'source', inputs: {account: {connector: connection, resource: 'accounts'},
      usage: {connector: connection, resource: 'usage'}}, steps: [{
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
  return {connection, resources: views.map(({resource}) => resource), connections, catalog, payload, inputMarkers,
    answers, program, expectedRows: [{
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
