import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {verifyIdentity} from './check-canonical-json.mjs';
import {validCheckOutcome} from '../packages/client-wire/index.mjs';

const read = path => JSON.parse(readFileSync(new URL('../' + path, import.meta.url), 'utf8'));
const independent = read('scripts/fixtures/check-consumer-condition-historical.json').checkSchemas;
const normative = read('spec/contracts/actql-protocol-schemas.json');
const fixtures = ['check-location-domains.json', 'check-template.verified.json',
  'check-capacity-required.json', 'check-unused-parameter.invalid.json',
  'check-numeric-profile-required.json', 'check-reporting-failure.json',
  'check-comment-fix.json', 'check-outcome-pins.verified.json',
  'check-requirement-omissions.invalid.json', 'check-binding-json-reasons.json',
  'check-default-type.invalid.json'];

for (const name of ['reason', 'outcome']) {
  test(`current check ${name} fixture identity matches its independent preimage and normative body`, () => {
    const original = independent[name];
    verifyIdentity(original.body, original.cid, original.canonicalPreimage);
    assert.deepEqual(original.body, normative.artifact_schemas['check_' + name]);
    assert.equal(original.cid, normative.artifact_schema_cids['check_' + name]);
  });
}

test('current check fixture headers use independently verified identities without accepting preceding originals', () => {
  for (const name of fixtures) {
    const fixture = read('packages/client-wire/fixtures/' + name);
    assert.equal(fixture.reason_schema_cid, independent.reason.cid, name);
    assert.equal(fixture.outcome_schema_cid, independent.outcome.cid, name);
    if (fixture.version !== 'actql-check-outcome/0.1') continue;
    assert.equal(validCheckOutcome(fixture), true, name);
    assert.equal(validCheckOutcome({...fixture,
      reason_schema_cid: 'sha256:1aa2b591972a9cd816826b6500f62ea38f8a4f5282e016b0d1153f8bb68e0742'}), false, name);
    assert.equal(validCheckOutcome({...fixture,
      outcome_schema_cid: 'sha256:b82a51998a31b6b6cb469fa366a497cea1b48a8b92ac73a5046dffb622b8bdce'}), false, name);
  }
  const comment = read('packages/client-wire/fixtures/check-comment-fix.json');
  assert.deepEqual(comment.report.runnable, {verdict: 'no', reasons: [{code: 'query_lexical_invalid'}]});
  const missing = structuredClone(comment); delete missing.report.runnable;
  assert.equal(validCheckOutcome(missing), false);
});
