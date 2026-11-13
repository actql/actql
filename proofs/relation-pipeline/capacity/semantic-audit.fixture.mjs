// Small synthetic receipts for the real capacity validator, not runtime evidence.
// Source overlays, fixture identities and semantic checks are not mocked. Only
// observations/logs are constructed; one real physical artifact is byte-audited.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { hash } from '../inventory.mjs';
import { fixedCorpus } from '../corpus.mjs';
import { corpusBaseline as registry } from '../registry.mjs';
import { registrations } from '../obligations.mjs';
import { candidates, generate, oracle, program } from '../engine.mjs';
import { expectedContracts } from '../evidence.mjs';
import { body, boundFixture, executionCommand, inputVariable, payload } from '../fixture.mjs';
import { generatedObservers, instrument, mutations, replacements, workspaceOverlay } from './instrument.mjs';
import { inputs, subject, unresolved, workspaceBound } from './model.mjs';
import { custodyCleanupStep, custodyInput, custodyOverlay } from './parent-control/custody.mjs';
import { mapBounds } from './backing/maps.mjs';
import { pipelineBounds } from './backing/pipeline.mjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));
export function semanticAuditFixture(artifact, artifactDigest) {
  const files = new Map(), put = (path, bytes) => { files.set(path, Buffer.from(bytes)); return path; };
  const read = path => files.get(path) ?? readFileSync(new URL(path, `file://${root}`));
  const current = { sources: {}, digest: hash('{}') }, toolchain = JSON.parse(read('toolchain.json'));
  const generated = Object.fromEntries(Object.entries(generatedObservers).map(([path, code]) => [path, hash(code)]));
  const report = { version: 'actql-relation-pipeline-structure/0.1', source: current, toolchain,
    claim: { subject, kind: 'structural-model-and-finite-correspondence', unresolved: [...unresolved],
      units: 'filled entries and numeric content octets', unconditionalAllocationBytes: false },
    corpus: fixedCorpus(registry, registrations).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1),
    seed: 148256, search: generate(registry, 148256, 24).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1),
    overlays: { ...Object.fromEntries(Object.keys(replacements).map(path => [path, hash(instrument(path, read(path).toString()))])), ...generated },
    normal: {}, boundaries: { '-1': {}, 0: {}, 1: {} }, mutations: [], executions: [] };
  function observation(c, id, correspondence, offset = 0, fault) {
    const p = program(c, registry), expected = oracle(c, registry), b = inputs(c, registry)[0];
    const wire = stage => stage.rows.map(row => Object.fromEntries(stage.columns.map((name, i) => [name, row[i]])));
    const faults = [];
    if (b) {
      const maps = mapBounds(c, registry), arrays = Object.fromEntries(Object.entries(pipelineBounds(c, registry, 'js')).map(([k, n]) => [k, k.endsWith('Names') ? Number(n) : 0]));
      const base = { kind: 'capacity observation', n: b.rows, w: b.width,
        mapCapacity: maps.capacity, mapEntries: maps.entries,
        mapAliases: { inputBinding: false, inputProjection: false, bindingProjection: false },
        arrayCapacity: arrays, metadataPreparation: { stepped: false, lookup: false, source: false,
          generatedField: -1, generatedSeen: 0, termColumn: false, nameCharge: false,
          snapshotEntries: 0, sourceEntries: 0, portPreparation: false, pendingPortNames: 0, completedPortNames: 0 },
        metadata: 0, index: 0, keep: 0, terms: 0, outputRows: 0, outputCells: 0,
        roots: 0, rowTemporary: 0, measureFrames: 0, unmodeledEntries: 0, live: 0,
        limit: workspaceBound(b.rows, b.width) + offset };
      faults.push({ kind: 'capacity declaration', steps: c.steps.length, retainedBytes: 0, executionBytes: 1 });
      for (let i = 0; i < (correspondence ? 4 : 1); i++) faults.push({ ...base, event: 'start' }, { ...base, event: 'after-cleanup' });
      faults.push({ kind: 'capacity observation', event: 'output-transfer', sharedOutput: true },
        { kind: 'capacity observation', event: 'input-view', sharedBacking: true });
    }
    if (fault) faults.push({ kind: 'capacity observation', event: fault.event, n: b.rows,
      delta: 0, length: b.rows, keep: 1, sharedBacking: false, rows: b.rows,
      consumer: c.steps.findIndex(s => s.op === 'distinct') + 1,
      ...(fault.name === 'oversized-metadata-map' ? { mapCapacity: { inputOrdinals: 16 } } : {}),
      ...(fault.event === 'premature-release' ? { delta: -1 } : {}) });
    return { id, source: p.source, steps: p.steps, checked: true, registered: true,
      kind: offset < 0 ? 'failed' : 'complete', correspondence, faults,
      contracts: expectedContracts(c, registry), columns: expected.columns, schemaColumns: [...expected.columns].sort(),
      rows: expected.rows, wireRows: wire(expected), tableRows: wire(expected).map(row => [...expected.columns].sort().map(k => row[k])),
      stageValues: expected.stages.map(stage => ({ columns: stage.columns, schemaColumns: [...stage.columns].sort(),
        wireRows: wire(stage), tableRows: wire(stage).map(row => [...stage.columns].sort().map(k => row[k])) })) };
  }
  function execution(label, cases, correspondence, offset, fault, healthy = false) {
    const source = { ...generated };
    for (const path of Object.keys(replacements)) {
      let code = read(path).toString();
      if (fault?.path === path) code = code.replace(fault.before, fault.after);
      if (offset !== undefined && path.endsWith('bounded_binding_rows.mbt')) code = workspaceOverlay(code, offset);
      source[path] = hash(instrument(path, code));
    }
    const sourceDigest = hash(JSON.stringify(source));
    const boundary = { version: 'actql-pipeline-execution-boundary/0.1', role: 'normal',
      root: '/synthetic-checkout', workspace: 'synthetic-owner', sourceDigest, target: 'js',
      command: executionCommand('js'), fixtureDigest: hash(body) };
    const run = { target: 'js', exit: 0, compiler: toolchain.moonc, boundary,
      command: executionCommand('js'), sourceDigest, inputVariable, correspondence,
      buildIdentity: hash(JSON.stringify(boundary)), artifacts: { '_build/js/debug/test/query_integration/synthetic.js': artifactDigest },
      cases: cases.map((c, i) => ({ id: `${label}:${i}`, testCase: c, caseDigest: hash(JSON.stringify(c)),
        program: program(c, registry), observation: observation(c, `${label}:${i}`, correspondence, offset, healthy ? undefined : fault) })) };
    const prefix = `.artifacts/relation-pipeline/synthetic/${label}`;
    run.inputPath = put(`${prefix}.input`, payload(run.cases, correspondence)); run.inputDigest = hash(read(run.inputPath));
    run.sourcePath = put(`${prefix}.source`, JSON.stringify({ sources: source, digest: sourceDigest }));
    run.fixturePath = put(`${prefix}.fixture`, boundFixture(boundary)); run.fixtureDigest = hash(read(run.fixturePath));
    const log = [`ACTQL_PIPELINE_BUILD:${run.buildIdentity}`, ...run.cases.flatMap(({ id, observation: o }) => [
      `ACTQL_PIPELINE_CASE:${JSON.stringify(id)}`, ...o.faults.map(f => `ACTQL_PIPELINE_FAULT:${JSON.stringify(f)}`),
      `ACTQL_PIPELINE:${JSON.stringify({ ...o, rows: o.tableRows })}`]), 'Total tests: 1, passed: 1, failed: 0.'].join('\n');
    run.logPath = put(`${prefix}.log`, log); run.logDigest = hash(log);
    const path = put(`${prefix}.receipt`, JSON.stringify(run));
    report.executions.push({ path, receipt: run, digest: hash(JSON.stringify(run)),
      capacityArchives: { '_build/js/debug/test/query_integration/synthetic.js': artifact } });
    return run.cases.map(c => c.observation);
  }
  report.normal.js = execution('capacity-normal-js', report.corpus, true);
  for (const offset of [-1, 0, 1]) report.boundaries[offset].js = execution(`capacity-boundary-${offset}-js`, report.corpus, true, offset);
  const original = report.search.find(c => inputs(c, registry)[0].rows > 0 && c.steps.findIndex(s => s.op === 'distinct') + 1 < c.steps.length);
  assert(original);
  for (const variant of mutations) {
    const index = original.steps.findIndex(s => s.op === 'distinct'), anchor = { event: variant.event, resource: variant.resource,
      fault: variant.fault, step: original.steps[index].id,
      ...(variant.edge ? { receiver: original.steps[index + 1].id } : {}) };
    execution(`capacity-${variant.name}-search-js`, report.search, false, undefined, variant);
    const finalCandidates = candidates(original, registry);
    // Healthy reductions still belong to this mutation's instrumented source.
    const finalObservations = execution(`capacity-${variant.name}-shrink-js`, finalCandidates, false, undefined, variant, true);
    report.mutations.push({ name: variant.name, original, minimal: original, anchor, localMinimal: true,
      finalCandidates, finalObservations, history: [{ attempted: finalCandidates.length, accepted: -1 }],
      replay: { js: execution(`capacity-${variant.name}-minimal-js`, [original], false, undefined, variant)[0] },
      healthy: { js: execution(`capacity-${variant.name}-restored-js`, [original], true)[0] } });
  }
  const model = (name, message) => { const logPath = put(`.artifacts/${name}.log`, message);
    return { command: ['node', `proofs/relation-pipeline/capacity/${name === 'backing' ? 'backing/' : ''}check.mjs`],
      exit: 0, sourceDigest: current.digest, logPath, logDigest: hash(message) }; };
  report.model = model('structural', '8 structural model propositions checked');
  report.backingModel = model('backing', '6 array backing model propositions checked\n4 restricted Map model propositions checked\n3 conditional native Map extent propositions checked\n3 selected native Array extent propositions checked');
  const probe = 'proofs/relation-pipeline/capacity/backing/probe/';
  const probeSources = Object.fromEntries(['moon.mod', 'moon.pkg', 'backing_wbtest.mbt', 'backend_js_wbtest.mbt',
    'backend_wasm_wbtest.mbt', 'backend_native_wbtest.mbt', 'abi_native_wbtest.mbt', 'layout_stub.c'].map(p => [p, hash(read(probe + p))]));
  const facts = [{ target: 'js', case: 'clear', before: 17, after: 0 },
    { target: 'js', case: 'growth', prior: 9, current: 17 },
    { target: 'js', case: 'map', default: 8, threeKeys: 8, seventhKey: 16, cleared: 16 }];
  const coreLog = facts.map(f => `ACTQL_BACKING_CORE:${JSON.stringify(f)}`).join('\n') + '\nTotal tests: 4, passed: 4, failed: 0.';
  const corePath = put('.artifacts/relation-pipeline/capacity/backing-core/js.log', coreLog);
  const small = 'synthetic non-runtime bytes', digest = hash(small);
  const coreArtifact = put('.artifacts/relation-pipeline/capacity/backing-core/binaries/js/synthetic', small);
  report.backingCore = { version: 'actql-array-core-probe/0.1', toolchain, sources: probeSources,
    profile: JSON.parse(read('proofs/relation-pipeline/capacity/backing/core-profile.json')),
    runs: { js: { target: 'js', compiler: toolchain.moonc, exit: 0,
      command: ['moon', 'test', '--target', 'js', '--deny-warn'], cwd: '_build/array-backing-probe', sources: probeSources,
      logPath: corePath, logDigest: hash(coreLog), facts, artifacts: { [coreArtifact]: digest } } } };
  const site = 'src/physical_strategy_host/task_execution.mbt', code = read(site).toString();
  const custodyMutations = [
    ['drop-installed-scratch-release-condition', 'normal', '(execution.hooks.unwrap().scratch_released)()', 'physical_equal(execution, execution)'],
    ['settle-success-before-scratch-release', 'success', 'if task_execution_scratch_released(execution) {', 'if true {'],
  ].map(([name, mode, before, after]) => {
    const sources = { [site]: hash(code.replace(before, after)) }, log = 'Scratch credited before child cleanup';
    return { name, mode, target: 'js', site, beforeDigest: hash(code), source: { sources, digest: hash(JSON.stringify(sources)) },
      exit: 1, logPath: put(`.artifacts/${name}.log`, log), logDigest: hash(log) };
  });
  report.custody = { source: current, mutations: custodyMutations, records: ['normal', 'pending', 'success'].map(mode => {
    const { overlay, fixture, variable } = custodyOverlay(read, mode);
    const overlays = Object.fromEntries(Object.entries({ ...generatedObservers, ...overlay }).map(([p, b]) => [p, hash(b)]));
    const exact = Object.fromEntries(Object.keys(overlays).sort().map(p => [p, overlays[p]]));
    const o = { executionCapacity: 1, before: 1, after: 1, workBefore: 1, workAfter: 1,
      ...(mode === 'success' ? { heldAtCompletion: 1, unusedRetentionAtCompletion: 0 } : {}) };
    const step = custodyCleanupStep(mode), after = `ACTQL_CUSTODY_STAGE:after-${mode === 'success' ? 'completion' : 'settlement'}-before-cleanup`;
    const lines = ['ACTQL_CUSTODY_CHAIN:started', ...(mode === 'success' ? ['ACTQL_CUSTODY_STAGE:before-success-settlement', 'ACTQL_CUSTODY_RETRY:false'] : []),
      after, ...(mode === 'pending' ? ['ACTQL_CUSTODY_RETRY:false'] : []), ...(mode !== 'normal' ? ['ACTQL_CUSTODY_RETRY:error'] : []),
      `ACTQL_CUSTODY_CLEANUP:${step}:before`, `ACTQL_CUSTODY_CLEANUP:${step}:after`, `ACTQL_CUSTODY:${JSON.stringify(o)}`, 'Total tests: 1, passed: 1, failed: 0.'];
    const log = lines.join('\n'), prefix = `.artifacts/synthetic-custody-${mode}`;
    const binary = put(`.artifacts/relation-pipeline/capacity/custody/binaries/${digest}`, small);
    const receipt = { version: 'actql-relation-custody/0.1', target: 'js', mode, toolchain, source: current, overlays,
      executedSource: { sources: exact, digest: hash(JSON.stringify(exact)) }, command: ['moon', 'test', fixture, '--target', 'js', '--deny-warn'], exit: 0,
      inputVariable: variable, inputPath: put(`${prefix}.input`, JSON.stringify(custodyInput())), inputDigest: hash(JSON.stringify(custodyInput().program)),
      fixturePath: put(`${prefix}.fixture`, overlay[fixture]), physicalGcCompletion: false, completeAllocationUpper: false, prematureReleaseCandidate: false,
      logPath: put(`${prefix}.log`, log), logDigest: hash(log), observation: o,
      artifacts: { '_build/js/debug/test/query_integration/query_integration.whitebox_test.js': digest },
      archives: { '_build/js/debug/test/query_integration/query_integration.whitebox_test.js': binary } };
    const path = put(`${prefix}.receipt`, JSON.stringify(receipt)); return { target: 'js', mode, path, digest: hash(read(path)) };
  }) };
  return { report, current, files, read };
}
