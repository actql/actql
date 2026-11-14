// The existing mutation engine, in one explicit local finite scope. This report
// is neither a complete three-target part nor authenticated Actions evidence.
import assert from 'node:assert/strict';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {fixedJsAction} from './fixed-js-scope.mjs';
import {logicalMutationNamesByPart as mutationNamesByPart} from './proof-parts.mjs';
import {logicalMutationPart as mutationPart} from './mutation-parts.mjs';
import {variants} from './mutation-registry.mjs';
import {applyMutation} from './sites.mjs';
import {hash} from './inventory.mjs';
import {registry} from './registry.mjs';
import {compareSemantics} from './evidence.mjs';
import {readExecutionFiles, validateExecutionOriginal, validateRequestedProgram} from './execution-original.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const digest = value => hash(JSON.stringify(value));
export function fixedJsExecutions(report) {
  return report.results.flatMap(result => [...result.executions, ...result.healthyExecutions, ...result.postRestore.executions]);
}
export function readFixedJsFiles(directory, report) { return readExecutionFiles(directory, fixedJsExecutions(report)); }

function exactOwner(value) {
  assert.deepEqual(Object.keys(value ?? {}).sort(), ['id', 'root'], 'Missing exact workspace owner');
  assert(typeof value.id === 'string' && value.id.length && typeof value.root === 'string' && value.root.length);
}

export function validateFixedJsReport({report, source, files, readSource, revision}) {
  assert.equal(report.version, 'actql-pipeline-fixed-js-campaign/0.1');
  assert.deepEqual(report.action, fixedJsAction); assert.equal(report.reuseAuthorized, false);
  assert.deepEqual(report.part, mutationPart(fixedJsAction.part));
  assert.equal(report.revision, revision); assert.match(revision, /^[a-f0-9]{40}$/u);
  assert.deepEqual(report.decision, {revision, localOnly: true});
  assert.equal(report.mode, 'fixed'); assert.equal(report.seed, null); assert.equal(report.explorationTarget, null);
  assert.deepEqual(report.source, source); assert.equal(source.digest, digest(source.sources));
  assert.deepEqual(report.closure, {mutable: true, pristine: true, restoration: true, sourceRestored: true});
  assert.deepEqual(Object.keys(report.workspaces).sort(), ['mutable', 'pristine']);
  const {mutable, pristine} = report.workspaces, restored = report.restorationOwner;
  [mutable, pristine, restored].forEach(exactOwner);
  assert.notEqual(mutable.id, pristine.id); assert.notEqual(mutable.root, pristine.root);
  assert.equal(restored.root, mutable.root, 'Restoration moved to a clean build root');
  assert.notEqual(restored.id, mutable.id, 'Restoration reused mutated owner');
  assert.notEqual(restored.id, pristine.id, 'Restoration borrowed pristine owner');
  assert.deepEqual(report.toolchain, JSON.parse(readSource('toolchain.json')), 'Wrong pinned campaign toolchain');
  const regressions = JSON.parse(readSource('proofs/relation-pipeline/regressions.json'));
  const names = mutationNamesByPart[fixedJsAction.part];
  assert.deepEqual(report.results.map(result => result.name), names, 'Missing or replaced independent mutation');
  const receiptPaths = new Set(), observationIds = new Set();
  for (const result of report.results) {
    const variant = variants.find(entry => entry.name === result.name);
    const minima = regressions.filter(entry => entry.name === result.name); assert.equal(minima.length, 1);
    const fixed = minima[0]; assert(variant.eligible(fixed.testCase));
    assert.equal(result.owner, fixedJsAction.part); assert.equal(result.site, variant.path);
    assert.deepEqual(result.original, fixed.testCase); assert.deepEqual(result.minimal, fixed.testCase);
    assert.deepEqual(result.anchor, fixed.anchor); assert.equal(result.localMinimal, false);
    assert.equal(result.killed, true);
    const original = readSource(variant.path), mutated = applyMutation(original.toString(), variant);
    assert.equal(hash(original), source.sources[variant.path], 'Original mutation bytes differ');
    assert.equal(result.originalDigest, hash(original)); assert.equal(result.mutatedDigest, hash(mutated));
    const changedSources = {...source.sources, [variant.path]: hash(mutated)};
    const changed = {sources: changedSources, digest: digest(changedSources)};
    assert.deepEqual(result.source, changed, 'Unrelated source changed during mutation');
    for (const [phase, executions, observations, owner, role, phaseSource, correspondence] of [
      ['mutated', result.executions, result.replay, mutable, 'mutable', changed, false],
      ['pristine', result.healthyExecutions, result.healthy, pristine, 'pristine', source, true],
      ['post-restore', result.postRestore?.executions, result.postRestore?.observations, restored, 'mutable', source, true],
    ]) {
      assert.equal(executions?.length, 1, `Missing or extra ${phase} execution`);
      assert.deepEqual(Object.keys(observations ?? {}), ['js'], `Wrong ${phase} target`);
      const execution = executions[0], run = execution.receipt;
      assert(!receiptPaths.has(execution.path), 'One receipt substituted for several phases'); receiptPaths.add(execution.path);
      assert.equal(run.boundary.workspace, owner.id); assert.equal(run.boundary.root, owner.root);
      assert.equal(run.compiler, report.toolchain.moonc, 'Campaign compiler differs');
      const observed = validateExecutionOriginal({execution, source: phaseSource, files, testCase: fixed.testCase,
        target: 'js', role, correspondence});
      validateRequestedProgram(run);
      assert.deepEqual(observations.js, observed);
      assert(!observationIds.has(observed.id), 'One observation substituted for several phases'); observationIds.add(observed.id);
      const detected = !!variant.preserves(fixed.testCase, observed, fixed.anchor, registry);
      assert.equal(detected, phase === 'mutated', 'Declared detection differs from actual anchored observation');
      if (correspondence) compareSemantics(fixed.testCase, observed, registry);
    }
    assert.deepEqual(Object.keys(result.postRestore).sort(), ['executions', 'observations']);
  }
  assert.equal(receiptPaths.size, names.length * fixedJsAction.phases.length);
  return true;
}

export function fixedJsScientificObservation(report) {
  return report.results.map(result => ({name: result.name, site: result.site, originalDigest: result.originalDigest,
    mutatedDigest: result.mutatedDigest, anchor: result.anchor, testCase: result.minimal,
    phases: fixedJsAction.phases.map((phase, index) => {
      const observed = [result.replay, result.healthy, result.postRestore.observations][index].js;
      const {id, ...science} = observed; assert(typeof id === 'string' && id.length);
      return {phase, observed: science};
    })}));
}

export async function replayFixedJs(revision) {
  const {runMutations} = await import('./mutations.mjs');
  const reports = await runMutations({profile: 'local-fixed-js', mode: 'fixed', partId: fixedJsAction.part, revision});
  assert.equal(reports.length, 1);
  return reports[0];
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'Use the exact local candidate revision; no selection overrides');
  const revision = process.argv[2]; assert.match(revision, /^[a-f0-9]{40}$/u);
  const report = await replayFixedJs(revision), files = readFixedJsFiles(root, report);
  validateFixedJsReport({report, source: report.source, files, revision, readSource: path => readFileSync(join(root, path))});
  const directory = join(root, '.artifacts/pipeline-fixed-js'); mkdirSync(directory, {recursive: true});
  const path = join(directory, `replay-${randomUUID()}.json`);
  writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`, {flag: 'wx'});
  console.log(`ACTQL_PIPELINE_FIXED_JS ${JSON.stringify({path, action: report.action,
    units: fixedJsExecutions(report).length, sourceDigest: report.source.digest, reuseAuthorized: false})}`);
}
