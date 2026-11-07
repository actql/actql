import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import recipe from './host-result-service-recipe.cjs';

// This validates support DATA, not a caller-issued allocation or Run permit.
// Registered public numeric scale tests exercise the original fixed callback.
test('Result publication accepts original extents beyond collection support without granting bytes', () => {
  for (const rows of [0,10000,10001,100000,2147483647]) {
    assert.equal(recipe.validOriginalResultPublicationExtent(1,rows,10000000,1),true);
  }
  for (const rows of [-1,1.5,NaN,Infinity,2147483648]) {
    assert.equal(recipe.validOriginalResultPublicationExtent(1,rows,10000000,1),false);
  }
  assert.equal(recipe.validOriginalResultPublicationExtent(0,100000,10000000,1),false);
  assert.equal(recipe.validOriginalResultPublicationExtent(0,100000,10000000,0),true);
  for (const bytes of [0,-1,1.5,2147483648]) {
    assert.equal(recipe.validOriginalResultPublicationExtent(1,100000,bytes,1),false);
  }
  const control={}, journal={sharedControl:control};
  const service=recipe.declareHostResultServiceRecipe(control,journal,{},{});
  assert.equal(service.result.maxCollectedRows,10000);
  assert.equal(Object.hasOwn(service.result,'maxRows'),false);
  assert.equal(service.store.maxObjectBytes,service.store.capacityBytes);
  assert.equal(service.store.capacityBytes,536870912);
  assert.equal(service.store.maxContractNodes,service.store.maxObjectBytes);
  assert.equal(service.numericalBackingClaim,false);
});

test('both Result admission consumers keep original provenance and share extent validation', () => {
  const ordinary=readFileSync(new URL('./ordinary-host-result.mjs',import.meta.url),'utf8');
  const startup=readFileSync(new URL('./node-public-initial-control-bootstrap.cjs',import.meta.url),'utf8');
  assert.match(ordinary,/admitSelectedRun\(prepared, requirements\(originals, prepared\), 'pure'\)/u);
  assert.match(ordinary,/validOriginalResultPublicationExtent\(value\.resultCount, value\.maxRows/u);
  assert.match(ordinary,/prior\.maxRows !== value\.maxRows/u);
  assert.match(startup,/run\.derived !== prepared \|\| run\.entry\.originals !== held \|\| !run\.admitted/u);
  assert.match(startup,/validOriginalResultPublicationExtent\(results, rows/u);
  assert.doesNotMatch(ordinary,/value\.maxRows > 10000/u);
  assert.doesNotMatch(startup,/recipe\.result\.maxRows/u);
});
