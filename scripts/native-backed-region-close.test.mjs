import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

// Native Array.clear keeps the unused backing slots. The existing owner may
// release those references only after its actual region-close success.
test('closed Native region releases loan backing only after original close succeeds', () => {
  const native = readFileSync(new URL('../src/platform_native/host_bootstrap/backed_region_native.mbt', import.meta.url), 'utf8');
  const close = native.slice(native.indexOf('pub fn[T, C] NativeHostBootstrap::close_backed_region('));
  assert.match(close, /if region\.closed \{\s*return Ok\(true\)\s*\}/u);
  assert.match(close, /match @resources\.close_backed_execution_region\(region\.accounting, self\) \{\s*Err\(issue\) => Err\(Accounting\(issue\)\)\s*Ok\(closed\) => \{\s*if closed \{/u);
  const code = close.replace(/\/\/[^\n]*/gu, '');
  assert.match(code, /if closed \{\s*region\.closed = true\s*region\.loans\.clear\(\)\s*region\.loans\.shrink_to_fit\(\)\s*\}\s*Ok\(closed\)/u);
  assert.equal((close.match(/loans\.shrink_to_fit\(\)/gu) ?? []).length, 1);
  const tests = readFileSync(new URL('../src/platform_native/host_bootstrap/backed_region_wbtest.mbt', import.meta.url), 'utf8');
  assert.match(tests, /close_backed_region\(\{ identity: 23, \}, region\)\s*is Err\(Bootstrap\(ForeignOriginal\)\)/u);
  assert.match(tests, /assert_false\(host\.close_backed_region\(original, region\)\.unwrap\(\)\)\s*assert_eq\(region\.loans\.length\(\), 1\)\s*assert_eq\(region\.loans\.capacity\(\), loan_capacity\)\s*assert_true\(physical_equal\(region\.loans\[0\], loan\)\)/u);
  assert.equal((tests.match(/assert_eq\(region\.loans\.capacity\(\), 0\)/gu) ?? []).length, 2);
});

test('closed-region source and regression retain their distribution input identities', () => {
  const directory = '../packages/python-local-runtime/native/pre-root/';
  for (const [manifest, paths] of [
    ['host-bootstrap-source.json', ['backed_region_native.mbt', 'backed_region_wbtest.mbt']],
    ['linux-x64-process-source.json', ['backed_region_native.mbt']],
  ]) {
    const document = JSON.parse(readFileSync(new URL(directory + manifest, import.meta.url), 'utf8'));
    for (const file of paths) {
      const path = 'src/platform_native/host_bootstrap/' + file;
      const inputs = document.inputs.filter(input => input.path === path);
      assert.equal(inputs.length, 1, `${manifest}: ${path}`);
      const bytes = readFileSync(new URL('../' + path, import.meta.url));
      assert.equal(inputs[0].bytes, bytes.length, `${manifest}: ${path} bytes`);
      assert.equal(inputs[0].sha256, createHash('sha256').update(bytes).digest('hex'),
        `${manifest}: ${path} SHA256`);
    }
  }
});
