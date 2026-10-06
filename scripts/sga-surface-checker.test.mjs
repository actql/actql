import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from
  '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalText} from './check-canonical-json.mjs';

const read = path => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
const {evidence_bundle_cid: ignored, ...body} = read('../spec/local-check-environment.json');
void ignored;
const environment = {...body, evidence_bundle_cid:cid(body)};
const numericProfile = read('../spec/contracts/actql-numeric-reduction.json');
const propertyLaw = read('../spec/dependencies/actql-graph-laws.json');

// Old tuple fixtures are historical evidence, not current successful runs.
// Current positive Plan, ownership, failure, cancellation and cleanup tests
// live in graph-surface-checker.test.mjs. Unsupported consumers use
// the one inventory-driven public Host refusal test, not this old fixture set.
test('retired tuple constructor is refused even with the current Graph profile installed', () => {
  const owner = moon.clientProgramCheckEnvironmentWithGraphProfile(
    canonicalText(environment), environment.evidence_bundle_cid,
    false, false, true, true, false, false, false, cid(numericProfile), cid(propertyLaw));
  assert.ok(owner, 'the current profile is admitted, so refusal is not missing installation');
  const historical = read('../spec/frontend/fixtures/sga-surface/match-projections.expected-program.json');
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
    canonicalText(historical), 'json', owner, undefined);
  assert.equal(moon.clientProgramPreparationReady(outcome), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(outcome), 'check_unsupported');
  assert.ok(moon.clientProgramPreparationIssue(outcome));
});
