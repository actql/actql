import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/sheets/host_node/host_node.js';
import {createSheetsClearDriver, sheetsClearCommand} from '../host/sheets-clear-command.mjs';
import {sheetsRangeCommand, sheetsRangeReference} from '../host/sheets-range-command.mjs';

const site = {apiOrigin: 'https://sheets.example.test', spreadsheetId: 'book',
  gridRange: {sheetId: 7, startRow: 2, endRow: 4, startColumn: 1, endColumn: 3},
  columns: [{name: 'text', type: 'string', nullable: false},
    {name: 'flag', type: 'boolean', nullable: true}]};
const token = character => `sha256:${character.repeat(64)}`;
const member = {resource: 'range_target', effectId: 'clear'};
function fixture() {
  const clear = sheetsClearCommand('sheets-book', site, provider);
  const target = sheetsRangeReference({site, catalogCid: token('a'), bindingCid: token('b'), moon: provider});
  let current = true;
  const driver = createSheetsClearDriver({moon: provider, site, command: clear.installed,
    target, bindingCid: token('b'), isCurrent: () => current});
  const request = driver.prepareRequest({member, value: {}, selector: target}).request;
  const entry = driver.recoveryEntry({member, entries: [{request}]});
  const body = {effects: [{effect_id: member.effectId, effect_kind: 'command',
    resolved_command_contract_cid: clear.installed.commandCid,
    changes: [{intended_changes: {value: {}}, target_row_identity: target}]}]};
  const durable = {connectorRecovery: [{...entry, memberIndex: 0}]};
  return {clear, target, driver, request, body, durable, revoke: () => { current = false; }};
}
const ack = request => ({spreadsheetId: 'book', replies: [{}, {createDeveloperMetadata: {
  developerMetadata: {metadataId: 17, metadataKey: 'actql_request', visibility: 'DOCUMENT',
    metadataValue: JSON.parse(request.body).requests[1].createDeveloperMetadata.developerMetadata.metadataValue,
    location: {sheetId: 7}}}}]});

test('clear selects a distinct empty-input Command and preserves the original update declaration', () => {
  const {clear} = fixture();
  assert.equal(clear.command.command_id, 'command:sheets-book.sheets.clear_range.v1');
  assert.deepEqual(clear.command.input_contract.fields, {});
  assert.deepEqual(clear.command.permissions, ['sheets:cells:clear']);
  assert.equal(Object.hasOwn(clear.command, 'minimum_approval'), false);
  const old = JSON.parse(readFileSync(new URL('./fixtures/range-owned-baseline.json', import.meta.url), 'utf8'));
  const update = sheetsRangeCommand('sheets-book', site, provider);
  const current = JSON.parse(readFileSync(new URL('./fixtures/range-command-approval-carriage.json', import.meta.url), 'utf8'));
  assert.equal(current.predecessor.command.contract_cid, old.commandCid);
  assert.deepEqual(update.command, current.current.command);
  assert.equal(update.installed.commandCid, current.current.command.contract_cid);
  assert.equal(update.command.input_schema.cid, old.inputContractCid);
  assert.equal(update.command.output_schema.cid, old.outputContractCid);
});

test('clear prepares one immutable original marker in the same values-only batch', () => {
  const {driver, request, target} = fixture();
  assert.deepEqual(JSON.parse(request.body).requests[0], {updateCells: {
    range: {sheetId: 7, startRowIndex: 2, endRowIndex: 4, startColumnIndex: 1, endColumnIndex: 3},
    rows: [], fields: 'userEnteredValue'}});
  assert.equal(JSON.parse(request.body).requests.length, 2);
  assert.match(request.marker, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u);
  assert.deepEqual(driver.requestFacts(request), {value: {}, target});
  assert.equal(driver.requestCid(request), request.requestCid);
  const next = driver.prepareRequest({member, value: {}, selector: target}).request;
  assert.notEqual(next.marker, request.marker);
  assert.notEqual(next.requestCid, request.requestCid);
  assert.throws(() => { request.marker = next.marker; }, TypeError);
  assert.throws(() => { request.target.identity_cid = token('c'); }, TypeError);
});

test('clear refuses copied requests and equal configuration under another nominal binding', () => {
  const first = fixture(), other = fixture();
  assert.throws(() => first.driver.requestCid({...first.request}), {code: 'ForeignSheetsClearRequest'});
  assert.throws(() => other.driver.requestCid(first.request), {code: 'ForeignSheetsClearRequest'});
  assert.throws(() => first.driver.recoveryEntry({member, entries: [{request: {...first.request}}]}),
    {code: 'ForeignSheetsClearRequest'});
  assert.throws(() => other.driver.recoveryEntry({member, entries: [{request: first.request}]}),
    {code: 'ForeignSheetsClearRequest'});
});

test('clear refuses nonempty input and foreign or closed targets before physical dispatch', () => {
  const {driver, target, request, revoke} = fixture();
  for (const value of [{rows: []}, {text: ''}, null, []]) {
    assert.throws(() => driver.prepareRequest({member, value, selector: target}));
  }
  for (const field of ['provider_namespace', 'resource_kind', 'provider_identity_cid',
    'authority_scope_cid', 'boundary_cid', 'identity_cid']) {
    assert.throws(() => driver.prepareRequest({member, value: {}, selector: {
      ...target, [field]: field.endsWith('_cid') ? token('c') : 'other'}}),
    {code: 'SheetsRangeReferenceUnavailable'});
  }
  revoke();
  assert.throws(() => driver.requestCid(request), {code: 'SheetsRangeReferenceUnavailable'});
  assert.throws(() => driver.recoveryEntry({member, entries: [{request}]}),
    {code: 'SheetsRangeReferenceUnavailable'});
});

test('clear restore retains the original marker bytes and ordered request CID without a new prepare', () => {
  const {driver, request, body, durable} = fixture();
  const restored = driver.recoverRequests({body, durable}).requests[0][0];
  assert.notEqual(restored, request);
  assert.equal(restored.marker, request.marker);
  assert.equal(restored.body, request.body);
  assert.equal(driver.requestCid(restored), driver.requestCid(request));
  assert.deepEqual(driver.requestFacts(restored), driver.requestFacts(request));
  assert.deepEqual(driver.recoveryEntry({member, entries: [{request: restored}]}),
    driver.recoveryEntry({member, entries: [{request}]}));
});

test('clear restore refuses missing duplicate noncanonical and substituted original bindings', () => {
  const {driver, body, durable} = fixture();
  const original = durable.connectorRecovery[0];
  for (const entries of [[], [original, original], [{...original, memberIndex: 1}],
    [{...original, kind: 'another-provider'}], [{...original, wire: original.wire + '\n'}]]) {
    assert.throws(() => driver.recoverRequests({body, durable: {connectorRecovery: entries}}),
      {code: 'SheetsClearRecoveryMismatch'});
  }
  const changed = structuredClone(body);
  changed.effects[0].changes[0].intended_changes.value = {rows: []};
  assert.throws(() => driver.recoverRequests({body: changed, durable}));
});

test('clear only settles the exact two acknowledgements with the original range marker', () => {
  const {driver, request} = fixture();
  const project = (statusCode, response) => driver.project({request,
    observation: {statusCode, body: Buffer.from(JSON.stringify(response))}});
  assert.deepEqual(project(200, ack(request)), {kind: 'typed-success-response',
    outcome: {state: 'applied', result: {spreadsheet_id: 'book', sheet_id: 7, cleared_rows: 2}}});
  for (const status of [0, 400, 403, 409, 429, 500, 503]) {
    assert.deepEqual(project(status, ack(request)), {kind: 'provider-response'});
  }
  for (const mutate of [value => { value.replies.pop(); }, value => { value.replies.push({}); },
    value => { value.spreadsheetId = 'other'; },
    value => { value.replies[1].createDeveloperMetadata.developerMetadata.metadataValue = 'another-request'; },
    value => { value.replies[1].createDeveloperMetadata.developerMetadata.location.sheetId = 8; }]) {
    const response = ack(request); mutate(response);
    assert.deepEqual(project(200, response), {kind: 'provider-response'});
  }
  assert.throws(() => driver.project({request: {...request},
    observation: {statusCode: 200, body: Buffer.from(JSON.stringify(ack(request)))}}),
    {code: 'ForeignSheetsClearRequest'});
});
