import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
test('scalar Owner selects one pinned portable numeric source on every target', () => {
  const root = new URL('../', import.meta.url);
  const read = path => readFileSync(new URL(path, root));
  const manifest = JSON.parse(read('src/scalar_numeric_kernel/upstream.json'));
  assert.equal(manifest.toolchain, '0.10.12+1634b282e');
  assert.equal(manifest.files.length, 9);
  const laws = JSON.parse(read('spec/contracts/actql-expressions.json')).laws;
  for (const name of ['pow', 'exp', 'ln', 'log', 'log10', 'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2', 'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh', 'cbrt']) {
    assert.ok(laws[name].algorithm.includes('sha256:' + sha(read('src/scalar_numeric_kernel/upstream.json'))));
  }
  for (const file of manifest.files) {
    const source = read(`src/scalar_numeric_kernel/${file.path}`);
    assert.equal(sha(source), file.sha256);
    assert.match(source.toString(), /Licensed under the Apache License/);
  }
  assert.doesNotMatch(read('src/scalar_numeric_kernel/moon.pkg').toString(), /targets:|options\(/);
  assert.match(read('src/execution_relation/moon.pkg').toString(), /"actql\/actql\/scalar_numeric_kernel" @math/);
  assert.doesNotMatch(read('src/execution_relation/moon.pkg').toString(), /"moonbitlang\/core\/math"/);
});
