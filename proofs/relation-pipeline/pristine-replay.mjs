// Fresh observations for one registered pristine phase, using the original
// executor, fixed minima and independent oracle. This is not a complete part.
import assert from 'node:assert/strict';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {logicalMutationNamesByPart as mutationNamesByPart} from './proof-parts.mjs';
import {snapshot, checkBaseline, hash} from './inventory.mjs';
import {readExecutionFiles, validateExecutionOriginal} from './execution-original.mjs';
import {registry} from './registry.mjs';
import {compareSemantics} from './evidence.mjs';
import {mutationWorkspaces} from './workspaces.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
export const pristineAction = Object.freeze({id: 'pipeline-l-m0-fixed-js-pristine',
  part: 'L-M0', mode: 'fixed', target: 'js', phase: 'pristine'});

export function pristineCases() {
  const originals = JSON.parse(readFileSync(join(root, 'proofs/relation-pipeline/regressions.json')));
  return mutationNamesByPart[pristineAction.part].map(name => {
    const selected = originals.filter(entry => entry.name === name);
    assert.equal(selected.length, 1, 'Missing/duplicate independent fixed minimum');
    return {name, testCase: selected[0].testCase};
  });
}

export function readPristineFiles(directory, report) {
  return readExecutionFiles(directory, report.receipts);
}

// Drop only process-local observation IDs. Keep work, stage values, contracts,
// schema, authored order, NULL, duplicate occurrences and every other field.
export function pristineScientificObservation(report) {
  return report.observations.map(({name, testCase, observed}) => {
    const {id, ...scientific} = observed;
    assert(typeof id === 'string' && id.length);
    return {name, testCase, observed: scientific};
  });
}

// Consume raw receipts and logs, rather than trusting a successful summary.
export function validatePristineReport(report, source, files) {
  assert.equal(report.version, 'actql-pipeline-pristine-phase/0.1');
  assert.deepEqual(report.action, pristineAction);
  assert.deepEqual(report.source, source);
  assert.equal(report.sourcePreserved, true); assert.equal(report.reuseAuthorized, false);
  const cases = pristineCases();
  assert.equal(report.units, cases.length);
  assert.equal(report.observations.length, cases.length); assert.equal(report.receipts.length, cases.length);
  const paths = new Set();
  for (const [index, {name, testCase}] of cases.entries()) {
    const execution = report.receipts[index];
    assert(!paths.has(execution.path)); paths.add(execution.path);
    const observed = validateExecutionOriginal({execution, source, files, testCase, target: 'js', role: 'pristine', correspondence: true});
    assert.deepEqual(report.observations[index], {name, testCase, observed});
    compareSemantics(testCase, observed, registry);
  }
  return true;
}

export async function replayPristine() {
  checkBaseline(root);
  const source = snapshot(root), cases = pristineCases();
  const {createExecutor, executions} = await import('./execute.mjs');
  const start = executions.length;
  const workspaces = await mutationWorkspaces(root);
  const owner = createExecutor(workspaces.pristine, {targets: [pristineAction.target]});
  const observations = [];
  try {
    for (const {name, testCase} of cases) {
      const observed = owner.execute([testCase], registry, pristineAction.target, true, `${name}-pristine`)[0];
      compareSemantics(testCase, observed, registry);
      observations.push({name, testCase, observed});
    }
  } finally { owner.close(); }
  // Both copies and the original are checked by the existing source owner.
  // No mutation occurred: do not call this mutated-source restoration evidence.
  workspaces.passed();
  assert.deepEqual(snapshot(root), source, 'Pristine phase changed source');
  const receipts = executions.slice(start);
  assert.equal(receipts.length, cases.length, 'Missing fresh pristine executions');
  assert(receipts.every(entry => entry.receipt.target === 'js' && entry.receipt.correspondence &&
    entry.receipt.boundary.role === 'pristine' && entry.receipt.sourceDigest === source.digest &&
    entry.receipt.exit === 0 && entry.receipt.cases.length === 1));
  return {version: 'actql-pipeline-pristine-phase/0.1', action: pristineAction,
    source, units: cases.length, observations, receipts, sourcePreserved: true,
    scope: 'four assigned fixed minima; pristine JS only; no mutated detection or post-restore claim',
    reuseAuthorized: false};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 2, 'The registered pristine phase takes no selection overrides');
  const report = await replayPristine();
  const directory = join(root, '.artifacts/pipeline-pristine');
  mkdirSync(directory, {recursive: true});
  const path = join(directory, `replay-${randomUUID()}.json`);
  writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`, {flag: 'wx'});
  console.log(`ACTQL_PIPELINE_PRISTINE ${JSON.stringify({path, action: report.action, units: report.units,
    sourceDigest: report.source.digest, sourcePreserved: report.sourcePreserved, reuseAuthorized: false})}`);
}
