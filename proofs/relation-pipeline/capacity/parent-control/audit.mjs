import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hash } from '../../inventory.mjs';
import { fixedCorpus } from '../../corpus.mjs';
import { registry } from '../../registry.mjs';
import { registrations } from '../../obligations.mjs';
import { program } from '../../engine.mjs';
import { auditFixture, payload, inputVariable } from '../../fixture.mjs';
import { compareSemantics } from '../../evidence.mjs';
import { nativeProfile } from '../backing/source.mjs';
import { inspectParentStartup } from '../backing/parent-layout.mjs';
import { parentOverlay } from './overlay.mjs';
import { checkParentCensus, inspectParentCorePhases } from './bounds.mjs';
import { inspectProviderConstruction } from './provider-construction.mjs';
export const directory = '.artifacts/relation-pipeline/capacity/parent-control-probe';
const pin = JSON.parse(readFileSync(new URL('../../../../toolchain.json', import.meta.url)));
export function parentCase() {
  const testCase = fixedCorpus(registry, registrations).find(c => c.id === 'pair:filter/distinct');
  assert(testCase && testCase.steps.length === 2 && testCase.steps[1].op === 'distinct');
  return testCase;
}
export function auditParentStartup(report, current, read) {
  assert.equal(report.version, 'actql-native-parent-startup/0.1');
  assert.equal(report.target, 'native', 'Requested parent probe target differs from execution');
  assert.equal(report.unconditionalAllocationBytes, false, 'Startup lower evidence cannot issue an unconditional capacity guarantee');
  assert.deepEqual(report.source, current, 'Stale parent source');
  checkParentCensus(read);
  const { receiptPath, ...model } = report.model;
  assert.deepEqual(JSON.parse(read(receiptPath)), model, 'Parent model differs from independent execution receipt');
  assert.equal(receiptPath, `${directory}/models/${hash(JSON.stringify(model))}.json`);
  assert.deepEqual(model.command, ['node', 'proofs/relation-pipeline/capacity/parent-control/check.mjs']);
  assert.equal(model.exit, 0); assert.equal(model.sourceDigest, current.digest);
  assert.equal(model.logPath, `${directory}/models/${model.logDigest}.log`);
  assert.equal(hash(read(model.logPath)), model.logDigest);
  assert(read(model.logPath).toString().includes('3 conditional retained parent-core propositions checked'));
  assert(read(model.logPath).toString().includes('2 conditional provider-construction propositions checked'));
  assert.deepEqual(report.toolchain, pin);
  const runtime = report.nativeRuntime;
  assert(nativeProfile.supported.includes(runtime.platform));
  assert.deepEqual(runtime.sources, { ...nativeProfile.sources, ...nativeProfile.platformBinaries[runtime.platform] });
  assert.deepEqual(runtime.archive, pin.archives[runtime.platform]);
  assert.equal(runtime.profileDigest, hash(JSON.stringify(nativeProfile)));
  const overlay = Object.fromEntries(Object.entries(parentOverlay(read)).map(([path, code]) => [path, hash(code)]));
  assert.deepEqual(report.overlays, overlay, 'Unknown parent observation source');
  assert.deepEqual(report.case, parentCase(), 'The fixture scope is independent of requested claims');
  const execution = report.execution, run = execution.receipt;
  assert.deepEqual(JSON.parse(read(execution.path)), run, 'Parent report differs from independent receipt');
  assert.equal(execution.digest, hash(JSON.stringify(run)));
  assert.equal(run.target, 'native', 'Native layout evidence belongs to another target');
  assert.equal(run.compiler, pin.moonc); assert.equal(run.exit, 0); assert.equal(run.correspondence, true);
  assert.deepEqual(run.command, ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt', '--target', 'native', '--deny-warn']);
  const log = read(run.logPath).toString(); assert.equal(hash(log), run.logDigest);
  auditFixture(run, read(run.fixturePath), log, 'native');
  assert.equal(run.inputVariable, inputVariable);
  assert.equal(run.inputDigest, hash(payload(run.cases, true)));
  assert.equal(read(run.inputPath).toString(), payload(run.cases, true));
  const source = JSON.parse(read(run.sourcePath));
  assert.equal(source.digest, run.sourceDigest);
  assert.equal(source.digest, hash(JSON.stringify(source.sources)));
  assert.deepEqual(source.sources, { ...current.sources, ...overlay }, 'Receipt did not execute the reviewed parent overlay');
  assert.equal(run.cases.length, 1);
  const entry = run.cases[0];
  assert.deepEqual(entry.testCase, report.case); assert.equal(entry.caseDigest, hash(JSON.stringify(report.case)));
  assert.deepEqual(entry.program, program(report.case, registry));
  assert.deepEqual(report.observation, entry.observation);
  assert.equal(entry.observation.id, entry.id);
  assert(entry.observation.checked && entry.observation.registered && entry.observation.correspondence);
  assert.equal(entry.observation.source, entry.program.source);
  assert.equal(entry.observation.steps, entry.program.steps);
  compareSemantics(report.case, entry.observation, registry);
  const observations = []; let id; let faults;
  for (const line of log.split('\n')) {
    if (line.startsWith('ACTQL_PIPELINE_CASE:')) { id = JSON.parse(line.slice(20)); faults = []; }
    if (line.startsWith('ACTQL_PIPELINE_FAULT:')) faults.push(JSON.parse(line.slice(21)));
    if (line.startsWith('ACTQL_PIPELINE:')) {
      const o = JSON.parse(line.slice(15)); assert.equal(o.id, id);
      observations.push({ ...o, tableRows: o.rows, rows: o.wireRows.map(row => o.columns.map(field => row[field])), faults });
    }
  }
  assert.deepEqual(observations, [entry.observation], 'Parent receipt differs from actual archived log');
  assert(Object.keys(run.artifacts).length > 0);
  assert.deepEqual(Object.keys(execution.parentArchives).sort(), Object.keys(run.artifacts).sort());
  for (const [path, digest] of Object.entries(run.artifacts)) {
    assert(path.startsWith('_build/native/debug/test/query_integration/'));
    const archive = execution.parentArchives[path];
    assert.equal(archive, `${directory}/binaries/${digest}`);
    assert.equal(hash(read(archive)), digest, 'Parent probe executed artifact changed');
  }
  const executed = '_build/native/debug/test/query_integration/query_integration.whitebox_test.exe';
  assert(Object.hasOwn(run.artifacts, executed), 'Missing actual native test executable');
  const binary = read(execution.parentArchives[executed]);
  if (runtime.platform === 'darwin-arm64') {
    assert.equal(binary.readUInt32LE(0), 0xfeedfacf, 'Runtime profile differs from executed binary platform');
    assert.equal(binary.readUInt32LE(4), 0x0100000c);
  } else {
    assert.equal(binary.subarray(0, 4).toString('hex'), '7f454c46', 'Runtime profile differs from executed binary platform');
    assert.equal(binary[4], 2); assert.equal(binary[5], 1); assert.equal(binary.readUInt16LE(18), 62);
  }
  const facts = entry.observation.faults.filter(f => f.kind === 'parent control investigation');
  assert.equal(facts.length, 1);
  const core = inspectParentCorePhases(report.case, facts[0],
    entry.observation.faults.filter(f => f.kind === 'parent core observation'), run.target,
    entry.observation.faults.filter(f => f.kind === 'parent completed identity'));
  assert.deepEqual(report.retainedCore, core, 'Retained-core recipe differs from independent input/source/observations');
  const construction = inspectProviderConstruction(
    entry.observation.faults.filter(f => f.kind === 'provider construction observation'), read, run.target);
  assert.deepEqual(report.providerConstruction, construction, 'Provider recipe differs from independent source and actual construction');
  return { kind: 'finite native startup, retained-core and provider-construction correspondence',
    ...inspectParentStartup(facts[0], run.target), retainedCore: core, providerConstruction: construction };
}
