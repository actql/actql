import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import {productMembersBody,readProductMembers} from '../packages/native-cli/lib/product-members.mjs';
const fixtures=JSON.parse(readFileSync(new URL('../spec/contracts/fixtures/native-product-members.json',import.meta.url)));
test('independent Common descriptor vectors match the existing formal Node codec',()=>{
  assert.equal(fixtures.length,2);
  for(const fixture of fixtures){
    assert.equal(createHash('sha256').update(fixture.wire).digest('hex'),fixture.sha256);
    const observed=readProductMembers(fixture.wire,fixture.selectors);
    assert.deepEqual(observed.files,fixture.members);
    assert.equal(productMembersBody(observed),fixture.wire);
    assert.deepEqual(observed.files.map(x=>x.path),['README.md','bin/actql-native-client','package.json']);
  }
});
