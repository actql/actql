import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { auditCoreProbe } from './core-probe.mjs';
import { hash } from '../../inventory.mjs';
import { nativeProfile } from './source.mjs';
const directory = '.artifacts/relation-pipeline/capacity/backing-core';
const sources = Object.fromEntries(['moon.mod', 'moon.pkg', 'backing_wbtest.mbt',
  'backend_js_wbtest.mbt', 'backend_wasm_wbtest.mbt', 'backend_native_wbtest.mbt',
  'abi_native_wbtest.mbt', 'layout_stub.c']
  .map(p => [p, hash(readFileSync(new URL(`./probe/${p}`, import.meta.url)))]));
function evidence() {
  const read = new Map();
  const report = { version: 'actql-array-core-probe/0.1',
    toolchain: JSON.parse(readFileSync(new URL('../../../../toolchain.json', import.meta.url))),
    profile: JSON.parse(readFileSync(new URL('./core-profile.json', import.meta.url))), sources, runs: {} };
  for (const target of ['js', 'wasm', 'native']) {
    const facts = [{ target, case: 'clear', before: target === 'js' ? 17 : 32, after: target === 'js' ? 0 : 32 },
      { target, case: 'growth', prior: target === 'js' ? 9 : 16, current: target === 'js' ? 17 : 32 },
      { target, case: 'map', default: 8, threeKeys: 8, seventhKey: 16, cleared: 16 }];
    if (target === 'native') facts.push({ target, case: 'native-map', headerBytes: 8,
      pointerBytes: 8, mapBytes: 48, tableBytes: 72, entryBytes: 48,
      emptyBytes: 120, threeKeysBytes: 264, replacementBytes: 240 });
    const count = target === 'native' ? 5 : 4;
    const log = facts.map(f => 'ACTQL_BACKING_CORE:' + JSON.stringify(f)).join('\n') + `\nTotal tests: ${count}, passed: ${count}, failed: 0.\n`;
    const logPath = `${directory}/${target}.log`, artifact = `${directory}/binaries/${target}/fixture.${target === 'native' ? 'exe' : target}`;
    read.set(logPath, Buffer.from(log)); read.set(artifact, Buffer.from('unit-test artifact'));
    report.runs[target] = { target, compiler: report.toolchain.moonc, exit: 0,
      command: ['moon', 'test', '--target', target, '--deny-warn'], cwd: '_build/array-backing-probe',
      sources, facts, logPath, logDigest: hash(log), artifacts: { [artifact]: hash(read.get(artifact)) } };
    if (target === 'native') report.runs[target].nativeRuntime = {
      platform: 'linux-x64', archive: report.toolchain.archives['linux-x64'],
      sources: { ...nativeProfile.sources, ...nativeProfile.platformBinaries['linux-x64'] },
      profileDigest: hash(JSON.stringify(nativeProfile)) };
  }
  return { report, read: p => { assert(read.has(p), 'Unbound evidence path'); return read.get(p); } };
}
test('core evidence binds the requested target to its whole execution, not internal labels alone', () => {
  const { report, read } = evidence();
  auditCoreProbe(report, ['js', 'wasm', 'native'], read);
  for (const target of ['js', 'wasm']) {
    const substituted = structuredClone(report);
    substituted.runs[target] = structuredClone(substituted.runs.native);
    assert.throws(() => auditCoreProbe(substituted, ['js', 'wasm', 'native'], read), /Requested core probe target differs/);
  }
});
test('native requested-extent evidence requires the separately pinned runtime sources', () => {
  const { report, read } = evidence();
  for (const change of [r => delete r.nativeRuntime,
    r => r.nativeRuntime.sources['include/moonbit.h'] = hash('unreviewed ABI'),
    r => r.nativeRuntime.archive.sha256 = hash('another compiler'),
    r => r.nativeRuntime.platform = 'linux-arm64']) {
    const invalid = structuredClone(report); change(invalid.runs.native);
    assert.throws(() => auditCoreProbe(invalid, ['js', 'wasm', 'native'], read));
  }
});
test('source substitution and false physical interpretations are refused', () => {
  const { report, read } = evidence();
  const modified = structuredClone(report); modified.sources['backing_wbtest.mbt'] = hash('new fixture');
  assert.throws(() => auditCoreProbe(modified, ['js', 'wasm', 'native'], read), /Probe source changed/);
  const relabeled = structuredClone(report); relabeled.profile.capacityMeaning.js = 'physical backing bytes';
  assert.throws(() => auditCoreProbe(relabeled, ['js', 'wasm', 'native'], read));
});
