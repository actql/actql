import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeOpaqueTypeBinders as normalize} from './check-moonbit-api.mjs';

test('opaque generic binder spelling and phantom wildcard are alpha equivalent', () => {
  assert.equal(normalize('type Owner[P]\ntype Pair[A, B]\n'), normalize('type Owner[_]\ntype Pair[X, _]\n'));
});
for (const [name, left, right] of [
  ['arity', 'type Owner[P]', 'type Owner[P, Q]'],
  ['constraint', 'type Owner[P : Eq]', 'type Owner[P]'],
  ['constructor', 'type Owner[P]', 'pub(all) enum Owner[P] { Forged(P) }'],
  ['field', 'pub struct Owner[P] { original : P }', 'pub struct Owner[P] { original : Int }'],
  ['function parameter', 'pub fn[P] use(Owner[P], P) -> Unit', 'pub fn[P] use(Owner[P], Int) -> Unit'],
  ['function availability', 'type Owner[P]\npub fn create() -> Owner[Int]', 'type Owner[P]'],
  ['derivation', 'type Owner[P] derive(Eq)', 'type Owner[P]'],
]) {
  test(`opaque normalization preserves ${name} differences`, () => {
    assert.notEqual(normalize(left), normalize(right));
  });
}

import {checkInterfaces} from './check-moonbit-api.mjs';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';

test('live compiler alpha comparison still rejects real target API differences', {timeout: 120_000}, t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-api-alpha-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const pkg = join(root, 'src', 'owner');
  mkdirSync(pkg, {recursive: true});
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/api-alpha-fixture"\nsource = "src"\n');
  writeFileSync(join(root, '.gitignore'), '_build/\n');
  writeFileSync(join(pkg, 'moon.pkg'), `supported_targets = "+js+wasm+native"
options(targets: { "owner_js.mbt": ["js"], "owner_other.mbt": ["not", "js"] })
`);
  writeFileSync(join(pkg, 'common.mbt'), 'pub fn[I] consume(_owner : Owner[I]) -> Unit {}\n');
  const js = 'struct Owner[I] { value : I }\n';
  const other = 'enum Owner[_] {}\n';
  writeFileSync(join(pkg, 'owner_js.mbt'), js);
  writeFileSync(join(pkg, 'owner_other.mbt'), other);
  const run = (command, args) => execFileSync(command, args, {cwd: root, encoding: 'utf8', timeout: 30_000, stdio: ['ignore', 'pipe', 'pipe']});
  run('moon', ['info', '--target', 'js,wasm,native']);
  run('git', ['init', '-q']);
  run('git', ['add', '.']);
  run('git', ['-c', 'user.name=API fixture', '-c', 'user.email=api-fixture@example.invalid', 'commit', '-qm', 'test: record compiler fixture']);
  assert.doesNotThrow(() => checkInterfaces(root));
  for (const [left, right] of [
    ['pub fn changed(_x : Int) -> Unit {}\n', 'pub fn changed(_x : String) -> Unit {}\n'],
    ['pub(all) struct Payload { field : Int }\n', 'pub(all) struct Payload { field : String }\n'],
    ['pub(all) enum Choice { First }\n', 'pub(all) enum Choice { First; Second }\n'],
  ]) {
    writeFileSync(join(pkg, 'owner_js.mbt'), js + left);
    writeFileSync(join(pkg, 'owner_other.mbt'), other + right);
    // Deliberately stale identical projection files must not suppress the
    // next real compiler report; checkInterfaces must regenerate them first.
    for (const target of ['js', 'wasm', 'native']) {
      writeFileSync(join(root, '_build', target, 'debug', 'check', 'owner', 'owner.mbti'), 'type Owner[_]\n');
    }
    assert.throws(() => checkInterfaces(root), /Common-core interfaces differ across targets/);
  }
});
