import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {buildClientHostWire} from './generate-client-host-wire.mjs';

const registry = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-client-host.json', import.meta.url), 'utf8'));
const protocol = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-protocol-schemas.json', import.meta.url), 'utf8'));

test('generated Client–Host guards and types match the machine contract',
  async () => {
    const outputs = buildClientHostWire(registry, protocol);
    assert.equal(outputs.module, await readFile(new URL(
      '../packages/client-wire/client-host.generated.js', import.meta.url),
    'utf8'));
    assert.equal(outputs.types, await readFile(new URL(
      '../packages/client-wire/client-host.generated.d.ts', import.meta.url),
    'utf8'));
  });

test('schema and operation mutations invalidate generated Client–Host wire',
  () => {
    const original = buildClientHostWire(registry, protocol);
    const changed = structuredClone(registry);
    changed.schemas.profile.properties.limits.properties.maxRows.minimum = 2;
    assert.notEqual(buildClientHostWire(changed, protocol).module,
      original.module);
    changed.operations.connect.push('nonce');
    assert.notEqual(buildClientHostWire(changed, protocol).module,
      original.module);
    changed.schemas.submit_preparation_error.properties.code.enum
      .push('UnexpectedSubmitError');
    assert.notEqual(buildClientHostWire(changed, protocol).types,
      original.types);
    changed.schemas.profile.properties.limits.properties.maxRows.type = 'number';
    assert.throws(() => buildClientHostWire(changed, protocol),
      /UnsupportedPublicationType/);
    const changedState = structuredClone(protocol);
    changedState.artifact_schemas.run_state.properties.run_id.minLength = 2;
    assert.notEqual(buildClientHostWire(registry, changedState).module,
      original.module);
  });

test('generated check validator rejects contradictory evidence and partial verification',
  async () => {
    const {validCheckOutcomeShape: valid} = await import(
      '../packages/client-wire/client-host.generated.js');
    const report = {context_ref: 'ctx:fixture', scope: {kind: 'bound_input'},
      verdict: 'verified', reasons: [], coverage: {limits: [], unresolved: []}};
    const outcome = report => ({version: 'actql-check-outcome/0.1',
      outcome: 'completed', report});
    assert.equal(valid(outcome(report)), true);
    for (const changed of [
      {...report, coverage: {limits: [{code: 'future_limit'}], unresolved: []}},
      {...report, coverage: {limits: [], unresolved: [
        {boundary: 'future_boundary', reason: 'unresolved_protected'}]}},
      {...report, reasons: [{code: 'future_violation'}]},
      {...report, verdict: 'invalid'},
      {...report, verdict: 'undetermined'},
      {...report, verdict: 'undetermined', reasons: [{code: 'future_violation'}]},
    ]) assert.equal(valid(outcome(changed)), false, JSON.stringify(changed));
    assert.equal(valid({version: 'actql-check-outcome/0.1', outcome: 'failed',
      problem: {code: 'future_problem'}, partial_report: report}), false);
    assert.equal(valid(outcome({...report, verdict: 'invalid',
      reasons: [{code: 'future_violation'}]})), true);
    assert.equal(valid(outcome({...report, verdict: 'undetermined',
      coverage: {limits: [{code: 'future_limit'}], unresolved: []}})), true);
  });
