import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const tryNumberIdentityLaw = {
  input: 'Admitted finite logical Number or canonical decimal String; no Boolean, Decimal, Signed64, temporal, structured or unknown-domain promotion.',
  number: 'Preserve the admitted Number value and canonical zero without formatting or parsing text. The result remains nullable Number. Ordinary scalar, Run, work, live-value, current and cancellation checks apply; no String parsing envelope or parsing workspace is issued for this branch.',
  string: 'Retain the existing canonical decimal grammar, full input consumption and nullable Number result. Only a non-null unparsable String becomes NULL. String profile admission, selected Host envelope, bounds and parsing workspace remain mandatory.',
  demand: 'Retain the authored try_number node and its original operand. Demand the child exactly once; child evaluation, control, cancellation, bounds, memory, engine and root-retirement failures propagate and never become NULL. NULL propagates after the original child succeeds.',
};

const profileSuffix = ' A try_number occurrence whose original checked operand is Number is an ordinary scalar identity, not a String parsing evaluation; it requires no text-time parsing profile or envelope. String occurrences retain the complete profile and envelope requirements.';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
export function verifyTryNumberIdentityContracts(write = false) {
  const expressionPath = 'spec/contracts/actql-expressions.json';
  const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
  const expression = read(expressionPath), scalar = read(scalarPath);
  if (write) {
    expression.laws.try_number = structuredClone(tryNumberIdentityLaw);
    for (const name of ['pure_profile_admission', 'profile_binding']) {
      if (!expression.laws[name].endsWith(profileSuffix)) expression.laws[name] += profileSuffix;
    }
    scalar.conversion_truth_table.try_number = structuredClone(tryNumberIdentityLaw);
    writeFileSync(expressionPath, JSON.stringify(expression, null, 2) + '\n');
    writeFileSync(scalarPath, JSON.stringify(scalar, null, 2) + '\n');
    const aoaPath = 'spec/contracts/actql-aoa.json', aoa = read(aoaPath);
    aoa.expression_contract_cid = machineCid(expression);
    aoa.rela_scalar_law_manifest_cid = machineCid(scalar);
    writeFileSync(aoaPath, JSON.stringify(aoa, null, 2) + '\n');
  }
  assert.deepEqual(expression.laws.try_number, tryNumberIdentityLaw);
  assert.deepEqual(scalar.conversion_truth_table.try_number, tryNumberIdentityLaw);
  for (const name of ['pure_profile_admission', 'profile_binding']) assert.ok(expression.laws[name].endsWith(profileSuffix));
  return {expression: machineCid(expression), scalar: machineCid(scalar)};
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log('TRY_NUMBER admitted Number identity:', verifyTryNumberIdentityContracts(process.argv.includes('--write')));
}
