import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, readdirSync, copyFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

// Compile the actual production package closure, not a model of its opaque
// handles. No synthetic issuer or foreign scalar stands in for a Node owner.
test('Node handles are opaque and uninhabited without the Node installer', {timeout: 180_000}, t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const temporary = mkdtempSync(join(tmpdir(), 'actql-node-handles-'));
  t.after(() => rmSync(temporary, {recursive: true, force: true}));
  copyFileSync(join(root, 'moon.mod'), join(temporary, 'moon.mod'));
  const visited = new Set();
  function copyPackage(name) {
    if (visited.has(name)) return;
    visited.add(name);
    const from = join(root, 'src', name), to = join(temporary, 'src', name);
    mkdirSync(to, {recursive: true});
    const manifest = readFileSync(join(from, 'moon.pkg'), 'utf8');
    for (const entry of readdirSync(from, {withFileTypes: true})) {
      if (!entry.isFile() || /_(?:wb)?test\.mbt$/.test(entry.name)) continue;
      if (entry.name === 'moon.pkg' || entry.name.endsWith('.mbt')) {
        copyFileSync(join(from, entry.name), join(to, entry.name));
      }
    }
    for (const [, dependency] of manifest.matchAll(/"actql\/actql\/([^"]+)"/g)) copyPackage(dependency);
  }
  copyPackage('physical_resources');
  const probe = join(temporary, 'src', 'external_node_probe');
  mkdirSync(probe);
  writeFileSync(join(probe, 'moon.pkg'), 'supported_targets = "+js+wasm+native"\nimport { "actql/actql/physical_resources" @resources, }\n');
  function check(target, source) {
    writeFileSync(join(probe, 'probe.mbt'), source);
    const actual = spawnSync('moon', ['check', '--target', target, 'src/external_node_probe', '--deny-warn'], {
      cwd: temporary, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024,
    });
    assert.equal(actual.error, undefined, actual.error?.message);
    assert.equal(actual.signal, null, actual.stderr);
    return {status: actual.status, output: actual.stdout + actual.stderr};
  }
  for (const target of ['js', 'wasm', 'native']) {
    const positive = check(target, `pub fn[I] start(value : @resources.NodePreparationAdmission[I]) -> Result[@resources.Ledger, @resources.ImportedChildLedgerIssue] { @resources.start_node_preparation_admission(value) }
pub fn[P] stop(value : @resources.NodeManagedRunAdmission[P]) -> Result[Unit, @resources.ImportedChildLedgerIssue] { @resources.stop_node_managed_run_admission(value) }
`);
    assert.equal(positive.status, 0, positive.output);
    for (const type of ['NodePreparationAdmission', 'NodeManagedRunAdmission']) {
      for (const source of [
        `pub fn forge() -> @resources.${type}[Int] { { admission: None, transitioning: false } }`,
        `pub fn forge(value : @resources.${type}[Int]) -> @resources.${type}[Int] { { ..value } }`,
      ]) {
        const negative = check(target, source);
        assert.notEqual(negative.status, 0, negative.output);
        assert.match(negative.output, /abstract type|not a struct|Cannot create/i);
      }
    }
    for (const reference of ['OriginalNodeManagedRunReference', 'OriginalNodeSourceReference']) {
      const forged = check(target, `pub fn forge() -> @resources.${reference} { 0 }`);
      assert.notEqual(forged.status, 0, forged.output);
      assert.match(forged.output, /Type Mismatch/i);
    }
  }
});
