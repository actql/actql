// One value-identity scenario of the installed row Effect, run as a node:test
// file with `--experimental-test-module-mocks`
// (installed-salesforce-effect.test.mjs runs it). The real Salesforce write
// driver is wrapped so that one fact it reports differs from the Program or
// the provider's reply only by Unicode normalization:
// - `value`: the request's value is reported composed; the Program's is
//   decomposed.
// - `target`: the request's target is reported composed; the Program's
//   selector is decomposed.
// - `outcome`: the provider's failure outcome carries decomposed text and
//   CRLF, which the Ledger must keep exactly.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import test, {mock} from 'node:test';

const scenario = process.env.ACTQL_ROW_VALUE_SCENARIO;
const decomposed = 'é';
const composed = 'é';
const driverUrl = new URL('../host/salesforce-write-driver.mjs',
  import.meta.url).href;
const ledgerUrl = new URL('../../../host-node/effect-ledger.mjs',
  import.meta.url).href;
const realDriver = await import(`${driverUrl}?unwrapped`);
const realLedger = await import(`${ledgerUrl}?unwrapped`);
const outcomeWires = [];
const prefixed = (prefix, value) => typeof value === 'string'
  ? `${prefix}${value}` : value;
const unprefixed = value => typeof value === 'string' &&
  value.startsWith(decomposed) ? value.slice(decomposed.length) : value;

mock.module(driverUrl, {namedExports: {...realDriver,
  salesforceWriteDriver(options) {
    const driver = realDriver.salesforceWriteDriver(options);
    if (scenario === 'value') {
      return Object.freeze({...driver, requestFacts(request) {
        const facts = driver.requestFacts(request);
        return {...facts, value: Object.fromEntries(Object.entries(
          facts.value).map(([key, item]) => [key, typeof item === 'string'
          ? item.normalize('NFC') : item]))};
      }});
    }
    if (scenario === 'target') {
      // The provider sees the plain record Id; the driver reports the target
      // with a composed prefix where the Program's selector has it
      // decomposed.
      return Object.freeze({...driver,
        prepareRequest: facts => driver.prepareRequest({...facts,
          selector: unprefixed(facts.selector)}),
        requestFacts(request) {
          const facts = driver.requestFacts(request);
          return {...facts, target: prefixed(composed, facts.target)};
        },
        async observeTargets(facts) {
          return (await driver.observeTargets(facts)).map(row =>
            ({...row, identity: prefixed(composed, row.identity)}));
        }});
    }
    if (scenario === 'outcome') {
      return Object.freeze({...driver, project(facts) {
        const projected = driver.project(facts);
        if (projected?.kind !== 'typed-failure-response') return projected;
        return {...projected, outcome: {...projected.outcome, error: {
          ...projected.outcome.error,
          message: `${decomposed}\r\nrejected`}}};
      }});
    }
    throw new Error(`Unknown scenario ${scenario}`);
  }}});
mock.module(ledgerUrl, {namedExports: {...realLedger,
  openEffectLedger(options) {
    const ledger = realLedger.openEffectLedger(options);
    return Object.freeze({...ledger, recordAdmittedRowOutcome(facts) {
      outcomeWires.push(facts.outcomeWire);
      return ledger.recordAdmittedRowOutcome(facts);
    }});
  }}});

const {effectHost, effectProgram, installedEffect} = await import(
  './installed-salesforce-effect.fixture.mjs');
const writesOf = org => org.seen.filter(item => item.method === 'PATCH' ||
  item.method === 'POST');
const schema = {id: {type: 'string', nullable: false},
  name: {type: 'string', nullable: false}};

test(`row Effect value identity: ${scenario}`, async t => {
  const installation = await installedEffect(t, {writes: [
    {resource: 'Test_Record__c', kind: 'update', fields: ['Name']}],
  ...(scenario === 'outcome' ? {org: {rejectWrites: [1]}} : {})});
  const host = await effectHost(t, installation,
    join(installation.root, 'host'));
  const [mapping] = host.installed.mappings;
  const id = scenario === 'target' ? `${decomposed}a00000000000001`
    : 'a00000000000001';
  const program = effectProgram({save: {update: {target: mapping.target,
    mapping: mapping.mappingRef, from: {result: 'rows'}, id: 'id',
    set: {Name: {field: 'name'}}}}}, [{id, name: `${decomposed}\r\nx`}],
  schema);
  const run = await host.run(program, `value-identity-${scenario}`).then(
    value => value, error => ({error}));
  if (scenario === 'outcome') {
    // The rejected write settles with exactly the provider's outcome text.
    assert.equal(writesOf(installation.org).length, 1);
    assert.equal(outcomeWires.length, 1);
    assert.equal(JSON.parse(outcomeWires[0]).error.message,
      `${decomposed}\r\nrejected`);
    assert.ok(outcomeWires[0].includes(JSON.stringify(
      `${decomposed}\r\nrejected`)), outcomeWires[0]);
    return;
  }
  // The request differs from the Program only by normalization: the common
  // owner refuses it as another request, before any later check or send.
  assert.equal(run.error?.code, 'ForeignInstalledRowEffectRequest',
    String(run.error?.stack));
  assert.equal(writesOf(installation.org).length, 0);
});
