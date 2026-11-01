import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {inspect} from 'node:util';
import * as provider from '../../../../_build/js/release/build/connectors/sheets/host_node/host_node.js';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson, contentCid} from '../../../host-node/local-account-config.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {checkInstalledSheetsSourceProfile, checkInstalledSheetsEffectProfile}
  from '../host/installed-sheets.mjs';
import {createSheetsRangeDriver, sheetsRangeCommand, sheetsRangeReference,
  withSheetsRangeCommand} from '../host/sheets-range-command.mjs';
import {rangeProgram} from './sheets-range-program.fixture.mjs';

const site = {apiOrigin: 'https://sheets.example.test', spreadsheetId: 'book',
  gridRange: {sheetId: 7, startRow: 2, endRow: 4, startColumn: 1, endColumn: 3},
  columns: [{name: 'text', type: 'string', nullable: false},
    {name: 'flag', type: 'boolean', nullable: true}]};
const token = character => `sha256:${character.repeat(64)}`;
const profile = {siteProfilePath: '/fixture/site.json', publicationPath: '/fixture/publication.json',
  connectorId: 'sheets-book', accountConfigurationWire: '{}'};
const member = {resource: 'range_target', effectId: 'replace'};
const value = {rows: [{text: '=e\u0301\r\n', flag: false}, {text: 'second', flag: true}]};
function fixture() {
  const range = sheetsRangeCommand(profile.connectorId, site, provider);
  const target = sheetsRangeReference({site, catalogCid: token('a'), bindingCid: token('b'), moon: provider});
  let current = true;
  const driver = createSheetsRangeDriver({moon: provider, site, command: range.installed,
    target, bindingCid: token('b'), isCurrent: () => current});
  const request = driver.prepareRequest({member, value, selector: target}).request;
  const entry = driver.recoveryEntry({member});
  const body = {effects: [{effect_id: 'replace', effect_kind: 'command',
    resolved_command_contract_cid: range.installed.commandCid,
    changes: [{intended_changes: {value}, target_row_identity: target}]}]};
  const durable = {connectorRecovery: [{...entry, memberIndex: 0}]};
  return {driver, target, request, range, body, durable, revoke: () => { current = false; }};
}

test('Sheets range opt-in is closed and leaves existing append profiles unchanged', () => {
  const source = {...profile, version: 'actql-installed-sheets-source/0.1'};
  const append = {...profile, version: 'actql-installed-sheets-effect/0.1',
    sources: [{target: 'text', field: 'text', null_behavior: 'reject'}]};
  assert.deepEqual(checkInstalledSheetsSourceProfile(source), source);
  assert.deepEqual(checkInstalledSheetsEffectProfile(append), append);
  assert.deepEqual(checkInstalledSheetsSourceProfile({...source, rangeCommand: true}),
    {...source, rangeCommand: true});
  const range = {...profile, version: append.version, rangeCommand: true};
  assert.deepEqual(checkInstalledSheetsEffectProfile(range), range);
  for (const invalid of [{...range, sources: append.sources}, {...range, rangeCommand: false},
    {...range, rangeCommand: 'true'}, {...range, extra: true}]) {
    assert.throws(() => checkInstalledSheetsEffectProfile(invalid), /InvalidInstalledEffectProfile/);
  }
});

test('Sheets range Catalog and bounded Command input reach the existing common checker', () => {
  const schema = {target: {type: 'resource_ref', resource_kind: 'sheet_range', nullable: false}};
  const declaration = checked(common.clientProgramRowSourceRestoreRelationDeclaration(
    profile.connectorId, 'sheets', 'sheets/0.1', JSON.stringify({views: [{
      resource: 'range_target', resource_kind: 'sheet_range',
      schema_wire: canonicalJson(schema), schema_cid: contentCid(schema)}]}), undefined));
  const original = JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
  const range = sheetsRangeCommand(profile.connectorId, site, provider);
  const declared = withSheetsRangeCommand(original, range, provider);
  assert.notEqual(declared.catalog_cid, original.catalog_cid);
  assert.deepEqual(JSON.parse(original.catalog).commands, []);
  assert.deepEqual(JSON.parse(declared.catalog).source_views, JSON.parse(original.catalog).source_views);
  const base = readFileSync(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
  const {evidence_bundle_cid: _, ...body} = JSON.parse(rowSourceCheckEnvironment(base, declared).wire);
  body.command_contracts = [range.command];
  const cid = contentCid(body);
  const wire = canonicalJson({...body, evidence_bundle_cid: cid});
  assert(common.clientProgramCheckEnvironment(wire, cid, false, false, true, false, false, false, false));
  assert.deepEqual(range.command.input_contract.fields.rows.items.fields, {
    text: {type: 'string', nullable: false}, flag: {type: 'boolean', nullable: false}});
  assert.equal(range.command.input_contract.fields.rows.max_items, 2);
  assert.equal(Object.hasOwn(range.command, 'minimum_approval'), false);
  assert.equal(range.command.command_id, 'command:sheets-book.sheets.update_range.v0');
  assert.equal(range.command.target.resource_kind, 'sheet_range');
  assert.equal(range.command.idempotency.support, 'unsupported');
});

test('Sheets range authored Program reaches the existing effect preparation and compiler', () => {
  const columns = [{name: 'text', type: 'string', nullable: false},
    {name: 'number', type: 'number', nullable: true},
    {name: 'flag', type: 'boolean', nullable: true}];
  const range = sheetsRangeCommand(profile.connectorId, {...site,
    gridRange: {...site.gridRange, endColumn: 4}, columns}, provider);
  const schema = {target: {type: 'resource_ref', resource_kind: 'sheet_range', nullable: false}};
  const declaration = checked(common.clientProgramRowSourceRestoreRelationDeclaration(
    profile.connectorId, 'sheets', 'sheets/0.1', JSON.stringify({views: [{resource: 'range_target',
      resource_kind: 'sheet_range', schema_wire: canonicalJson(schema), schema_cid: contentCid(schema)}]}), undefined));
  const declared = withSheetsRangeCommand(
    JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration)), range, provider);
  const base = readFileSync(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
  const {evidence_bundle_cid: _, ...body} = JSON.parse(rowSourceCheckEnvironment(base, declared).wire);
  body.command_contracts = [range.command];
  const cid = contentCid(body);
  const environment = common.clientProgramCheckEnvironment(
    canonicalJson({...body, evidence_bundle_cid: cid}), cid, false, false, true, false, false, false, false);
  const rows = [{text: '=literal e\u0301\r\n', number: 0, flag: false},
    {text: 'second', number: -2.5, flag: true}];
  const outcome = common.clientProgramPrepareEffectComputationWithParameters(
    rangeProgram(range.command.command_id, rows, profile.connectorId), 'json', environment, undefined, []);
  const prepared = common.clientProgramEffectPreparationReady(outcome);
  assert(prepared, inspect(common.clientProgramEffectPreparationIssue(outcome),
    {depth: 9, maxArrayLength: 0, maxStringLength: 100, customInspect: false, getters: false}));
  const compiled = checked(common.clientProgramCompileLocalEffects(prepared));
  assert.deepEqual(common.clientProgramEffectCompilationResultNames(compiled), ['answer']);
});

test('Sheets range request binds original literal values exact rectangle and original Ref', () => {
  const {request, driver, target} = fixture();
  assert.deepEqual(JSON.parse(request.body), {requests: [{updateCells: {
    range: {sheetId: 7, startRowIndex: 2, endRowIndex: 4, startColumnIndex: 1, endColumnIndex: 3},
    rows: [{values: [{userEnteredValue: {stringValue: '=e\u0301\r\n'}},
      {userEnteredValue: {boolValue: false}}]},
    {values: [{userEnteredValue: {stringValue: 'second'}}, {userEnteredValue: {boolValue: true}}]}],
    fields: 'userEnteredValue'}}]});
  assert.deepEqual(driver.requestFacts(request), {value, target});
  assert.equal(driver.requestCid(request), request.requestCid);
  assert.throws(() => { request.value.rows[0].text = 'replacement'; }, TypeError);
  assert.throws(() => { request.target.identity_cid = token('c'); }, TypeError);
  assert.throws(() => driver.recheckRequests({entries: [{request: {...request}}]}),
    /ForeignSheetsRangeRequest/);
});

test('Sheets nominal request owner refuses same bytes under another permission or installation', () => {
  const first = fixture();
  const other = fixture();
  assert.equal(first.request.body, other.request.body);
  assert.equal(first.request.requestCid, other.request.requestCid);
  assert.throws(() => other.driver.recheckRequests({entries: [{request: first.request}]}),
    {code: 'ForeignSheetsRangeRequest'});
  const target = sheetsRangeReference({site, catalogCid: token('a'), bindingCid: token('c'), moon: provider});
  const driver = createSheetsRangeDriver({moon: provider, site, command: first.range.installed,
    bindingCid: token('c'), target, isCurrent: () => true});
  const request = driver.prepareRequest({member, value, selector: target}).request;
  assert.equal(request.body, first.request.body);
  assert.notEqual(request.requestCid, first.request.requestCid);
  assert.throws(() => driver.recheckRequests({entries: [{request: first.request}]}),
    {code: 'SheetsRangeReferenceUnavailable'});
  assert.throws(() => first.driver.recheckRequests({entries: [{request: {...first.request, target}}]}),
    {code: 'SheetsRangeReferenceUnavailable'});
});

test('Sheets body projection does not serialize a legal request into a second request-sized JSON envelope', () => {
  const {driver, target} = fixture();
  const large = {rows: [{text: '"'.repeat(49_900), flag: false}, {text: 'second', flag: true}]};
  assert(Buffer.byteLength(JSON.stringify(large)) < 100_000, 'existing common Effect value bound');
  const request = driver.prepareRequest({member, value: large, selector: target}).request;
  assert(Buffer.byteLength(request.body) < 300_000, 'original physical request clamp');
  assert.equal(JSON.parse(request.body).requests[0].updateCells.rows[0].values[0]
    .userEnteredValue.stringValue, large.rows[0].text);
  assert.equal(driver.requestCid(request), request.requestCid);
});

test('Sheets original configuration and footprint do not follow later caller DTO mutation', () => {
  const originalSite = structuredClone(site);
  const range = sheetsRangeCommand(profile.connectorId, originalSite, provider);
  const target = structuredClone(sheetsRangeReference({site: originalSite,
    catalogCid: token('a'), bindingCid: token('b'), moon: provider}));
  const driver = createSheetsRangeDriver({moon: provider, site: originalSite,
    command: range.installed, bindingCid: token('b'), target, isCurrent: () => true});
  const request = driver.prepareRequest({member, value, selector: target}).request;
  originalSite.apiOrigin = 'https://foreign.example.test';
  originalSite.gridRange.endRow = 9;
  originalSite.columns.reverse();
  target.boundary_cid = token('c');
  const again = driver.prepareRequest({member, value, selector: request.target}).request;
  assert.equal(again.body, request.body);
  assert.equal(driver.requestCid(again), request.requestCid);
  assert.equal(driver.footprint().boundaryCid, token('a'));
  const saved = JSON.parse(driver.recoveryEntry({member}).wire);
  assert.equal(saved.origin, site.apiOrigin);
  assert.deepEqual(saved.range, site.gridRange);
  assert.deepEqual(saved.columns, site.columns);
});

test('Sheets range refuses foreign current target installation and partial input before send', () => {
  const {driver, target, revoke, request} = fixture();
  for (const field of ['provider_namespace', 'resource_kind', 'provider_identity_cid',
    'authority_scope_cid', 'boundary_cid', 'identity_cid']) {
    assert.throws(() => driver.prepareRequest({member, value,
      selector: {...target, [field]: field.endsWith('_cid') ? token('c') : 'other'}}),
    /SheetsRangeReferenceUnavailable/);
  }
  for (const invalid of [{}, {...value, extra: 1}, {rows: value.rows.slice(0, 1)},
    {rows: [{text: null, flag: true}, value.rows[1]]},
    {rows: [{text: 'ok', flag: true, extra: 'ignored'}, value.rows[1]]}]) {
    assert.throws(() => driver.prepareRequest({member, value: invalid, selector: target}));
  }
  revoke();
  assert.throws(() => driver.recheckRequests({entries: [{request}]}), /SheetsRangeReferenceUnavailable/);
});

test('Sheets range recovery preserves original request bytes and never reacquires Source', () => {
  const {driver, durable, body, request} = fixture();
  const restored = driver.recoverRequests({durable, body}).requests[0][0];
  assert.equal(restored.body, request.body);
  assert.equal(driver.requestCid(restored), driver.requestCid(request));
  assert.deepEqual(driver.requestFacts(restored), driver.requestFacts(request));
  const changed = structuredClone(body);
  changed.effects[0].changes[0].intended_changes.value.rows[0].text = '=é\n';
  const different = driver.recoverRequests({durable, body: changed}).requests[0][0];
  // The existing common recoveredEntries guard compares this exact CID and
  // facts against the retained claim and sealed Preview; no equal-value lookup.
  assert.notEqual(driver.requestCid(different), request.requestCid);
});

test('Sheets range recovery refuses missing duplicate foreign and noncanonical retained bindings', () => {
  const {driver, durable, body} = fixture();
  const original = durable.connectorRecovery[0];
  for (const entries of [[], [original, original], [{...original, memberIndex: 1}],
    [{...original, kind: 'another-provider'}], [{...original, wire: original.wire + '\n'}]]) {
    assert.throws(() => driver.recoverRequests({body, durable: {connectorRecovery: entries}}),
      /SheetsRangeRecoveryMismatch/);
  }
  for (const mutate of [value => { delete value.range; }, value => { value.extra = true; },
    value => { value.range.sheetId = 8; }, value => { value.bindingCid = token('c'); },
    value => { value.columns.reverse(); }, value => { value.effectId = 'foreign'; }]) {
    const saved = JSON.parse(original.wire); mutate(saved);
    const changed = {...original, wire: canonicalJson(saved), observationCid: contentCid(saved)};
    assert.throws(() => driver.recoverRequests({body, durable: {connectorRecovery: [changed]}}),
      /SheetsRangeRecoveryMismatch/);
  }
});

test('Sheets range projection requires exact batch ACK and never settles an uncertain response', () => {
  const {driver, request} = fixture();
  const project = (statusCode, body) => driver.project({request,
    observation: {statusCode, body: Buffer.from(body)}});
  assert.deepEqual(project(200, '{"spreadsheetId":"book","replies":[{}]}'), {
    kind: 'typed-success-response', outcome: {state: 'applied', result: {
      spreadsheet_id: 'book', sheet_id: 7, acknowledged_rows: 2}}});
  for (const status of [0, 400, 403, 409, 429, 500, 503]) {
    assert.deepEqual(project(status, '{"spreadsheetId":"book","replies":[{}]}'), {kind: 'provider-response'});
  }
  for (const body of ['{}', '{"spreadsheetId":"other","replies":[{}]}',
    '{"spreadsheetId":"book","replies":[]}', '{"spreadsheetId":"book","replies":[{},{}]}']) {
    assert.deepEqual(project(200, body), {kind: 'provider-response'});
  }
});

// Count forwarding to this actual exported matcher only, including its
// canonical DATA fast path. This is a caller counter, NOT a full-validation
// counter, internal Native invocation count or performance measurement.
test('range original request does not repeat the exported target parser at CID and recheck boundaries',()=>{
  let completedMatches=0,current=true;
  const native=Object.freeze({...provider,sheetsRangeTargetMatches(...args){
    const result=Reflect.apply(provider.sheetsRangeTargetMatches,provider,args);completedMatches++;return result;
  }});
  const definition=sheetsRangeCommand('sheets-book',site,native);
  const target=sheetsRangeReference({site,catalogCid:token('a'),bindingCid:token('b'),moon:native});
  const driver=createSheetsRangeDriver({moon:native,site,command:definition.installed,target,bindingCid:token('b'),isCurrent:()=>current});
  const request=driver.prepareRequest({member,value:value,selector:target}).request;
  assert.equal(completedMatches,1,'New selector check stays before value encoding or marker construction');
  assert.equal(driver.requestCid(request),request.requestCid);
  driver.recheckRequests({entries:[{request}]});
  assert.equal(driver.requestCid(request),request.requestCid);
  assert.equal(completedMatches,1,'Original immutable request uses native original/binding admission');
  assert.throws(()=>driver.requestCid({...request}),{code:'ForeignSheetsRangeRequest'});
  assert.equal(completedMatches,2,'Foreign failure keeps the existing target-first diagnostic');
  assert.throws(()=>driver.requestCid({...request,target:{...target,boundary_cid:token('c')}}),{code:'SheetsRangeReferenceUnavailable'});
  assert.equal(completedMatches,3);
  current=false;
  assert.throws(()=>driver.requestCid(request),{code:'SheetsRangeReferenceUnavailable'});
  assert.equal(completedMatches,3,'Closed current fence precedes every native operation');
});
