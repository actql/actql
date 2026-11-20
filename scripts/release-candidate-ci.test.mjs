import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {parse} from 'yaml';

const workflow = parse(readFileSync(new URL('../.github/workflows/release-candidate.yml', import.meta.url), 'utf8'));
const publicWorkflow = parse(readFileSync(new URL('../.github/workflows/release-public-check.yml', import.meta.url), 'utf8'));
const {jobs} = workflow;
const sourceRef = '${{ needs.source.outputs.sha }}';
const isAction = (step, name) => step.uses?.startsWith(`actions/${name}@`);
const action = (job, name) => job.steps.find(step => isAction(step, name));
const calls = (job, path) => job.steps.find(step => step.run?.includes(`scripts/${path}`));
const render = (text, context) => text.replace(/\$\{\{\s*(.*?)\s*\}\}/gu, (_, expression) => {
  if (expression === 'toJSON(needs)') return JSON.stringify(context.needs);
  const value = expression.split('||').map(path => path.trim().split('.')
    .reduce((parent, key) => parent?.[key], context)).find(value => Boolean(value));
  return value === undefined ? '' : String(value);
});
const run = (step, context, environment = {}) => spawnSync('bash', ['-e', '-o', 'pipefail', '-c', step.run], {
  encoding: 'utf8', timeout: 10000, env: {...process.env, ...environment,
    ...Object.fromEntries(Object.entries(step.env ?? {}).map(([key, value]) => [key, render(value, context)]))},
});

test('candidate source fixes PR head H and refuses invalid input without selecting event M', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-release-source-contract-'));
  t.after(() => rmSync(root, {recursive: true}));
  const step = jobs.source.steps.find(value => value.env?.CANDIDATE_SHA);
  assert.equal(step.env.CANDIDATE_SHA, '${{ github.event.pull_request.head.sha || github.sha }}');
  assert.equal(jobs.source.outputs.sha, '${{ steps.source.outputs.sha }}');
  assert.deepEqual(workflow.on.pull_request.branches, ['main']);
  assert.match(jobs.source.if, /startsWith\(github\.head_ref, 'release\/'\)/u);
  assert.match(jobs.source.if, /github\.event_name == 'workflow_dispatch'/u);
  const source = 'a'.repeat(40), merge = 'b'.repeat(40), output = join(root, 'outputs');
  const environment = {RUNNER_TEMP: root, GITHUB_OUTPUT: output, GITHUB_REPOSITORY: 'actql/actql',
    GITHUB_EVENT_NAME: 'pull_request', GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '2'};
  const result = run(step, {github: {event: {pull_request: {head: {sha: source}}}, sha: merge}}, environment);
  assert.equal(result.error, undefined); assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(output, 'utf8'), `sha=${source}\n`);
  const original = readFileSync(join(root, 'release-source.json'));
  assert.equal(JSON.parse(original).sourceSha, source); assert.equal(JSON.parse(original).eventSha, merge);
  writeFileSync(output, '');
  const refused = run(step, {github: {event: {pull_request: {head: {sha: 'invalid'}}}, sha: merge}}, environment);
  assert.notEqual(refused.status, 0); assert.equal(readFileSync(output, 'utf8'), '');
  assert.deepEqual(readFileSync(join(root, 'release-source.json')), original);
  const dispatched = run(step, {github: {event: {}, sha: merge}}, environment);
  assert.equal(dispatched.status, 0, dispatched.stderr);
  assert.equal(readFileSync(output, 'utf8'), `sha=${merge}\n`);
});

test('every builder and consumer checks out exact H with read-only credentials', () => {
  assert.equal(workflow.permissions.contents, 'read'); assert.equal(workflow.permissions.actions, 'read');
  for (const [name, job] of Object.entries(jobs)) {
    for (const permission of Object.values(job.permissions ?? {})) assert.notEqual(permission, 'write', name);
    for (const step of job.steps ?? []) {
      assert.equal(step['continue-on-error'], undefined, name);
      if (isAction(step, 'checkout')) {
        assert.equal(step.with.ref, sourceRef, name);
        assert.equal(step.with['persist-credentials'], false, name);
      }
      assert(!/\b(?:npm publish|npm dist-tag|git push|gh release create)\b/u.test(step.run ?? ''), name);
    }
  }
});

test('both Node native originals feed one four-package RC and all four compiler-free consumers', () => {
  const native = jobs['node-native'], producer = jobs['node-packages'], consumer = jobs['node-readme'];
  assert.deepEqual(new Set(native.strategy.matrix.include.map(row => row.target)), new Set(['linux-x64', 'darwin-arm64']));
  const context = {github: {run_id: '123', run_attempt: '2'}, needs: {source: {outputs: {sha: 'a'.repeat(40)}}}};
  const upload = action(native, 'upload-artifact');
  const expected = native.strategy.matrix.include.map(matrix => render(upload.with.name, {...context, matrix})).sort();
  const downloads = producer.steps.filter(step => isAction(step, 'download-artifact'));
  assert.deepEqual(downloads.map(step => render(step.with.name, context)).sort(), expected);
  for (const step of downloads) assert.equal(step.with['run-id'], undefined, 'No cross-run supplier selection');
  assert(calls(producer, 'packed-client-packages.mjs'));
  assert(calls(producer, 'package-release.mjs').run.includes('prepare'));
  const install = calls(producer, 'test-package-release-install.mjs'); assert(install);
  assert(producer.steps.indexOf(install) > producer.steps.indexOf(calls(producer, 'packed-client-packages.mjs')));
  const publicPaths = action(producer, 'upload-artifact').with.path.split('\n').filter(path => path.endsWith('-0.0.2.tgz'));
  assert.deepEqual(new Set(publicPaths.map(path => path.split('/').at(-1))), new Set([
    'actql-client-wire-0.0.2.tgz', 'actql-sdk-0.0.2.tgz', 'actql-local-node-0.0.2.tgz', 'actql-node-0.0.2.tgz']));
  assert.equal(action(consumer, 'download-artifact').with['artifact-ids'], '${{ needs.node-packages.outputs.artifact-id }}');
  assert.deepEqual(new Set(consumer.strategy.matrix.target), new Set(['linux-x64', 'darwin-arm64']));
  assert.deepEqual(new Set(consumer.strategy.matrix.node), new Set(['22.22.0', '24']));
  assert.equal(consumer.strategy['fail-fast'], false);
  assert(calls(consumer, 'test-package-release-readme.mjs'));
  assert(!consumer.steps.some(step => step.uses === './.github/actions/setup-toolchain'));
  assert(!consumer.steps.some(step => /\bmoon\b|scripts\/(?:build-runtime-packages|packed-client-packages|produce-native)/u.test(step.run ?? '')));
  assert.equal(action(consumer, 'upload-artifact').if, 'always()');
});

test('Native keeps both same-source inputs in one joint RC and measures only that Linux distribution', () => {
  const production = jobs['native-production'], packages = jobs['native-packages'], installed = jobs['native-installed'];
  assert.deepEqual(new Set(installed.needs), new Set(['source', 'native-packages', 'node-packages']));
  assert.deepEqual(new Set(production.strategy.matrix.include.map(row => row.platform)), new Set(['linux-x64-gnu', 'darwin-arm64']));
  assert.equal(production.env.SELECTED_SOURCE, sourceRef);
  const upload = action(production, 'upload-artifact');
  const context = {github: {run_id: '123', run_attempt: '2'}, needs: {source: {outputs: {sha: 'a'.repeat(40)}}}};
  const expected = production.strategy.matrix.include.map(matrix => render(upload.with.name, {...context, matrix})).sort();
  assert.deepEqual(packages.steps.filter(step => isAction(step, 'download-artifact'))
    .map(step => render(step.with.name, context)).sort(), expected);
  const prepare = calls(packages, 'native-cli-release.mjs');
  assert(prepare.run.includes('prepare-local'));
  assert(prepare.run.includes('release/0.0.2/native-cli-cohort.json'));
  for (const platform of ['linux', 'darwin']) assert(prepare.run.includes(`native-joint/${platform}/native-originals/production/artifact`));
  assert.equal(action(installed, 'download-artifact').with['artifact-ids'], '${{ needs.native-packages.outputs.artifact-id }}');
  assert.deepEqual(new Set(installed.strategy.matrix.include.map(row => row.platform)), new Set(['linux-x64-gnu', 'darwin-arm64']));
  const formal = calls(installed, 'test-native-approval-performance.mjs'); assert(formal);
  assert.equal(formal.if, "matrix.platform == 'linux-x64-gnu'");
  assert(formal.run.includes('--normal "$RUNNER_TEMP/native-installed/release"'));
  assert(!/--diagnostic|--binding/u.test(formal.run));
  assert(formal.run.includes('env -u TMPDIR -u TMP -u TEMP'));
  assert(calls(installed, 'test-native-cli-source-free-install.mjs'));
  assert(calls(installed, 'test-native-cli-mock-install.mjs').run.includes('--measure-approval-resources'));
  const mac = "matrix.platform == 'darwin-arm64'";
  const companion = installed.steps.find(step => isAction(step, 'download-artifact') &&
    step.with['artifact-ids'] === '${{ needs.node-packages.outputs.artifact-id }}');
  assert(companion, 'Mac sequences consume the existing exact Node artifact');
  assert.equal(companion.if, mac);
  assert.equal(companion.with['run-id'], undefined, 'No cross-run companion substitution');
  assert.equal(companion.with.path, '${{ runner.temp }}/native-installed/node-release-input');
  assert.equal(companion.with['merge-multiple'], true);
  const node24 = installed.steps.find(step => isAction(step, 'setup-node'));
  assert.equal(node24?.if, mac);
  assert.equal(node24.with['node-version'], '24');
  const functional = calls(installed, 'test-native-cli-mock-install.mjs');
  assert(installed.steps.indexOf(node24) > installed.steps.indexOf(calls(installed, 'test-native-cli-source-free-install.mjs')));
  assert(installed.steps.indexOf(node24) < installed.steps.indexOf(functional));
  assert.equal(functional['timeout-minutes'], 30);
  assert.equal(installed.strategy.matrix.include.find(row => row.platform === 'darwin-arm64').minutes, 65);
  const evidence = action(installed, 'upload-artifact'); assert.equal(evidence.if, 'always()');
  assert(evidence.with.path.includes('/tmp/actql-native-mock-install-*/commands.json'));
  assert(evidence.with.path.includes('native-installed/release/*.json'));
});

test('Mac project companion uses the original artifact and refuses foreign manifest bindings', t => {
  const installed = jobs['native-installed'], mac = "matrix.platform == 'darwin-arm64'";
  const id = installed.steps.find(step => step.env?.ARTIFACT_ID === '${{ needs.node-packages.outputs.artifact-id }}');
  const binding = installed.steps.find(step => step.env?.MANIFEST_SHA256 === '${{ needs.node-packages.outputs.manifest-sha256 }}');
  assert(id, 'Require the existing Node artifact ID before download');
  assert(binding, 'Bind the original Node manifest before the installed sequence consumer');
  assert.equal(id.if, mac); assert.equal(binding.if, mac);
  assert.equal(binding.env.CANDIDATE_SHA, sourceRef);
  const download = installed.steps.find(step => isAction(step, 'download-artifact') &&
    step.with['artifact-ids'] === '${{ needs.node-packages.outputs.artifact-id }}');
  assert(installed.steps.indexOf(id) < installed.steps.indexOf(download));
  assert(installed.steps.indexOf(download) < installed.steps.indexOf(binding));
  assert(installed.steps.indexOf(binding) < installed.steps.indexOf(calls(installed, 'test-native-cli-mock-install.mjs')));
  const originalInputs = action(jobs['node-packages'], 'upload-artifact').with.path;
  assert(originalInputs.includes('/node-release-rc/development/packed-client-packages.json'));
  for (const role of ['client-wire', 'sdk', 'local-node', 'node']) {
    assert(originalInputs.includes(`/node-release-rc/actql-${role}-0.0.2.tgz`));
    assert(originalInputs.includes(`/node-release-rc/development/actql-${role}-0.0.0-development.tgz`));
  }
  const root = mkdtempSync(join(tmpdir(), 'actql-rc-project-binding-'));
  t.after(() => rmSync(root, {recursive: true}));
  const directory = join(root, 'native-installed/node-release-input/node-release-rc');
  mkdirSync(directory, {recursive: true});
  const sha = 'a'.repeat(40);
  const context = (artifact, digest) => ({needs: {source: {outputs: {sha}},
    'node-packages': {outputs: {'artifact-id': artifact, 'manifest-sha256': digest}}}});
  for (const artifact of ['123', '', 'latest', '1;exit 0']) {
    const result = run(id, context(artifact, ''), {RUNNER_TEMP: root});
    assert.equal(result.error, undefined);
    assert.equal(result.status === 0, artifact === '123', artifact);
  }
  for (const variant of ['same', 'wrong-digest', 'wrong-source', 'missing-source', 'missing-file']) {
    const manifest = join(directory, 'release.json');
    const bytes = Buffer.from(JSON.stringify(variant === 'missing-source' ? {} :
      {sourceSha: variant === 'wrong-source' ? 'b'.repeat(40) : sha}));
    writeFileSync(manifest, bytes);
    const digest = variant === 'wrong-digest' ? 'c'.repeat(64)
      : createHash('sha256').update(bytes).digest('hex');
    if (variant === 'missing-file') rmSync(manifest);
    const result = run(binding, context('123', digest), {RUNNER_TEMP: root});
    assert.equal(result.error, undefined);
    assert.equal(result.status === 0, variant === 'same', result.stderr);
  }
});

test('the actual always-gate recipes reject failure, cancellation, skip and missing dependencies', () => {
  for (const [name, job] of ['node-check', 'native-check', 'release-check'].map(name => [name, jobs[name]])
    .concat([['pubcheck', publicWorkflow.jobs.pubcheck]])) {
    assert.match(job.if, /always\(\)/u);
    const step = job.steps.find(value => value.run);
    const needs = Object.fromEntries(job.needs.map(dependency => [dependency, {result: 'success'}]));
    assert.equal(run(step, {needs}).status, 0, name);
    for (const dependency of job.needs) for (const status of ['failure', 'cancelled', 'skipped', undefined]) {
      needs[dependency].result = status;
      assert.notEqual(run(step, {needs}).status, 0, `${name}:${dependency}:${status}`);
      needs[dependency].result = 'success';
    }
  }
  const reachable = new Set();
  function visit(name) {if (reachable.has(name)) return; reachable.add(name); for (const need of jobs[name].needs ?? []) visit(need);}
  visit('release-check');
  for (const name of ['source', 'node-native', 'node-packages', 'node-readme', 'native-production', 'native-packages', 'native-installed']) {
    assert(reachable.has(name), name);
  }
});

test('published acceptance is manual and reuses pinned original RCs without building or publishing', () => {
  assert.deepEqual(Object.keys(publicWorkflow.on), ['workflow_dispatch']);
  const inputs = publicWorkflow.on.workflow_dispatch.inputs;
  assert.deepEqual(new Set(Object.keys(inputs)), new Set(['candidate_sha', 'candidate_run_id', 'candidate_run_attempt',
    'node_artifact_id', 'native_artifact_id', 'node_manifest_sha256', 'native_manifest_sha256']));
  for (const input of Object.values(inputs)) {assert.equal(input.required, true); assert.equal(input.type, 'string');}
  assert.equal(publicWorkflow.permissions.actions, 'read'); assert.equal(publicWorkflow.permissions.contents, 'read');
  for (const [name, job] of Object.entries(publicWorkflow.jobs)) for (const step of job.steps) {
    if (isAction(step, 'checkout')) {
      assert.equal(step.with.ref, '${{ needs.candidate.outputs.sha }}');
      assert.equal(step.with['persist-credentials'], false);
    }
    assert(!/\b(?:npm publish|npm dist-tag|git push|moon build)\b|scripts\/(?:produce-native|build-runtime-packages|packed-client-packages)/u
      .test(step.run ?? ''), name);
    assert.notEqual(step.uses, './.github/actions/setup-toolchain', 'Public consumption has no compiler setup');
  }
  for (const [name, artifact] of [['node-public', 'node'], ['native-public', 'native']]) {
    const download = action(publicWorkflow.jobs[name], 'download-artifact');
    assert.equal(download.with['artifact-ids'], `\${{ needs.candidate.outputs.${artifact}-artifact-id }}`);
    assert.equal(download.with['run-id'], '${{ needs.candidate.outputs.run-id }}');
    assert.equal(download.with.repository, '${{ github.repository }}');
    assert.equal(download.with['github-token'], '${{ github.token }}');
    assert.equal(action(publicWorkflow.jobs[name], 'upload-artifact').if, 'always()');
  }
  assert.deepEqual(new Set(publicWorkflow.jobs['node-public'].strategy.matrix.node), new Set(['22.22.0', '24']));
  assert.deepEqual(new Set(publicWorkflow.jobs['node-public'].strategy.matrix.target), new Set(['linux-x64', 'darwin-arm64']));
  assert.deepEqual(new Set(publicWorkflow.jobs['native-public'].strategy.matrix.include.map(row => row.target)),
    new Set(['linux-x64-gnu', 'darwin-arm64']));
  const node = calls(publicWorkflow.jobs['node-public'], 'test-package-release-readme.mjs');
  assert(node.run.includes('--public-registry "$MANIFEST_SHA256"'));
  assert.equal(node.env.MANIFEST_SHA256, '${{ needs.candidate.outputs.node-manifest-sha256 }}');
  const native = calls(publicWorkflow.jobs['native-public'], 'test-native-cli-public-install.mjs');
  assert(native.run.includes('"$MANIFEST_SHA256" "$RUNNER_TEMP/native-public-receipt.json"'));
  assert.equal(native.env.MANIFEST_SHA256, '${{ needs.candidate.outputs.native-manifest-sha256 }}');
});

test('the actual public metadata recipe rejects wrong source run artifacts and latest before emitting consumer inputs', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-public-metadata-contract-'));
  t.after(() => rmSync(root, {recursive: true}));
  const sha = 'a'.repeat(40), runId = '123', attempt = '2', repository = 'actql/actql';
  const base = `https://api.github.com/repos/${repository}`;
  const runUrl = `${base}/actions/runs/${runId}/attempts/${attempt}`;
  const urls = [`${base}/actions/artifacts/11`, `${base}/actions/artifacts/12`];
  const fixtures = {[runUrl]: {id: 123, run_attempt: 2, status: 'completed', conclusion: 'success', head_sha: sha,
    repository: {full_name: repository}, head_repository: {full_name: repository},
    path: '.github/workflows/release-candidate.yml', event: 'pull_request'}};
  for (const [index, kind] of ['node', 'native'].entries()) fixtures[urls[index]] = {id: 11 + index,
    name: `${kind === 'node' ? 'node-release-rc' : 'native-public-0.0.2'}-${sha}-${runId}-${attempt}`,
    workflow_run: {id: 123, head_sha: sha}, expired: false, size_in_bytes: 1234, digest: `sha256:${'d'.repeat(64)}`};
  const names = ['@actql/client-wire', '@actql/sdk', '@actql/local-node', '@actql/node',
    'actql', '@actql/cli-linux-x64-gnu', '@actql/cli-darwin-arm64'];
  const tags = names.map(name => `https://registry.npmjs.org/-/package/${encodeURIComponent(name)}/dist-tags`);
  for (const url of tags) fixtures[url] = {latest: '0.0.2'};
  const preload = join(root, 'fetch.cjs');
  writeFileSync(preload, `const fs=require('node:fs'),assert=require('node:assert/strict');
    const replies=JSON.parse(fs.readFileSync(process.env.FETCH_FIXTURE));
    globalThis.fetch=async(url,options)=>{assert(Object.hasOwn(replies,String(url)));
      if(String(url).startsWith('https://registry.npmjs.org/'))assert.equal(options.headers.authorization,undefined);
      else assert.equal(options.headers.authorization,'Bearer fixture-read-token');
      return new Response(JSON.stringify(replies[String(url)]),{status:200});};\n`);
  const step = publicWorkflow.jobs.candidate.steps.find(value => value.env?.CANDIDATE_RUN_ID);
  const context = {inputs: {candidate_sha: sha, candidate_run_id: runId, candidate_run_attempt: attempt,
    node_artifact_id: '11', native_artifact_id: '12', node_manifest_sha256: 'b'.repeat(64),
    native_manifest_sha256: 'c'.repeat(64)}, github: {token: 'fixture-read-token'}};
  const mutations = [null, value => {value[runUrl].conclusion = 'failure';},
    value => {value[runUrl].head_sha = 'e'.repeat(40);}, value => {value[urls[0]].workflow_run.id = 124;},
    value => {value[urls[1]].expired = true;}, value => {value[urls[0]].name += '-different-attempt';},
    value => {value[tags.at(-1)].latest = '0.0.1';}];
  for (const [index, mutate] of mutations.entries()) {
    const directory = join(root, String(index)); mkdirSync(directory);
    const responses = structuredClone(fixtures); mutate?.(responses);
    const fixturePath = join(directory, 'responses.json'), output = join(directory, 'outputs');
    writeFileSync(fixturePath, JSON.stringify(responses)); writeFileSync(output, '');
    const result = run(step, context, {NODE_OPTIONS: `--require=${preload}`, FETCH_FIXTURE: fixturePath,
      RUNNER_TEMP: directory, GITHUB_OUTPUT: output, GITHUB_REPOSITORY: repository});
    assert.equal(result.error, undefined);
    if (mutate === null) {
      assert.equal(result.status, 0, result.stderr);
      const report = JSON.parse(readFileSync(join(directory, 'public-inputs.json')));
      assert.deepEqual(report.latest.map(row => row.name), names);
      assert.equal(report.sourceSha, sha); assert.match(readFileSync(output, 'utf8'), /node-artifact-id=11/u);
    } else {
      assert.notEqual(result.status, 0); assert.equal(readFileSync(output, 'utf8'), '');
      assert.equal(existsSync(join(directory, 'public-inputs.json')), false);
    }
  }
});
