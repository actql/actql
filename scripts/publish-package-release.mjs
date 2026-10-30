// Explicit operator action after release GO. No workflow, install or import
// publishes anything. Existing immutable versions must have identical bytes.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {publicationPlan, publishedVersion, verifyPackageRelease} from './package-release.mjs';
import {refuseUnconfiguredPublication} from './release-authority.mjs';

export async function publishPackageRelease({directory, executePublish, fetchMetadata = fetch, verify = verifyPackageRelease}) {
  const manifest = await verify(directory);
  // Inspect the whole cohort first, so an occupied conflicting version does
  // not cause an avoidable partial publication of earlier dependencies.
  const plan = await publicationPlan(manifest, fetchMetadata);
  const receipts = join(directory, 'publication-receipts');
  await mkdir(receipts, {recursive: true});
  const manifestSha256 = createHash('sha256').update(await readFile(join(directory, 'release.json'))).digest('hex');
  for (const [index, action] of plan.entries()) {
    if (action.state === 'published-identical') continue;
    // Recheck immediately before publishing. Never overwrite, bump or silently
    // pick another tag when a version appeared between planning and execution.
    const item = manifest.packages[index];
    if (await publishedVersion(item, manifest.cohort.registry, fetchMetadata) === 'published-identical') continue;
    await executePublish({file: join(directory, item.file), registry: manifest.cohort.registry,
      access: manifest.cohort.access, tag: manifest.cohort.tag});
    // Command success is recorded separately from registry confirmation. If
    // confirmation fails, the next invocation authenticates existing bytes
    // first; it does not assume that the previous publication never happened.
    const receipt = {version: 'actql-package-publication/0.1', at: new Date().toISOString(),
      manifestSha256, sourceSha: manifest.sourceSha, name: item.name, packageVersion: item.version,
      integrity: item.integrity, registry: manifest.cohort.registry, commandSucceeded: true};
    const filename = `${index}-${Date.now()}-${crypto.randomUUID()}.json`;
    await writeFile(join(receipts, filename), `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
    assert.equal(await publishedVersion(item, manifest.cohort.registry, fetchMetadata), 'published-identical',
      'Publication not yet confirmed; preserve receipt and rerun inspection');
  }
  return publicationPlan(manifest, fetchMetadata);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [permission, input] = process.argv.slice(2);
  assert(permission === '--publish' && input, 'usage after release GO: publish-package-release.mjs --publish <RC-directory>');
  refuseUnconfiguredPublication();
  const directory = resolve(input);
  const manifest = await verifyPackageRelease(directory);
  const identity = execFileSync('npm', ['whoami', '--registry', manifest.cohort.registry,
    '--fetch-timeout=15000', '--fetch-retries=0'], {encoding: 'utf8', timeout: 20_000}).trim();
  assert(identity, 'Authenticated npm identity required');
  console.log(`Authenticated npm operator: ${identity}`);
  console.log(JSON.stringify(await publishPackageRelease({directory, executePublish({file, registry, access, tag}) {
    execFileSync('npm', ['publish', file, '--ignore-scripts', '--registry', registry, '--access', access, '--tag', tag],
      {stdio: 'inherit', timeout: 180_000});
  }}), null, 2));
}
