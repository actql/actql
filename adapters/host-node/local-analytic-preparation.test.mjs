import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {machineCid} from '../../scripts/actql-spec-family.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {checkedRequestProgramPreparation} from './client-program-preparation.mjs';
import {publicClientErrorStatus, publicClientErrorCode} from './client-http.mjs';

const standard = JSON.parse(readFileSync('spec/local-check-environment.json', 'utf8'));
const fields = ['max_analytic_input_wire_bytes', 'max_analytic_output_wire_bytes',
  'max_analytic_partition_wire_bytes', 'max_analytic_frame_memberships'];
const query = expression => 'WITH t AS (SELECT 1 AS id, 3 AS v UNION ALL SELECT 2 AS id, 5 AS v) ' +
  `SELECT id, ${expression} AS total FROM t`;
function preparation(body) {
  const {evidence_bundle_cid: ignored, ...original} = body;
  const cid = machineCid(original);
  const environment = moon.clientProgramCheckEnvironmentWithGraphProfile(
    canonicalText({...original, evidence_bundle_cid: cid}), cid,
    true, true, true, true, true, false, false,
    machineCid(JSON.parse(readFileSync('spec/contracts/actql-numeric-reduction.json'))),
    machineCid(JSON.parse(readFileSync('spec/dependencies/actql-graph-laws.json'))));
  assert.ok(environment);
  return text => moon.clientProgramPrepareSourceWithParameters(text, 'sql', environment,
    JSON.stringify({environmentCid: cid, aliases: []}), undefined, undefined);
}
test('standard Local environment prepares cumulative SUM and ROW_NUMBER without injected policy', () => {
  const prepare = preparation(standard);
  for (const expression of ['SUM(v) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)',
    'ROW_NUMBER() OVER (ORDER BY id)']) assert.ok(moon.clientProgramPreparationReady(prepare(query(expression))));
});
test('each missing analytic ceiling is a known preparation refusal, never HTTP 500', () => {
  for (const field of fields) {
    const body = structuredClone(standard);
    delete body.host_policy_profile.capacity[field];
    const prepare = preparation(body);
    const result = prepare(query('ROW_NUMBER() OVER (ORDER BY id)'));
    assert.equal(moon.clientProgramPreparationIssueCode(result), 'check_invalid_configuration', field);
    // Exercise the ordinary Host projection with the original Core category.
    assert.throws(() => checkedRequestProgramPreparation(moon,
      {$tag: 0, _0: moon.clientProgramPreparationIssue(result)},
      () => moon.clientProgramPreparationIssueCode(result)), error => {
      assert.equal(error.code, 'ClientProgramRejected', field);
      assert.equal(publicClientErrorStatus(error), 422);
      assert.equal(publicClientErrorCode(error), 'ClientProgramRejected');
      return true;
    });
    assert.ok(moon.clientProgramPreparationReady(prepare('SELECT 9 AS healthy')));
  }
  assert.equal(publicClientErrorStatus({code: 'ClientProgramPreparationFailure'}), 500);
});
