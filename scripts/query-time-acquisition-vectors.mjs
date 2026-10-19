import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {generateQueryEvidenceVectors} from './query-evidence-vectors.mjs';

const hash = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
export function queryTimeAcquisitionVectors(originals) {
  const requirement = originals[0].body;
  const observation = originals[2].body;
  const access = originals[5].body;
  // Independently authored correspondence data, not admitted Runs, provider
  // evidence or values obtained from a product preparation/clock/runtime.
  return ['first-original-run', 'second-original-run'].flatMap(name => {
    const owner = {...requirement.owner, run_definition_cid: hash({fixture_run_definition: name})};
    const bound = {...requirement, owner};
    const completed = {...observation, owner, requirement_cid: hash(bound),
      actual_access: {...observation.actual_access,
        scope_cid: hash({...access, requirement_cid: hash(bound)})}};
    return [bound, completed].map(body => ({body, cid: hash(body)}));
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const originals = JSON.parse(readFileSync('portability/corpus/query-acquisition-identities.json', 'utf8'));
  const records = queryTimeAcquisitionVectors(originals);
  const path = 'portability/corpus/query-time-acquisition-identities.json';
  const moon = 'src/canonical_json/query_time_acquisition.generated_test.mbt';
  const generated = generateQueryEvidenceVectors('query_time_acquisition', records);
  if (process.argv.includes('--write')) {
    writeFileSync(path, JSON.stringify(records, null, 2) + '\n');
    writeFileSync(moon, generated);
  }
  assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), records);
  assert.equal(readFileSync(moon, 'utf8'), generated);
}
