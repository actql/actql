import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { hash } from '../../inventory.mjs';
import { artifacts } from '../../../bounded-session/evidence.mjs';
import { checkCore } from './source.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
const sources = ['moon.mod', 'moon.pkg', 'backing_wbtest.mbt',
  'backend_js_wbtest.mbt', 'backend_wasm_wbtest.mbt', 'backend_native_wbtest.mbt'];
const template = 'proofs/relation-pipeline/capacity/backing/probe';
const installed = '_build/array-backing-probe';
const directory = '.artifacts/relation-pipeline/capacity/backing-core';
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const sourceHashes = () => {
  assert.deepEqual(readdirSync(join(root, template)).sort(), [...sources].sort(), 'Probe templates contain generated or unreviewed files');
  return Object.fromEntries(sources.map(p => [p, hash(readFileSync(join(root, template, p)))]));
};
const prefix = 'ACTQL_BACKING_CORE:';
function facts(log) {
  return log.split('\n').filter(line => line.startsWith(prefix)).map(line => JSON.parse(line.slice(prefix.length)));
}
function checkFacts(target, observed) {
  assert.deepEqual(observed.map(o => o.case), ['clear', 'growth']);
  assert(observed.every(o => o.target === target), 'Core fixture target differs from requested target');
  const [clear, growth] = observed;
  assert.deepEqual(clear, { target, case: 'clear', before: target === 'js' ? 17 : 32,
    after: target === 'js' ? 0 : 32 });
  assert.deepEqual(growth, { target, case: 'growth', prior: target === 'js' ? 9 : 16,
    current: target === 'js' ? 17 : 32 });
}
export function auditCoreProbe(report, targets, read = path => readFileSync(join(root, path))) {
  assert.equal(report.version, 'actql-array-core-probe/0.1');
  assert.deepEqual(report.toolchain, pin);
  assert.deepEqual(report.sources, sourceHashes(), 'Probe source changed');
  assert.deepEqual(report.profile, JSON.parse(readFileSync(new URL('./core-profile.json', import.meta.url))));
  assert.deepEqual(Object.keys(report.runs).sort(), [...targets].sort());
  for (const target of targets) {
    const run = report.runs[target];
    assert.equal(run.target, target, 'Requested core probe target differs from execution');
    assert.equal(run.compiler, pin.moonc); assert.equal(run.exit, 0);
    assert.deepEqual(run.command, ['moon', 'test', '--target', target, '--deny-warn']);
    assert.equal(run.cwd, installed);
    assert.deepEqual(run.sources, report.sources);
    assert.equal(run.logPath, `${directory}/${target}.log`);
    const log = read(run.logPath).toString(); assert.equal(hash(log), run.logDigest);
    assert(/Total tests: 3, passed: 3, failed: 0\./.test(log), 'Incomplete core fixture');
    assert.deepEqual(run.facts, facts(log)); checkFacts(target, run.facts);
    assert(Object.keys(run.artifacts).length > 0);
    for (const [path, digest] of Object.entries(run.artifacts)) {
      assert(path.startsWith(`${directory}/binaries/${target}/`), 'Core binary belongs to another target');
      assert(!path.split('/').includes('..'), 'Non-local core artifact');
      assert.equal(hash(read(path)), digest, 'Core probe artifact changed');
    }
  }
  return { targets, modelRefinement: 'finite core correspondence', allocationBytes: false };
}
export function runCoreProbe(targets) {
  assert(targets.length > 0 && targets.every(t => ['js', 'wasm', 'native'].includes(t)));
  const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
  const env = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
  const compiler = spawnSync(join(home, 'bin/moonc'), ['-v'], { env, encoding: 'utf8' });
  assert.equal(compiler.status, 0); assert.equal(compiler.stdout.trim(), pin.moonc);
  const profile = checkCore(join(home, 'lib/core'), pin);
  mkdirSync(join(root, installed), { recursive: true });
  mkdirSync(join(root, directory), { recursive: true });
  for (const path of sources) copyFileSync(join(root, template, path), join(root, installed, path));
  const report = { version: 'actql-array-core-probe/0.1', toolchain: pin, profile,
    sources: sourceHashes(), runs: {} };
  for (const target of targets) {
    const command = ['test', '--target', target, '--deny-warn'];
    const result = spawnSync(join(home, 'bin/moon'), command, {
      cwd: join(root, installed), env, encoding: 'utf8', maxBuffer: 1024 * 1024,
    });
    const log = (result.stdout ?? '') + (result.stderr ?? '');
    const logPath = `${directory}/${target}.log`; writeFileSync(join(root, logPath), log);
    assert.equal(result.status, 0, log);
    for (const path of sources) assert.equal(hash(readFileSync(join(root, installed, path))), report.sources[path]);
    const binaries = artifacts(join(root, installed), target, '');
    const archives = {};
    for (const [path, digest] of Object.entries(binaries)) {
      const suffix = path.slice(`_build/${target}/debug/test/`.length);
      const archive = `${directory}/binaries/${target}/${suffix}`;
      // Preserve the relative compiler path beneath this target's archive.
      mkdirSync(dirname(join(root, archive)), { recursive: true });
      copyFileSync(join(root, installed, path), join(root, archive));
      archives[archive] = digest;
    }
    report.runs[target] = { target, compiler: compiler.stdout.trim(), exit: result.status,
      command: ['moon', ...command], cwd: installed, sources: report.sources,
      facts: facts(log), logPath, logDigest: hash(log), artifacts: archives };
    console.log(`${target}: 3 pinned-core backing and explicit-holder checks`);
  }
  auditCoreProbe(report, targets);
  writeFileSync(join(root, directory, targets.length === 3 ? 'all.json' : `${targets[0]}.json`), JSON.stringify(report, null, 2) + '\n');
  return report;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const targets = process.argv[2] === 'js' ? ['js'] : ['js', 'wasm', 'native'];
  runCoreProbe(targets);
}
