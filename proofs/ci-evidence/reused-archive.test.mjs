// Actual Git/ZIP/Lean/final-consumer composition. API/environment/image facts
// are explicit controlled fixtures, never live Actions or physical authority.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {archiveFixture, jsonBytes} from './final-archive-fixture.mjs';
import {storedArchive} from './archive-fixture.mjs';
import {hash, gitTree} from './inputs.mjs';
import {comparisonPlan} from './plan.mjs';
import {verifyCurrentFamily} from './final.mjs';
import {sealAcceptance, readReadyOrigin, acceptanceName} from './acceptance.mjs';
import {fullCheckpointJobs} from '../../scripts/ci-main-base.mjs';
import {gateJobs} from '../../scripts/ci-targets.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
// Two actual parent revisions with identical scientific/policy inputs. The
// second adds only the independent archive-construction fixture and its test.
const first = '3e59835ee2caedc4b4fbbf8e96abb2d85f96046a';
const second = '19f7b920fce6840524c7302138e46f65d623e46d';

test('real nested original/acceptance ZIPs satisfy the mixed final consumer and remain mandatory once reused', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-reused-archive-'));
  const historical = join(directory, 'fresh-main');
  let added = false;
  t.after(async () => {
    if (added) execFileSync('git', ['worktree', 'remove', historical], {cwd: root});
    await rm(directory, {recursive: true, force: true});
  });
  execFileSync('git', ['worktree', 'add', '--detach', '--quiet', historical, second], {cwd: root});
  added = true;

  const runs = new Map(), jobs = new Map(), artifacts = new Map(), archives = new Map();
  const request = async path => {
    if (path === '/actions/workflows/ci.yml') return {id: 2, path: '.github/workflows/ci.yml', state: 'active'};
    if (/^\/actions\/workflows\/2\/runs\?/u.test(path)) return {workflow_runs: [...runs.values()]};
    let match = /^\/actions\/runs\/(\d+)$/u.exec(path);
    if (match) return structuredClone(runs.get(Number(match[1])));
    match = /^\/actions\/runs\/(\d+)\/attempts\/(\d+)\/jobs\?per_page=100$/u.exec(path);
    if (match) {
      const entries = jobs.get(Number(match[1]));
      assert(entries.every(job => job.run_attempt === Number(match[2])));
      return {total_count: entries.length, jobs: structuredClone(entries)};
    }
    match = /^\/actions\/runs\/(\d+)\/artifacts\?per_page=100$/u.exec(path);
    if (match) {
      const entries = [...artifacts.values()].filter(value => value.workflow_run.id === Number(match[1]));
      return {total_count: entries.length, artifacts: structuredClone(entries)};
    }
    match = /^\/actions\/artifacts\/(\d+)$/u.exec(path);
    if (match) {assert(artifacts.has(Number(match[1]))); return structuredClone(artifacts.get(Number(match[1])));}
    assert.fail(`Unexpected controlled request: ${path}`);
  };
  const register = (fixture, checkId) => {
    runs.set(fixture.run.id, fixture.run); artifacts.set(fixture.artifact.id, fixture.artifact);
    archives.set(fixture.artifact.id, fixture.original);
    const complete = fullCheckpointJobs(gateJobs).map((name, index) => ({...fixture.job,
      id: name === 'session-evidence' ? fixture.job.id : name === 'check' ? checkId : 1000 + fixture.run.id * 100 + index,
      name}));
    jobs.set(fixture.run.id, complete);
  };
  const priorFetch = globalThis.fetch;
  // Execute the real bounded two-hop downloader over controlled responses.
  globalThis.fetch = async (url, options) => {
    const value = new URL(url);
    if (value.hostname === 'api.github.com') {
      const match = /\/actions\/artifacts\/(\d+)\/zip$/u.exec(value.pathname);
      assert(match && options.redirect === 'manual'); assert(options.headers.authorization);
      assert(archives.has(Number(match[1])));
      return new Response(null, {status: 302, headers: {location: `https://fixture.blob.core.windows.net/${match[1]}`}});
    }
    assert.equal(value.hostname, 'fixture.blob.core.windows.net');
    assert.equal(options.redirect, 'error'); assert.equal(options.headers?.authorization, undefined);
    return new Response(archives.get(Number(value.pathname.slice(1))), {status: 200});
  };
  t.after(() => {globalThis.fetch = priorFetch;});
  const compare = repository => ({context, catalog, runtime, actionRuntimes}) => comparisonPlan({root: repository,
    context, runtime, actionRuntimes, directory, token: 'controlled-fixture-only', request});

  const a = await archiveFixture(t, {revision: first, closed: true, requestFor: request});
  register(a, 7);
  const b = await archiveFixture(t, {repository: historical, revision: second, runId: 13, attempt: 1,
    jobId: 15, artifactId: 16, closed: true, requestFor: request, comparisonFor: compare(historical)});
  register(b, 17);
  const accepted = await verifyCurrentFamily({...b.options, token: 'controlled-fixture-only'});
  assert.equal(accepted.comparison.confirmation.status, 'confirmed');
  assert(accepted.applications.every(application => application.acquisition === 'fresh'));
  const {acceptanceInputs, ...result} = accepted;
  const acceptance = sealAcceptance({result, observations: acceptanceInputs.observations,
    owner: {runId: 13, runAttempt: 1, jobId: 17}, event: 'workflow_dispatch', branch: 'main',
    sourceArtifact: {id: 16, digest: hash(b.original)}, certificateDigest: hash(b.members.get('checked.json'))});
  assert.deepEqual(acceptance.ready.map(value => value.actionId), ['mutations-js']);
  const acceptanceBytes = storedArchive([['verified-family.json', jsonBytes(acceptance)]]);
  const acceptanceArchive = join(directory, 'acceptance.zip'); await writeFile(acceptanceArchive, acceptanceBytes);
  artifacts.set(18, {...b.artifact, id: 18, name: acceptanceName(b.options.context),
    digest: `sha256:${hash(acceptanceBytes)}`, size_in_bytes: acceptanceBytes.length});
  archives.set(18, acceptanceBytes);

  const candidate = await archiveFixture(t, {runId: 30, attempt: 1, jobId: 35, artifactId: 36,
    event: 'pull_request', branch: 'controlled-feature', closed: true, requestFor: request, comparisonFor: compare(root),
    reusedOriginal: {source: b.original, acceptance: acceptanceBytes, receipt: b.members.get('receipts/mutations-js.json')},
    readReady: (comparison, context) => readReadyOrigin({root, catalog: b.catalog, sourceArchive: b.options.archive,
      sourceArtifact: {id: 16, digest: hash(b.original)}, baseline: comparison.baseline, candidateContext: context,
      treeAt: revision => gitTree(root, revision), request, token: 'controlled-fixture-only', directory,
      artifactId: 18, archive: acceptanceArchive, expectedDigest: hash(acceptanceBytes)}),
  });
  register(candidate, 37);
  let index = 0;
  const consume = async (members = candidate.members) => {
    const out = join(directory, `consumer-${index++}`); await mkdir(out);
    const bytes = storedArchive(members), archive = join(out, 'candidate.zip'); await writeFile(archive, bytes);
    Object.assign(candidate.artifact, {digest: `sha256:${hash(bytes)}`, size_in_bytes: bytes.length});
    return verifyCurrentFamily({...candidate.options, directory: out, archive, expectedDigest: hash(bytes), token: 'controlled-fixture-only'});
  };
  const checked = await consume();
  assert.equal(checked.lean.accepted, true); assert.equal(checked.requiredActions.length, 30);
  assert.deepEqual(checked.applications.filter(value => value.acquisition === 'reused').map(value => value.actionId), ['mutations-js']);
  assert(checked.applications.filter(value => value.actionId !== 'mutations-js').every(value => value.acquisition === 'fresh'));
  assert.equal(checked.comparison.confirmation.status, 'confirmed');
  assert.deepEqual(checked.costObservation.actions.find(value => value.actionId === 'mutations-js').currentMilliseconds, null);
  assert.equal(checked.costObservation.netRunnerSavingsMilliseconds, null);
  assert(candidate.members.get('receipts/mutations-js.json').equals(b.members.get('receipts/mutations-js.json')));
  assert(!candidate.members.has('isolated-execution.json'));

  // Availability becomes mandatory once the candidate omitted the execution.
  const final = jobs.get(13).find(value => value.id === 17);
  final.conclusion = 'failure';
  await assert.rejects(consume(), /Required full main checkpoint no longer verifies/u); final.conclusion = 'success';
  artifacts.get(18).expired = true;
  await assert.rejects(consume(), {name: 'ArtifactUnavailable'}); artifacts.get(18).expired = false;
  for (const mutate of [
    members => members.delete('reused/session-origin.zip'),
    members => members.delete('reused/session-applicability.zip'),
  ]) {
    const members = new Map(candidate.members); mutate(members);
    await assert.rejects(consume(members), /Missing\/unbounded retained original/u);
  }
  const corrupted = new Map(b.members);
  corrupted.set('receipts/mutations-js.json', Buffer.from('changed original bytes'));
  const replaced = new Map(candidate.members); replaced.set('reused/session-origin.zip', storedArchive(corrupted));
  await assert.rejects(consume(replaced), /SHA-256|digest/u);
  runs.get(13).head_branch = 'feature';
  await assert.rejects(consume(), /protected main integration/u); runs.get(13).head_branch = 'main';
});
