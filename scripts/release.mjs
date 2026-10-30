// Local candidate freezing and read-only inspection only. Candidate JSON or
// flags cannot confer publisher authority, fetch a credential, stage a
// placeholder or move a tag.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {releasePlan} from './release-policy.mjs';
import {freezeReleaseSet, verifyReleaseSet, resumeReleaseSet, releaseSetSummary} from './release-set.mjs';

export async function runReleasePlan(args) {
  const [command, requestFile, ...rest] = args;
  assert.equal(command, 'plan', 'Only read-only plan is implemented; external release operations require a separate owner-approved executor');
  assert(requestFile && rest.length === 0, 'usage: release.mjs plan <release-request.json>');
  const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url), 'utf8'));
  const request = JSON.parse(await readFile(resolve(requestFile), 'utf8'));
  return releasePlan(request, policy);
}

export async function runRelease(args) {
  const [command, ...values] = args;
  if (command === 'plan') return runReleasePlan(args);
  if (command === 'freeze') {
    assert.equal(values.length, 3, 'usage: release.mjs freeze <request.json> <cohorts.json> <new-directory>');
    const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url), 'utf8'));
    return freezeReleaseSet({request: JSON.parse(await readFile(resolve(values[0]), 'utf8')),
      policy, cohorts: JSON.parse(await readFile(resolve(values[1]), 'utf8')), destination: values[2]});
  }
  if (['verify', 'summary', 'resume-plan'].includes(command)) {
    assert.equal(values.length, command === 'resume-plan' ? 3 : 2,
      'Supply the original directory and externally retained manifest SHA256; resume-plan also needs observation JSON');
    const fixed = await verifyReleaseSet(values[0], {expectedSha256: values[1]});
    if (command === 'summary') return releaseSetSummary(fixed);
    if (command === 'resume-plan') return resumeReleaseSet(fixed, JSON.parse(await readFile(resolve(values[2]), 'utf8')));
    return fixed;
  }
  throw new Error('External release operation is unavailable: only plan/freeze/verify/summary/resume-plan are implemented; no publication authority');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(await runRelease(process.argv.slice(2)), null, 2));
}
