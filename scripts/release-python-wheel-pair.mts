import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {openArtifactZip} from './ci-artifact-reader.mjs';
import type {ReleaseTarget} from './release-policy.mjs';

const platforms = ['linux-x64', 'darwin-arm64'] as const;
const roles = {sdk: 'actql-sdk', runtime: 'actql-local-runtime', facade: 'actql'} as const;
const sha = /^[a-f0-9]{64}$/u;
const id = /^[1-9][0-9]*$/u;
const maxJsonBytes = 4 * 1024 ** 2;
const cohortMember = 'cohort/cohort.json';
type Role = keyof typeof roles;
type Platform = typeof platforms[number];
type Wheel = {distribution: typeof roles[Role]; file: string; bytes: number; sha256: string};
type Archive = Awaited<ReturnType<typeof openArtifactZip>>;

const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

function record(value: unknown): Record<string, unknown> {
  assert(value && typeof value === 'object' && !Array.isArray(value), 'Expected Python release evidence object');
  return value as Record<string, unknown>;
}

function field(value: unknown, pattern: RegExp, message: string) {
  assert(typeof value === 'string' && pattern.test(value), message);
  return value;
}

function readJson(bytes: Buffer) {
  assert(bytes.length > 0 && bytes.length <= maxJsonBytes, 'Python release evidence exceeds its JSON byte bound');
  return record(JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)));
}

function wheel(value: unknown, role: Role): Wheel {
  const input = record(value);
  assert.deepEqual(Object.keys(input).sort(), ['bytes', 'distribution', 'file', 'sha256']);
  const distribution = roles[role];
  assert.equal(input.distribution, distribution, 'Foreign Python wheel distribution');
  const {bytes} = input;
  assert(typeof bytes === 'number' && Number.isSafeInteger(bytes) && bytes > 0, 'Invalid Python wheel length');
  const file = field(input.file, /^[A-Za-z0-9][A-Za-z0-9._-]*\.whl$/u, 'Invalid Python wheel filename');
  return {distribution, file, bytes, sha256: field(input.sha256, sha, 'Invalid Python wheel digest')};
}

function platformReceipt(value: unknown, platform: Platform, runId: string, attempt: string) {
  const input = record(value);
  assert.equal(input.platform, platform, 'Foreign Python platform receipt');
  assert.equal(input.producerArtifactName, `python-wheel-acceptance-${platform}-${runId}-${attempt}`,
    'Foreign Python producer archive name');
  assert.equal(input.producerRepository, 'actql/actql', 'Foreign Python producer repository');
  assert(typeof input.producerJobId === 'number' && Number.isSafeInteger(input.producerJobId) && input.producerJobId > 0,
    'Missing Python producer job ID');
  field(input.gateBSha256, sha, 'Missing Python Gate B digest');
  const pins = record(input.wheels);
  return {platform, producerJobId: input.producerJobId,
    producerArtifactId: field(input.producerArtifactId, id, 'Missing Python producer artifact ID'),
    archiveSha256: field(input.archiveSha256, sha, 'Missing Python producer archive digest'),
    manifestSha256: field(input.manifestSha256, sha, 'Missing Python producer cohort digest'),
    wheels: {sdk: wheel(pins.sdk, 'sdk'), runtime: wheel(pins.runtime, 'runtime'), facade: wheel(pins.facade, 'facade')}};
}

export function readPythonReleasePair(bytes: Buffer, source: string, version: string, target: ReleaseTarget) {
  assert.equal(target.ecosystem, 'pypi');
  assert.deepEqual([...target.platforms].sort(), [...platforms].sort(),
    'Python release requires exactly the selected Linux and Darwin platforms');
  assert.equal(version, '0.0.3', 'Paired Python release requires v0.0.3');
  const pair = readJson(bytes);
  assert.equal(pair.sourceSha, source, 'Foreign Python release pair source');
  assert.equal(pair.packageVersion, version, 'Foreign Python release pair version');
  const runId = field(pair.wheelRunId, id, 'Missing Python producer run ID');
  const attempt = field(pair.wheelRunAttempt, id, 'Missing Python producer run attempt');
  assert(Array.isArray(pair.platforms) && pair.platforms.length === 2, 'Both Python platform receipts are required');
  const linux = platformReceipt(pair.platforms[0], platforms[0], runId, attempt);
  const darwin = platformReceipt(pair.platforms[1], platforms[1], runId, attempt);
  assert.notEqual(linux.producerArtifactId, darwin.producerArtifactId, 'Python platforms need distinct original archives');
  assert.notEqual(linux.producerJobId, darwin.producerJobId, 'Python platforms need distinct original jobs');
  assert.deepEqual(linux.wheels.sdk, darwin.wheels.sdk, 'Python platforms need the same SDK wheel');
  assert.deepEqual(linux.wheels.facade, darwin.wheels.facade, 'Python platforms need the same facade wheel');
  assert.notEqual(linux.wheels.runtime.sha256, darwin.wheels.runtime.sha256,
    'Python runtime wheel digests must be distinct');
  const published = [linux.wheels.facade, linux.wheels.sdk, linux.wheels.runtime, darwin.wheels.runtime];
  assert.equal(new Set(published.map(item => item.file)).size, 4, 'Python release requires four distinct wheel files');
  assert.deepEqual(pair.publishWheels, published, 'Python wheel inventory differs from the original platform receipts');
  const receipts = [linux, darwin] as const;
  const origins = published.map(item => ({
    file: item.file,
    members: receipts.filter(receipt => Object.values(receipt.wheels).some(candidate => candidate.file === item.file))
      .map(({platform, producerArtifactId}) => ({platform, producerArtifactId, member: `cohort/wheels/${item.file}`})),
  }));
  assert.deepEqual(pair.publishWheelOrigins, origins, 'Python wheel origins differ from the original platform receipts');
  assert.deepEqual(target.packages, Object.values(roles), 'Python release requires all three projects in dependency order');
  const wheels = [linux.wheels.sdk, linux.wheels.runtime, darwin.wheels.runtime, linux.wheels.facade];
  return {receipts, wheels};
}

export async function openPythonReleasePair(bytes: Buffer, source: string, version: string, target: ReleaseTarget,
                                            paths: Record<Platform, string>) {
  const {receipts, wheels} = readPythonReleasePair(bytes, source, version, target);
  const archives: Archive[] = [];
  const wheelSources = new Map<string, Archive>();
  const manifests: {platform: Platform; bytes: Buffer}[] = [];
  const close = async () => {
    const results = await Promise.allSettled(archives.map(archive => archive.close()));
    const failed = results.filter(result => result.status === 'rejected');
    if (failed.length) throw new AggregateError(failed.map(result => result.reason), 'Failed to close Python producer archives');
  };
  try {
    for (const receipt of receipts) {
      const archive = await openArtifactZip(paths[receipt.platform], {expectedSha256: receipt.archiveSha256});
      archives.push(archive);
      const header = archive.entries.find(entry => entry.path === cohortMember);
      assert(header && header.bytes <= maxJsonBytes, 'Missing bounded original Python producer cohort');
      const manifestBytes = await archive.read(cohortMember);
      assert.equal(hash(manifestBytes), receipt.manifestSha256, 'Foreign Python producer cohort digest');
      const manifest = readJson(manifestBytes);
      assert.equal(manifest.source_sha, source, 'Foreign Python producer cohort source');
      assert.equal(manifest.package_version, version, 'Foreign Python producer cohort version');
      assert.equal(manifest.platform, receipt.platform, 'Foreign Python producer cohort platform');
      const cohortWheels = [receipt.wheels.sdk, receipt.wheels.runtime, receipt.wheels.facade];
      assert.deepEqual(manifest.wheels, cohortWheels, 'Foreign Python producer cohort wheel identities');
      manifests.push({platform: receipt.platform, bytes: manifestBytes});
      for (const item of cohortWheels) {
        const member = `cohort/wheels/${item.file}`;
        assert.equal(archive.entries.find(entry => entry.path === member)?.bytes, item.bytes,
          'Original Python wheel length mismatch');
        assert.equal(await archive.digest(member), item.sha256, 'Original Python wheel digest mismatch');
        if (!wheelSources.has(item.file)) wheelSources.set(item.file, archive);
      }
    }
    return {wheels, manifests, close, async readWheel(file: string) {
      const archive = wheelSources.get(file);
      assert(archive, 'Wheel is outside the selected Python release pair');
      return archive.read(`cohort/wheels/${file}`);
    }};
  } catch (error) {
    try {
      await close();
    } catch (cleanup) {
      throw new AggregateError([error, cleanup], 'Python producer archive verification and close failed');
    }
    throw error;
  }
}
