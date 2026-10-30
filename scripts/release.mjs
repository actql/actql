// The initial common entry is read-only. Candidate JSON/flags cannot confer
// publisher authority, fetch a credential, stage a placeholder or move a tag.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {releasePlan} from './release-policy.mjs';

export async function runReleasePlan(args) {
  const [command, requestFile, ...rest] = args;
  assert.equal(command, 'plan', 'Only read-only plan is implemented; external release operations require a separate owner-approved executor');
  assert(requestFile && rest.length === 0, 'usage: release.mjs plan <release-request.json>');
  const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url), 'utf8'));
  const request = JSON.parse(await readFile(resolve(requestFile), 'utf8'));
  return releasePlan(request, policy);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(await runReleasePlan(process.argv.slice(2)), null, 2));
}
