import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const fixture = (path, name) => {
  const source = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const marker = 'let ' + name + ' : String =';
  assert.equal(source.split(marker).length, 2);
  return JSON.parse(source.split(marker)[1].split('#|')[1].split('\n')[0]);
};
const nativePath = 'src/platform_native/remote_resident_source_compute_tests/source_fixture_wbtest.mbt';
const portablePath = 'src/client_local_host/resident_source_query_regression_wbtest.mbt';
const nativeFragment = fixture(nativePath, 'resident_effect_source_fragment');
test('original resident Source fragment selects the exact normative execution contract', () => {
  const aoa = JSON.parse(readFileSync(new URL('../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  assert.deepEqual(nativeFragment, aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
});
test('portable Source regression retains the actual Native fixture originals', () => {
  for (const suffix of ['environment', 'registry', 'values', 'fragment']) {
    assert.deepEqual(fixture(portablePath, 'source_query_original_' + suffix),
      fixture(nativePath, 'resident_effect_source_' + suffix));
  }
});
