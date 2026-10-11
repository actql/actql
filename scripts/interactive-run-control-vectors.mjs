import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {identityVectors, shapeVectors, negativeVectors, running, paused,
  manual, legacyState, bindingVectors, bindingMutations, planBody, ref} from './fixtures/interactive-run-control-vectors.mjs';

const quote = value => JSON.stringify(value);
export function generateControlVectors() {
  let source = '// Generated from independently authored Interactive Control vectors.\n';
  for (const [index, vector] of [...identityVectors, ...bindingVectors].entries()) {
    verifyIdentity(vector.body, vector.cid);
    const body = canonicalText(vector.body);
    const complete = canonicalText({...vector.body, self_cid: vector.cid});
    source += `\n///|\ntest "interactive identity ${index}: ${vector.name}" {\n` +
      `  let value = seal_run_evidence_value(${quote(vector.name)}, ${quote(body)}, 20000, 2000, 32).unwrap()\n` +
      `  assert_eq(run_evidence_value_identity(value), ${quote(vector.cid)})\n` +
      `  let restored = admit_run_evidence_value(${quote(vector.name)}, ${quote(complete)}, 20000, 2000, 32).unwrap()\n` +
      `  assert_eq(run_evidence_value_identity(restored), ${quote(vector.cid)})\n` +
      `  assert_true(parse_interactive_run_control_shape(${quote(vector.name)}, ${quote(complete)}, 20000, 2000, 32) is Ok(_))\n` +
      `}\n`;
  }
  for (const [expected, vectors] of [[true, shapeVectors], [false, negativeVectors]]) {
    for (const [index, vector] of vectors.entries()) {
      source += `\n///|\ntest "interactive ${expected ? 'positive' : 'negative'} ${index}: ${vector.name}" {\n` +
        `  assert_${expected ? 'true' : 'false'}(parse_interactive_run_control_shape(${quote(vector.name)}, ${quote(canonicalText(vector.value))}, 20000, 2000, 32) is Ok(_))\n}\n`;
    }
  }
  source += `\n///|\ntest "interactive legacy projection stays exact and rejects manual origins" {\n` +
    `  assert_eq(project_interactive_legacy_state(${quote(canonicalText(running))}, 20000, 2000, 32).unwrap(), ${quote(canonicalText(legacyState))})\n` +
    [paused, manual].map(state =>
      `  assert_eq(project_interactive_legacy_state(${quote(canonicalText(state))}, 20000, 2000, 32), Err(RunStateVersionUnsupported))\n`).join('') +
    `  assert_eq(project_interactive_legacy_state(${quote(canonicalText({...running, control_revision: 18}))}, 20000, 2000, 32), Err(LegacyProjectionMismatch("control_revision")))\n` +
    `}\n`;
  const bindingTest = (label, replacement, succeeds) => {
    const values = bindingVectors.map(vector => vector.name === replacement?.name
      ? replacement : vector);
    return `\n///|\ntest "interactive binding ${label}" {\n` +
      `  let plan = seal_publication_contract("compiled_plan", ${quote(canonicalText(planBody))}, 20000, 2000, 32).unwrap()\n` +
      `  let profile = seal_run_evidence_value("control_profile", ${quote(canonicalText(identityVectors[0].body))}, 20000, 2000, 32).unwrap()\n` +
      values.map((vector, index) => `  let value${index} = seal_run_evidence_value(${quote(vector.name)}, ${quote(canonicalText(vector.body))}, 20000, 2000, 32).unwrap()\n`).join('') +
      `  assert_${succeeds ? 'true' : 'false'}(check_interactive_admission_binding(value0, profile, profile, value1, value2, value3, plan, ${quote(ref.namespaceId)}, ${quote(ref.runDefinitionCid)}, 20000, 2000, 32) is Ok(_))\n}\n`;
  };
  source += bindingTest('original intent and input-only Plan map', null, true);
  for (const [index, mutation] of bindingMutations.entries())
    source += bindingTest(`rehashed substitution ${index}`, mutation, false);
  return execFileSync(process.env.MOON_HOME ? `${process.env.MOON_HOME}/bin/moonfmt`
    : 'moonfmt', ['-'], {input: source, encoding: 'utf8'});
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'src/run_publication/interactive_run_control.generated_wbtest.mbt';
  const source = generateControlVectors();
  if (process.argv.includes('--write')) writeFileSync(path, source);
  else assert.equal(readFileSync(path, 'utf8'), source, 'Stale control vectors');
}
