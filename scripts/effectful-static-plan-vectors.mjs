import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {positiveEffectfulPlans, negativeEffectfulPlans} from './fixtures/effectful-static-plan-vectors.mjs';

// Only independently authored fixture inputs are emitted. The product issuer
// is not called to create expected bytes, classifications or identities.
export function effectfulStaticPlanVectors() {
  let text = '// Generated from independently authored Effectful static Plan vectors.\n';
  for (const [accepted, values] of [[true, positiveEffectfulPlans], [false, negativeEffectfulPlans]]) {
    values.forEach((value, index) => {
      text += `\n///|\ntest "Effectful static closed ${accepted ? 'positive' : 'negative'} ${index}" {\n` +
        `  assert_${accepted ? 'true' : 'false'}(parse_interactive_run_control_shape(\n` +
        `    "effectful_static_plan_view", ${JSON.stringify(canonicalText(value))}, 20000, 2000, 32,\n` +
        `  ) is Ok(_))\n}\n`;
    });
  }
  return execFileSync((process.env.MOON_HOME ? process.env.MOON_HOME + '/bin/' : '') + 'moonfmt',
    ['-'], {input: text, encoding: 'utf8'});
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'src/run_publication/effectful_static_plan.generated_wbtest.mbt';
  const content = effectfulStaticPlanVectors();
  if (process.argv.includes('--write')) writeFileSync(path, content);
  else assert.equal(readFileSync(path, 'utf8'), content, 'Stale Effectful static Plan vectors');
}
