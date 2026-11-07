import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {authoredCommandProjection} from './installed-authored-command.mjs';
import {canonicalJson} from './local-account-config.mjs';
const cid = value => 'sha256:' + createHash('sha256').update(canonicalJson(value)).digest('hex');
const contract = body => ({...body, cid: cid(body)});
function fixture() {
  const role = contract({schema: 'actql.contract/0.1', id: 'fixture.input', version: 'external',
    kind: 'command_input', body: {type: 'object', fields: {}, additional_properties: false}});
  const body = {schema: 'actql.command_contract/0.1', connector_id: 'fixture', command_id: 'command:write',
    input_schema: {id: role.id, version: role.version, cid: role.cid}, permissions: ['files.write']};
  const command = {...body, contract_cid: cid(body)};
  const catalog = {schema: 'actql.connector_catalog/0.1', connector_id: 'fixture', connector_version: 'fixture',
    contracts: [], commands: [], source_views: []};
  const wire = canonicalJson({catalog_cid: cid(catalog), catalog: canonicalJson({...catalog, catalog_cid: cid(catalog)}),
    contracts: [], manifest_entry: '{}', view_bodies: [], evidence_schemas: [], evidence_capabilities: []});
  const commands = Object.freeze([Object.freeze({resource: 'files', body: canonicalJson(command)})]);
  const specification = Object.freeze({operation: 'files.write', commands, contracts: Object.freeze([canonicalJson(role)])});
  const quantity = Object.freeze({original: 'controlled construction quantity'}), quotes = [];
  const moon = {clientProgramInstalledSourceConstructionCapacity(...values) {quotes.push(values); return {$tag: 1, _0: quantity};}};
  return {wire, specification, command, role, quantity, quotes, moon};
}

test('authored Command composition retains exact contract bodies and source catalog while quoting before projection', () => {
  const f = fixture(), projection = authoredCommandProjection(f.moon, f.specification);
  assert.equal(projection.capacity(f.wire), f.quantity);
  assert.equal(f.quotes.length, 1);
  assert(f.quotes[0].every(value => typeof value === 'bigint' && value > 0n));
  const selected = projection.project(f.wire), catalog = JSON.parse(selected.declared.catalog);
  assert.deepEqual(catalog.commands, [f.command]);
  assert.deepEqual(catalog.contracts, [f.role]);
  assert.deepEqual(catalog.source_views, []);
  const {catalog_cid, ...preimage} = catalog;
  assert.equal(catalog_cid, cid(preimage));
  assert.deepEqual(selected.commands, [{resource: 'files', commandRef: f.command.command_id,
    commandCid: f.command.contract_cid, body: canonicalJson(f.command)}]);
  assert.equal(selected.definition.rowOperations[0].operation, 'files.write');
});

test('authored Command refuses changed identity foreign connector duplicate command and getter inputs', () => {
  const f = fixture();
  for (const command of [{...f.command, contract_cid: 'sha256:' + '0'.repeat(64)},
    {...f.command, connector_id: 'foreign'}]) {
    const commands = Object.freeze([Object.freeze({resource: 'files', body: canonicalJson(command)})]);
    assert.throws(() => authoredCommandProjection(f.moon, Object.freeze({...f.specification, commands})).project(f.wire));
  }
  const commands = Object.freeze([...f.specification.commands, ...f.specification.commands]);
  assert.throws(() => authoredCommandProjection(f.moon, Object.freeze({...f.specification, commands})).project(f.wire));
  let calls = 0;
  const getter = Object.freeze({get operation() {calls++; return 'files.write';},
    commands: f.specification.commands, contracts: f.specification.contracts});
  assert.throws(() => authoredCommandProjection(f.moon, getter));
  assert.equal(calls, 0);
  assert.throws(() => authoredCommandProjection(f.moon, new Proxy(f.specification, {})));
  assert.equal(f.quotes.length, 0);
});
