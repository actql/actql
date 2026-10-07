// Fresh observations for one registered pristine phase, using the original
// executor, fixed minima and independent oracle. This is not a complete part.
import assert from 'node:assert/strict';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {mutationNamesByPart} from './proof-parts.mjs';
import {snapshot, checkBaseline, hash} from './inventory.mjs';
import {auditFixture, payload, inputVariable} from './fixture.mjs';
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
  const files = {};
  for (const {path, receipt} of report.receipts) for (const input of [path, receipt.sourcePath, receipt.logPath, receipt.inputPath, receipt.fixturePath]) {
    assert(/^\.artifacts\/relation-pipeline\/[A-Za-z0-9_.\/-]+$/u.test(input) && !input.split('/').includes('..'));
    files[input] = readFileSync(join(directory, input), 'utf8');
  }
  return files;
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
    const execution = report.receipts[index], run = execution.receipt;
    assert(!paths.has(execution.path)); paths.add(execution.path);
    assert.equal(hash(JSON.stringify(run)), execution.digest);
    assert.deepEqual(JSON.parse(files[execution.path]), run);
    assert.equal(run.target, 'js'); assert.equal(run.correspondence, true);
    assert.equal(run.boundary.role, 'pristine'); assert.equal(run.sourceDigest, source.digest);
    assert.deepEqual(JSON.parse(files[run.sourcePath]), source);
    assert.equal(run.cases.length, 1); assert.deepEqual(run.cases[0].testCase, testCase);
    assert.equal(run.cases[0].caseDigest, hash(JSON.stringify(testCase)));
    assert.equal(run.inputVariable, inputVariable);
    const inputs = payload(run.cases, true);
    assert.equal(files[run.inputPath], inputs); assert.equal(hash(inputs), run.inputDigest);
    const log = files[run.logPath]; assert.equal(hash(log), run.logDigest);
    auditFixture(run, files[run.fixturePath], log, 'js');
    let id, faults = []; const observations = [];
    for (const line of log.split('\n')) {
      if (line.startsWith('ACTQL_PIPELINE_CASE:')) { id = JSON.parse(line.slice(20)); faults = []; }
      if (line.startsWith('ACTQL_PIPELINE_FAULT:')) faults.push(JSON.parse(line.slice(21)));
      if (line.startsWith('ACTQL_PIPELINE:')) {
        const actual = JSON.parse(line.slice(15)); assert.equal(actual.id, id);
        observations.push({...actual, tableRows: actual.rows,
          rows: actual.wireRows.map(row => actual.columns.map(field => row[field])), faults});
      }
    }
    assert.deepEqual(run.cases.map(entry => entry.observation), observations);
    assert(observations[0]?.checked && observations[0]?.registered);
    assert.deepEqual(report.observations[index], {name, testCase, observed: observations[0]});
    compareSemantics(testCase, observations[0], registry);
    assert(Object.keys(run.artifacts).length > 0);
    for (const path of Object.keys(run.artifacts))
      assert(path.startsWith('_build/js/debug/test/query_integration/') && /^[a-f0-9]{64}$/u.test(run.artifacts[path]));
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
