// Local candidate freezing and read-only inspection only. Candidate JSON or
// flags cannot confer publisher authority, fetch a credential, stage a
// placeholder or move a tag.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {releasePlan} from './release-policy.mjs';
import {freezeReleaseSet, verifyReleaseSet, prepareReleaseReview, resumeReleaseSet, releaseSetSummary} from './release-set.mjs';
import {observeReleaseSet, observeReleaseChannels} from './release-registry.mjs';
import {promotionPlan} from './release-channels.mjs';
import {inspectReleaseSource, maintenanceReviewPlan} from './release-source.mjs';
import {npmStagePlan} from './publish-package-release.mjs';

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
  if (command === 'observe' || command === 'channels') {
    assert.equal(values.length, 2, 'usage: release.mjs observe|channels <fixed-directory> <externally-retained-sha256>');
    return (command === 'observe' ? observeReleaseSet : observeReleaseChannels)(values[0], values[1]);
  }
  if (command === 'review') {
    assert.equal(values.length, 4, 'usage: release.mjs review <preparation-directory> <externally-retained-SHA256> <review-request.json> <new-directory>');
    return prepareReleaseReview({directory: values[0], expectedSha256: values[1], reviewFile: values[2], destination: values[3]});
  }
  if (command === 'npm-stage-plan') {
    assert.equal(values.length, 3, 'usage: release.mjs npm-stage-plan <fixed-directory> <externally-retained-SHA256> <target-id>');
    return npmStagePlan(values[0], values[1], values[2]);
  }
  if (command === 'promotion-plan') {
    assert.equal(values.length, 4, 'usage: release.mjs promotion-plan <fixed-directory> <SHA256> <explicit-moves.json> <channel-report.json>');
    const fixed = await verifyReleaseSet(values[0], {expectedSha256: values[1]});
    const report = await readFile(resolve(values[3]));
    return promotionPlan(fixed, JSON.parse(await readFile(resolve(values[2]), 'utf8')),
      JSON.parse(report), createHash('sha256').update(report).digest('hex'));
  }
  if (command === 'source-plan' || command === 'maintenance-plan') {
    const minimum = command === 'source-plan' ? 2 : 3;
    assert(values.length === minimum || values.length === minimum + 1,
      'usage: source-plan <request.json> <repository> [branches.json] | maintenance-plan <request.json> <repository> <review.json> [branches.json]');
    const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url), 'utf8'));
    const branches = JSON.parse(await readFile(values[minimum] ? resolve(values[minimum])
      : new URL('../release/branches.json', import.meta.url), 'utf8'));
    const source = inspectReleaseSource({repository: resolve(values[1]), policy, branches,
      request: JSON.parse(await readFile(resolve(values[0]), 'utf8'))});
    return command === 'source-plan' ? source : maintenanceReviewPlan(source,
      JSON.parse(await readFile(resolve(values[2]), 'utf8')));
  }
  if (['verify', 'summary', 'resume-plan'].includes(command)) {
    assert.equal(values.length, command === 'resume-plan' ? 3 : 2,
      'Supply the original directory and externally retained manifest SHA256; resume-plan also needs observation JSON');
    const fixed = await verifyReleaseSet(values[0], {expectedSha256: values[1]});
    if (command === 'summary') return releaseSetSummary(fixed);
    if (command === 'resume-plan') return resumeReleaseSet(fixed, JSON.parse(await readFile(resolve(values[2]), 'utf8')));
    return fixed;
  }
  throw new Error('External release operation is unavailable: only local preparation, observation and review plans are implemented; no publication authority');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(await runRelease(process.argv.slice(2)), null, 2));
}
