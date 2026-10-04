// Synthetic orchestration diagnostic only, never runtime execution evidence.
// Real audit, semantic, fixture, receipt, log and archive checks run against one
// tiny invented case. Repository preparation and the corpus/mutation domain are
// controlled here; hosted pipeline verification keeps their complete originals.
import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { createHash } from 'node:crypto';
import { cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [root, scenario] = process.argv.slice(2);
const repository = fileURLToPath(new URL('../../../', import.meta.url));
const auditPath = fileURLToPath(new URL('../audit.mjs', import.meta.url));
const hash = value => createHash('sha256').update(value).digest('hex');
const clone = value => structuredClone(value);
const prefix = '.artifacts/relation-pipeline/';
const stages = ['baseline', 'foundation', 'snapshot', 'decision'];
const calls = { preparation: [], validate: 0, fixture: 0, history: 0 };
const failure = scenario.startsWith('setup-failure-') ? scenario.slice('setup-failure-'.length)
  : scenario === 'cli-preparation-failure' ? 'foundation' : null;
const sources = { 'synthetic-source.mbt': hash('synthetic source, not compiled') };
const current = { sources, digest: hash(JSON.stringify(sources)) };
const impact = { revision: '1'.repeat(40), required: false, paths: ['README.md'],
  reason: 'Synthetic presentation-only change', base: '2'.repeat(40) };
const expectedCurrent = clone(current), expectedImpact = clone(impact);
const prepare = stage => {
  calls.preparation.push(stage);
  if (failure === stage) throw new Error(`Synthetic ${stage} preparation failure`);
};
const mockModule = (relative, namedExports) => mock.module(new URL(relative, import.meta.url).href, { namedExports });
mockModule('../inventory.mjs', {
  hash,
  checkBaseline: () => { prepare('baseline'); },
  snapshot: () => { prepare('snapshot'); return current; },
});
mockModule('../history.mjs', {
  checkFoundation: () => { prepare('foundation'); },
  checkTakeHistory: () => { calls.history++; return { handwrittenCombinationAdditions: 0 }; },
});
mockModule('../exploration-impact.mjs', { decision: () => { prepare('decision'); return impact; } });
const testCase = { id: 'synthetic-case', rows: [{ id: 'row-0', values: { extra: 0, k: null, tag: 1 } }],
  steps: [{ id: 'step-0', op: 'filter', args: { mode: 'true' } }] };
const obligations = { synthetic: ['synthetic-case'] };
mockModule('../corpus.mjs', { fixedCorpus: () => [clone(testCase)], coverage: () => clone(obligations) });
mockModule('../mutation-registry.mjs', { variants: [] });
const { baseRegistry, registry } = await import('../registry.mjs');
const { program, oracle } = await import('../engine.mjs');
const evidence = await import('../evidence.mjs');
const fixture = await import('../fixture.mjs');
let preparedSource;
mockModule('../evidence.mjs', { ...evidence, validate: (report, source, selected) => {
  calls.validate++;
  assert(Object.isFrozen(source), 'Prepared source must be immutable');
  assert(Object.isFrozen(source.sources), 'Nested prepared source must be immutable');
  assert.deepEqual(source, expectedCurrent);
  if (preparedSource) assert.equal(source, preparedSource, 'One factory should retain one prepared source');
  else preparedSource = source;
  return evidence.validate(report, source, selected);
} });
mockModule('../fixture.mjs', { ...fixture, auditFixture: (...args) => {
  calls.fixture++;
  return fixture.auditFixture(...args);
} });
const compiler = JSON.parse(readFileSync(join(repository, 'toolchain.json'), 'utf8')).moonc;
const json = (path, value) => write(path, `${JSON.stringify(value)}\n`);
function write(path, bytes) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes);
}
json(join(root, 'toolchain.json'), { moonc: compiler });

function execution(directory, target, name, id = `${name}:observation`) {
  const requested = program(testCase, registry);
  const expected = oracle(testCase, registry);
  const raw = { id, source: requested.source, steps: requested.steps, kind: 'complete',
    checked: true, registered: true, correspondence: true, stepCount: 1, orderOrigin: 'input:0',
    work: 1, referenceWork: 1, cancelConfirmedChildren: 0, alreadyTerminalChildren: 1,
    contracts: evidence.expectedContracts(testCase, registry), columns: expected.columns,
    schemaColumns: [...expected.columns].sort(), wireRows: expected.output.map(row => row.values),
    rows: expected.rows,
    stageValues: expected.stages.map(stage => ({ columns: stage.columns,
      schemaColumns: [...stage.columns].sort(), wireRows: stage.output.map(row => row.values),
      tableRows: stage.rows })),
  };
  const observation = { ...raw, tableRows: raw.rows, rows: expected.rows, faults: [] };
  const entry = { id, testCase: clone(testCase), caseDigest: hash(JSON.stringify(testCase)), program: requested, observation };
  const command = ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt', '--target', target, '--deny-warn'];
  const boundary = { version: 'actql-pipeline-execution-boundary/0.1', sourceDigest: expectedCurrent.digest,
    target, command, fixtureDigest: hash(fixture.body), role: 'normal', workspace: `synthetic-${name}` };
  const compiledFixture = fixture.boundFixture(boundary);
  const buildIdentity = hash(JSON.stringify(boundary));
  const log = `ACTQL_PIPELINE_BUILD:${buildIdentity}\nACTQL_PIPELINE_CASE:${JSON.stringify(id)}\n` +
    `ACTQL_PIPELINE:${JSON.stringify(raw)}\nTotal tests: 1, passed: 1, failed: 0\n`;
  const inputs = fixture.payload([entry], true);
  const archive = 'synthetic artifact bytes, not executable';
  const artifactPath = `_build/${target}/debug/test/query_integration/${name}.bin`;
  const receipt = { target, exit: 0, compiler, command, boundary, buildIdentity,
    sourcePath: `${prefix}${name}/source.json`, sourceDigest: expectedCurrent.digest,
    correspondence: true, cases: [entry], inputVariable: fixture.inputVariable,
    inputPath: `${prefix}${name}/input.json`, inputDigest: hash(inputs),
    logPath: `${prefix}${name}/execution.log`, logDigest: hash(log),
    fixturePath: `${prefix}${name}/fixture.mbt`, fixtureDigest: hash(compiledFixture),
    artifacts: { [artifactPath]: hash(archive) }, archives: { [artifactPath]: `${prefix}${name}/archive.bin` } };
  json(join(directory, name, 'source.json'), expectedCurrent);
  write(join(directory, name, 'input.json'), inputs);
  write(join(directory, name, 'execution.log'), log);
  write(join(directory, name, 'fixture.mbt'), compiledFixture);
  write(join(directory, name, 'archive.bin'), archive);
  json(join(directory, name, 'receipt.json'), receipt);
  return { path: `${prefix}${name}/receipt.json`, digest: hash(JSON.stringify(receipt)), receipt };
}
function makeDirectory(name, duplicateObservation = false) {
  const directory = join(root, name);
  mkdirSync(directory, { recursive: true });
  for (const [slot, target, selected] of [['base-js', 'js', baseRegistry],
    ...['js', 'wasm', 'native'].map(target => [target, target, registry])]) {
    const run = execution(directory, target, slot,
      duplicateObservation && slot === 'js' ? 'base-js:observation' : undefined);
    const models = Object.fromEntries([['session', 14, 'proofs/bounded-session/check.mjs'],
      ['chain', 36, 'proofs/relation-chain/check.mjs']].map(([id, count, file]) => {
      const log = `Checked ${count} theorems, expected claim types and axiom dependencies\n`;
      write(join(directory, `${id}.log`), log);
      return [id, { logPath: `${prefix}${id}.log`, logDigest: hash(log), passed: true,
        exit: 0, sourceDigest: expectedCurrent.digest, command: ['node', file] }];
    }));
    json(join(directory, `${slot}.json`), { version: 'actql-relation-pipeline-evidence/0.1',
      profile: evidence.profile, source: expectedCurrent, inherited: evidence.inherited,
      premises: evidence.premises, evidenceKinds: ['formal-model', 'tested-refinement', 'independent-semantic-check'],
      residual: ['No arbitrary registry/length implementation refinement; capacity remains conditional'],
      registry: selected.map(descriptor => descriptor.name), target, revision: expectedImpact.revision,
      models, executions: [run], obligations, caseCount: 1, requested: [run.receipt.cases[0].caseDigest],
      toolchain: { moonc: compiler } });
  }
  json(join(directory, 'exploration-decision.json'), expectedImpact);
  json(join(directory, 'fixed-mutations.json'), { mode: 'fixed', decision: expectedImpact,
    revision: expectedImpact.revision, source: expectedCurrent,
    workspaces: { pristine: { id: 'pristine', root: '/synthetic/pristine' },
      mutable: { id: 'mutable', root: '/synthetic/mutable' } }, explorationTarget: null, seed: null, results: [] });
  return directory;
}
const healthy = makeDirectory('healthy');
const read = path => JSON.parse(readFileSync(path, 'utf8'));
function altered(name, change) {
  const directory = join(root, name);
  cpSync(healthy, directory, { recursive: true });
  change(directory);
  return directory;
}
const targetCases = ['js', 'wasm', 'base-js'].map(slot => ({
  name: `native-in-${slot}-slot`,
  directory: altered(`native-in-${slot}`, directory => cpSync(join(directory, 'native.json'), join(directory, `${slot}.json`))),
  expected: slot === 'base-js' ? 'Baseline report target differs from requested audit target js'
    : `Report target differs from requested audit target ${slot}`,
}));
const duplicateReceipt = altered('duplicate-receipt', directory => {
  const report = read(join(directory, 'js.json'));
  report.executions = read(join(directory, 'base-js.json')).executions;
  json(join(directory, 'js.json'), report);
});
const duplicateObservation = makeDirectory('duplicate-observation', true);
const negativeCases = [...targetCases,
  { name: 'duplicate-receipt', directory: duplicateReceipt, expected: 'Execution receipt reused across obligations' },
  { name: 'duplicate-observation', directory: duplicateObservation, expected: 'Observation identity reused across executions' }];
const assertPreparation = (expected = stages) => assert.deepEqual(calls.preparation, expected);
const checkError = (action, expected) => assert.throws(action, error => error.message.includes(expected));

if (scenario.startsWith('cli-')) {
  if (scenario === 'cli-healthy') process.argv = [process.execPath, auditPath, healthy];
  else {
    let entries = targetCases;
    if (scenario === 'cli-admitted-negative') entries = [{ name: 'unexpectedly-healthy', directory: healthy, expected: targetCases[0].expected }];
    if (scenario === 'cli-wrong-rejection') entries = [{ ...negativeCases.at(-1), expected: targetCases[0].expected }];
    const plan = join(root, 'plan.json');
    json(plan, entries);
    process.argv = [process.execPath, auditPath, '--target-regressions', plan];
  }
  await import('../audit.mjs');
  assertPreparation();
  if (scenario === 'cli-healthy') assert.equal(calls.history, 1);
  else assert.equal(calls.history, 0);
} else {
  const { createAudit, auditTargetRegressions } = await import('../audit.mjs');
  assert.deepEqual(calls, { preparation: [], validate: 0, fixture: 0, history: 0 }, 'Import must have no audit side effects');
  if (scenario === 'import-only') {
    assert.equal(typeof createAudit, 'function');
    assert.equal(typeof auditTargetRegressions, 'function');
  } else if (failure) {
    checkError(() => createAudit(root), `Synthetic ${failure} preparation failure`);
    assertPreparation(stages.slice(0, stages.indexOf(failure) + 1));
    assert.equal(calls.validate, 0);
    assert.equal(calls.fixture, 0);
    assert.equal(calls.history, 0);
  } else if (scenario === 'batch-targets') {
    const entries = [...targetCases, ...targetCases.toReversed()];
    const { results, preparation } = auditTargetRegressions(entries);
    assert(Object.isFrozen(preparation));
    assert.deepEqual(Object.keys(preparation), ['baselineMs', 'foundationMs', 'snapshotMs', 'decisionMs']);
    assert(Object.values(preparation).every(value => Number.isFinite(value) && value >= 0));
    assert.equal(results.length, entries.length);
    results.forEach((result, index) => {
      assert.equal(result.name, entries[index].name);
      assert.equal(result.rejected, true);
      assert(!Object.hasOwn(result, 'exit'), 'An in-process rejection is not a child-process exit');
      assert(Number.isFinite(result.auditMs) && result.auditMs >= 0);
      assert(result.log.includes(entries[index].expected), result.log);
    });
    assertPreparation();
  } else {
    const audit = createAudit(root);
    assertPreparation();
    const log = [];
    const run = directory => audit(directory, line => log.push(line));
    if (scenario === 'repeated-and-reversed') {
      for (const entries of [negativeCases, negativeCases.toReversed()]) {
        run(healthy);
        for (const entry of entries) {
          checkError(() => run(entry.directory), entry.expected);
          run(healthy);
        }
      }
      assert.equal(calls.history, 12);
      assert(log.some(line => line.startsWith('native: exact normal corpus')));
    } else if (scenario === 'detached-preparation') {
      assert(!Object.isFrozen(current) && !Object.isFrozen(current.sources), 'Factory must not freeze caller-owned snapshot');
      assert(!Object.isFrozen(impact) && !Object.isFrozen(impact.paths), 'Factory must not freeze caller-owned decision');
      current.sources['synthetic-source.mbt'] = hash('external mutation');
      current.digest = hash('external mutation');
      impact.revision = '3'.repeat(40);
      impact.required = true;
      impact.paths.push('external mutation');
      run(healthy);
      run(healthy);
      assert.equal(calls.validate, 8);
      assert.equal(calls.fixture, 8);
    } else if (scenario === 'revalidate-artifacts') {
      run(healthy);
      const archive = join(healthy, 'js/archive.bin');
      const original = readFileSync(archive);
      writeFileSync(archive, 'changed after successful audit');
      checkError(() => run(healthy), 'Final normal artifact changed');
      writeFileSync(archive, original);
      run(healthy);
      assert.equal(calls.history, 2);
      assert.equal(calls.validate, 10);
      assert.equal(calls.fixture, 10);
    } else throw new Error(`Unknown synthetic scenario ${scenario}`);
    assertPreparation();
  }
}
console.log(`SYNTHETIC_AUDIT_BATCH:${JSON.stringify({ scenario, calls })}`);
