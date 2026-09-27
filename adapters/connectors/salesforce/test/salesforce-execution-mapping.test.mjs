// Execution Mappings generated from a Site's declaration are the Mappings
// the common Effect Check and compile accept for the same write: no hand
// written Mapping, and none of the three writes is accepted by a Mapping of
// another write.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as salesforceMoon from
  '../../../../_build/js/release/build/connectors/salesforce/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {openSalesforceEffectSiteFixture} from
  './salesforce-effect-site.fixture.mjs';
import {declarationEnvironment} from
  './salesforce-declaration-environment.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const target = 'connector://crm-main/Test_Record__c';

// A Named Result of source rows; every Effect reads it.
function program(effect) {
  return JSON.stringify({version: 'actql/0.1', id: 'declared-writes',
    stages: [{id: 'source', inputs: {},
      steps: [{values: {schema: {
        id: {type: 'string', nullable: false},
        label: {type: 'string', nullable: false},
        key: {type: 'string', nullable: false}},
      rows: [{id: 'a00000000000001', label: 'one', key: 'key-1'}]},
      as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id', 'key', 'label']}},
      effects: {save: effect}}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}});
}

function prepare(environment, document) {
  const outcome = commonMoon.clientProgramPrepareEffectComputationWithParameters(
    document, 'json', environment, undefined, []);
  return {prepared: commonMoon.clientProgramEffectPreparationReady(outcome),
    issue: commonMoon.clientProgramEffectPreparationIssueCode(outcome)};
}

test('generated execution Mappings pass Effect Check and compile', async t => {
  const site = await openSalesforceEffectSiteFixture(t, {commonMoon,
    salesforceMoon, runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  const writes = {
    update: site.executionMapping({kind: 'update', fields: ['Name']}),
    upsert: site.executionMapping({kind: 'upsert', key: 'External_Key__c',
      fields: ['Name']}),
    create: site.executionMapping({kind: 'createFromResult', sources: [
      {target: 'External_Key__c', field: 'key', nullBehavior: 'reject'},
      {target: 'Name', field: 'label', nullBehavior: 'reject'}]}),
  };
  const {text, evidenceCid} = declarationEnvironment(site.declared,
    Object.values(writes).map(write => write.body));
  const environment = commonMoon.clientProgramCheckEnvironment(text,
    evidenceCid, false, false, true, false, false, false, false);
  assert.ok(environment);
  const effects = {
    update: {update: {target, mapping: writes.update.mappingRef,
      from: {result: 'rows'}, id: 'id', set: {Name: {field: 'label'}}}},
    upsert: {upsert: {target, mapping: writes.upsert.mappingRef,
      from: {result: 'rows'}, key: 'key', set: {Name: {field: 'label'}}}},
    create: {create: {target, mapping: writes.create.mappingRef,
      from: {result: 'rows'}}},
  };
  for (const [name, effect] of Object.entries(effects)) {
    const {prepared, issue} = prepare(environment, program(effect));
    assert.ok(prepared, `${name}: ${issue}`);
    const compiled = commonMoon.clientProgramCompileLocalEffects(prepared);
    assert.equal(commonMoon.clientProgramEffectCompilationIssueCode(compiled),
      undefined, name);
    assert.ok(checked(compiled), name);
  }
  // Each Mapping carries exactly its own write: an update of more fields,
  // an upsert through the update's Mapping, and an update through the
  // create's Mapping all fail Check.
  for (const effect of [
    {update: {...effects.update.update, set: {Name: {field: 'label'},
      External_Key__c: {field: 'key'}}}},
    {upsert: {...effects.upsert.upsert, mapping: writes.update.mappingRef}},
    {update: {...effects.update.update, mapping: writes.create.mappingRef}},
  ]) {
    assert.equal(prepare(environment, program(effect)).prepared, undefined);
  }
});
