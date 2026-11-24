// Validate the original producer outputs before a hosted consumer downloads
// its fixed Native CLI cohort. This does not qualify the installed payload.
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export function validateNativeCliArtifactInputs(env: Readonly<Record<string, string | undefined>>) {
  for (const key of ['ARTIFACT_ID', 'ARTIFACT_RUN_ID', 'ARTIFACT_RUN_ATTEMPT',
    'EXPECTED_RUN_ID', 'EXPECTED_RUN_ATTEMPT']) {
    assert.equal(typeof env[key], 'string', key);
    assert.match(env[key]!, /^[1-9][0-9]*$/u, key);
  }
  for (const key of ['ARTIFACT_SOURCE_SHA', 'EXPECTED_SOURCE_SHA']) {
    assert.equal(typeof env[key], 'string', key);
    assert.match(env[key]!, /^[a-f0-9]{40}$/u, key);
  }
  assert.equal(env.ARTIFACT_RUN_ID, env.EXPECTED_RUN_ID, 'Producer run differs');
  assert.equal(env.ARTIFACT_RUN_ATTEMPT, env.EXPECTED_RUN_ATTEMPT, 'Producer attempt differs');
  assert.equal(env.ARTIFACT_SOURCE_SHA, env.EXPECTED_SOURCE_SHA, 'Producer source differs');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  validateNativeCliArtifactInputs(process.env);
}
