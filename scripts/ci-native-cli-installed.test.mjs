// Scheduling/input guards only. Real package acceptance runs in its own job.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';
import {nativeCliTestCohort, requireNativeCliCiInputs} from './ci-native-cli-installed.mjs';
import {admitNativeReleaseCohort} from './native-cli-release.mjs';
import {gateJobs, gateJobRequired, selectTargets} from './ci-targets.mjs';

const {jobs} = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
test('ordinary Native CLI installed acceptance is required by the final full CI gate', () => {
  const job = jobs['native-cli-installed'];
  assert.deepEqual(job.needs, ['select-targets', 'preflight', 'client-packages']);
  assert.equal(job['runs-on'], 'ubuntu-24.04');
  assert.match(job.if, /outputs\.profile == 'full'/u);
  assert.doesNotMatch(job.if, /always\(|failure\(|cancelled\(/u);
  assert.equal(job['continue-on-error'], undefined);
  assert(gateJobs.includes('native-cli-installed'));
  assert(jobs.check.needs.includes('native-cli-installed'));
  const full = selectTargets(['packages/native-cli/bin/actql.mjs']);
  assert.equal(gateJobRequired(full, 'native-cli-installed'), true);
  assert.equal(gateJobRequired(selectTargets(['packages/native-cli/bin/actql.mjs'], {draft: true}),
    'native-cli-installed'), false);
  const download = job.steps.find(step => step.uses === './.github/actions/download-client-packages');
  assert.equal(download.with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  const execution = job.steps.find(step => step.run?.startsWith('node scripts/ci-native-cli-installed.mjs'));
  assert(execution); assert.equal(execution.if, undefined);
  assert.equal(execution['continue-on-error'], undefined);
  assert.match(execution.run, /runner\.temp/u);
});

test('private CI cohort retains ordinary release validation without proposing a publication', () => {
  assert.deepEqual(admitNativeReleaseCohort(nativeCliTestCohort), nativeCliTestCohort);
  assert.equal(nativeCliTestCohort.packageVersion, '0.0.2-rc.0');
  assert.throws(() => requireNativeCliCiInputs({}, {clean: true}, 'linux', 'x64'), /normal Client package producer/u);
  assert.throws(() => requireNativeCliCiInputs({ACTQL_PACKED_CLIENT_PACKAGES: '/fixture'}, {clean: false}, 'linux', 'x64'), /clean source/u);
});

test('installed gate uses real producers and independent Host permissions rather than source overlays', () => {
  const source = readFileSync(new URL('./ci-native-cli-installed.mjs', import.meta.url), 'utf8');
  assert.match(source, /await buildNativeCliArtifact\(artifact/u);
  assert.match(source, /await prepareNativeCliRelease\(release/u);
  assert.match(source, /await packedClientPackage\(/u);
  assert.match(source, /release-native-host-authorization\.mjs/u);
  assert.match(source, /state: join\(host, 'host-state'\)/u);
  assert.match(source, /\['release-native-host\.mjs', launcher\]/u);
  assert.match(source, /cwd: launcherHost/u);
  assert(source.indexOf('await registry.close()') < source.indexOf('await save(receipt)'));
  assert.match(source, /new AggregateError\(\[failure, error\]/u);
  assert.match(source, /assert\.equal\(after\.mtimeMs, before\.mtimeMs\)/u);
  assert.match(source, /assert\.rejects\(stat\(target\), \{code: 'ENOENT'\}\)/u);
  assert.doesNotMatch(source, /publishPackageRelease|npm.*\['publish'|git.*\['push'/u);
});
