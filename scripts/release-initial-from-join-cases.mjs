// Test inputs and selection only. Public product execution supplies all actual results.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonical} from './fixtures/two-source-public-query.mjs';

export const initialFromJoinNames = Object.freeze([
  'initial-join-flat', 'initial-join-select-from', 'initial-join-with',
]);
const leftFields = {id: {type: 'number', nullable: false}, amount: {type: 'number', nullable: true}};
const rightFields = {id: {type: 'number', nullable: false}, tag: {type: 'string', nullable: false}};
const cid = body => 'sha256:' + createHash('sha256').update(canonical(body)).digest('hex');
const seal = (body, key) => ({...body, [key]: cid(body)});

export function selectInitialFromJoinCases(vector) {
  assert.deepEqual(vector.expected_fields, [
    {name: 'id', type: 'number', nullable: false},
    {name: 'amount', type: 'number', nullable: true},
    {name: 'tag', type: 'string', nullable: false},
  ]);
  assert.equal(vector.expected_rows.length, 4);
  assert.equal(vector.left_rows.length, 3); assert.equal(vector.right_rows.length, 3);
  const projection = 'l.id AS id, l.amount AS amount, r.tag AS tag';
  const join = 'JOIN right_records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10';
  const order = 'ORDER BY amount ASC NULLS FIRST, tag';
  const columns = vector.expected_fields.map(({name, type, nullable}) => ({name, contract: {type, nullable}}));
  const definitions = [
    ['aql-text', `FROM left_records AS l ${join} |> SELECT ${projection} |> ${order}`],
    ['sql', `SELECT ${projection} FROM left_records AS l ${join} ${order}`],
    ['aql-text', `WITH joined AS (FROM left_records AS l ${join} |> SELECT ${projection}) FROM joined |> ${order} |> RESULT answer`],
  ];
  return definitions.map(([format, text], index) => ({name: initialFromJoinNames[index], format, text,
    expected: vector.expected_rows, columns, sourceReadSessionCount: 2}));
}

// Retype only declared reference positions. Business data and unrelated contracts
// are never traversed as references. These are new fixture identities, not old pins.
export function initialFromJoinFixture(vector, environments) {
  selectInitialFromJoinCases(vector);
  const left = structuredClone(environments.left), right = structuredClone(environments.right);
  const old = right.contract_registry.filter(value => value.kind === 'carrier_schema');
  assert.equal(old.length, 1);
  assert.deepEqual(old[0].body.fields, leftFields);
  assert.deepEqual(left.contract_registry.find(value => value.kind === 'carrier_schema').body.fields, leftFields);
  const {cid: oldSchemaCid, ...schemaBody} = old[0];
  const schema = seal({...schemaBody, body: {...schemaBody.body, fields: rightFields}}, 'cid');
  const [oldView] = right.source_views; assert.equal(right.source_views.length, 1);
  assert.equal(oldView.output.schema.cid, oldSchemaCid);
  const {contract_cid: oldViewCid, ...viewBody} = oldView;
  const view = seal({...viewBody, output: {...viewBody.output,
    schema: {...viewBody.output.schema, cid: schema.cid}}}, 'contract_cid');
  right.contract_registry = right.contract_registry.map(value => value.cid === oldSchemaCid ? schema : value);
  right.source_views = [view];
  assert.equal(right.connector_catalogs.length, 1);
  const {catalog_cid, ...catalog} = right.connector_catalogs[0];
  assert.deepEqual(catalog.source_views, [oldView]);
  right.connector_catalogs = [seal({...catalog,
    contracts: catalog.contracts.map(value => value.cid === oldSchemaCid ? schema : value),
    source_views: [view]}, 'catalog_cid')];
  for (const snapshot of right.schema_snapshots) {
    assert.equal(snapshot.source_contract_cid, oldViewCid);
    assert.equal(snapshot.source_view_contract_cid, oldViewCid);
    assert.equal(snapshot.carrier_schema_contract_cid, oldSchemaCid);
    snapshot.source_contract_cid = snapshot.source_view_contract_cid = view.contract_cid;
    snapshot.carrier_schema_contract_cid = schema.cid;
  }
  for (const capability of right.connector_capabilities) {
    assert.equal(capability.source_contract_cid, oldViewCid);
    assert.equal(capability.source_view_contract_cid, oldViewCid);
    capability.source_contract_cid = capability.source_view_contract_cid = view.contract_cid;
  }
  const {evidence_bundle_cid, ...environment} = right;
  return {initialFromJoin: true, rows: {left: vector.left_rows, right: vector.right_rows},
    environments: {left, right: seal(environment, 'evidence_bundle_cid')}};
}

export const releaseInitialFromJoinFixturePaths = Object.freeze([
  'scripts/release-initial-from-join-cases.mjs',
  'scripts/fixtures/release-initial-from-join-worker.mjs',
  'scripts/fixtures/initial-from-join/independent-vector.json',
  'scripts/fixtures/public-query-input.mjs',
  'scripts/fixtures/two-source-public-query.mjs',
  'scripts/fixtures/packed-query-transport-owner.mjs',
  'adapters/host-node/fixtures/two-source/left.environment.json',
  'adapters/host-node/fixtures/two-source/right.environment.json',
]);
