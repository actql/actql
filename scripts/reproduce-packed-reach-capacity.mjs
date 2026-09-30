// Pending acceptance: explicit Result ordering currently fails compilation.
// Keep the desired rows and order intact; this is not a passing gate.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const installation = process.argv[2];
if (!installation || !process.env.ACTQL_LOCAL_STATE_DIR) {
  throw new Error('Provide packed installation and ACTQL_LOCAL_STATE_DIR');
}
const installed = createRequire(join(resolve(installation), 'package.json'));
const {connect} = await import(pathToFileURL(installed.resolve('@actql/node')));
const program = {
  version: 'actql/0.1', id: 'reach-capacity', stages: [{
    id: 'main', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false}},
        rows: [{id: 1}, {id: 2}, {id: 3}]}, as: 'nodes'},
      {values: {schema: {src: {type: 'number', nullable: false},
        dst: {type: 'number', nullable: false}},
        rows: [{src: 1, dst: 2}, {src: 2, dst: 3}]}, as: 'edges'},
      {graph: {nodes: {from: 'nodes', id: 'id', fields: []},
        edges: {from: 'edges', source: 'src', target: 'dst', fields: []}}, as: 'g'},
      {reach: {start: 1, direction: 'out', max_depth: 2}},
      {select: ['node_id', 'depth'], as: 'reached'},
    ], results: {answer: {from: 'reached', fields: ['node_id', 'depth'],
      order_by: [{node_id: 'desc'}]}},
  }], results: {answer: {from: {stage: 'main', result: 'answer'}}},
};
const client = await connect({mode: 'local', owner: 'local', durability: 'durable'});
try {
  const execution = await client.aql(JSON.stringify(program), {
    format: 'json', requestId: 'packed-reach-capacity',
  });
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = [{node_id: 3, depth: 2}, {node_id: 2, depth: 1},
    {node_id: 1, depth: 0}];
  assert.deepEqual(await execution.result('answer').all(), expected);
  const attached = await client.attach(execution.ref);
  assert.deepEqual(await attached.result('answer').all(), expected);
  console.log('Packed Local Reach: named rows and attach passed');
} finally {
  client.close();
}
