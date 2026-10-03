import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { parentOverlay, helper } from '../parent-control/overlay.mjs';
import { auditParentStartup, parentCase } from '../parent-control/audit.mjs';
import { nativeProfile } from './source.mjs';
import { body, boundFixture, executionCommand, inputVariable, payload } from '../../fixture.mjs';
import { hash } from '../../inventory.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
const read = path => readFileSync(join(root, path));
test('one existing two-child registered case fixes the native startup scope', () => {
  assert.equal(parentCase().id, 'pair:filter/distinct');
  assert.deepEqual(parentCase().steps.map(s => s.op), ['filter', 'distinct']);
});
test('the parent observation borrows source roots and rejects a missing constructor site', () => {
  const overlay = parentOverlay(read);
  assert(overlay[helper].includes('#borrow(parent, children, previous, current'));
  const provider = 'src/connectors/local/selected_relation_provider.mbt';
  assert.equal(overlay[provider].split('println(parent_control_probe(').length, 2);
  assert.throws(() => parentOverlay(path => path === provider ? '' : read(path)), /Missing exact chain constructor/);
});

// Prefix-only receipt fixture: stop before independent source/observation
// checks. This tests the actual parent audit entrypoint's compiled boundary,
// not native execution or a complete correspondence certificate.
test('parent audit requires the executed target-bound fixture and build marker', () => {
  const source = {sources: {}, digest: hash('reviewed source')};
  const pin = JSON.parse(read('toolchain.json'));
  const boundary = {version: 'actql-pipeline-execution-boundary/0.1',
    workspace: 'parent-fixture', root: '/parent-fixture', role: 'normal',
    sourceDigest: hash('overlaid source'), toolchainDigest: hash('tools'),
    environmentDigest: hash('environment'), fixtureDigest: hash(body),
    target: 'native', command: executionCommand('native')};
  const buildIdentity = hash(JSON.stringify(boundary));
  const fixture = boundFixture(boundary);
  const log = `ACTQL_PIPELINE_BUILD:${buildIdentity}\nTotal tests: 1, passed: 1, failed: 0\n`;
  const run = {target: 'native', compiler: pin.moonc, exit: 0, correspondence: true,
    sourceDigest: boundary.sourceDigest, boundary, buildIdentity,
    command: executionCommand('native'), fixtureDigest: hash(fixture),
    fixturePath: 'fixture', logPath: 'log', logDigest: hash(log),
    inputVariable, cases: [], inputPath: 'inputs', inputDigest: hash(payload([], true)),
    sourcePath: 'next-independent-source-check'};
  const report = {version: 'actql-native-parent-startup/0.1', target: 'native',
    unconditionalAllocationBytes: false, source, toolchain: pin,
    nativeRuntime: {platform: 'linux-x64',
      sources: {...nativeProfile.sources, ...nativeProfile.platformBinaries['linux-x64']},
      archive: pin.archives['linux-x64'], profileDigest: hash(JSON.stringify(nativeProfile))},
    overlays: Object.fromEntries(Object.entries(parentOverlay(read)).map(([path, code]) => [path, hash(code)])),
    case: parentCase(), execution: {path: 'receipt', receipt: run, digest: hash(JSON.stringify(run))}};
  const next = new Error('reached independent source verification');
  const audit = (bytes = fixture, output = log, receipt = run) => {
    const execution = {...report.execution, receipt, digest: hash(JSON.stringify(receipt))};
    return auditParentStartup({...report, execution}, source, path => {
      if (path === 'receipt') return Buffer.from(JSON.stringify(receipt));
      if (path === 'fixture') return Buffer.from(bytes);
      if (path === 'log') return Buffer.from(output);
      if (path === 'inputs') return Buffer.from(payload([], true));
      if (path === run.sourcePath) throw next;
      return read(path);
    });
  };
  assert.throws(() => audit(), error => error === next);
  assert.throws(() => audit(body), /Archived compiled fixture differs/);
  const stale = log.replace(buildIdentity, hash('other binary'));
  assert.throws(() => audit(fixture, stale, {...run, logDigest: hash(stale)}), /Executed binary boundary differs/);
  assert.throws(() => audit(fixture, log, {...run, boundary: {...boundary, target: 'js'}}), /Compiled target boundary differs/);
});
