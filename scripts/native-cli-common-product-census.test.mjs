import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {productMembersCensus, readProductMembers} from '../packages/native-cli/lib/product-members.mjs';

const fixtures = JSON.parse(readFileSync(new URL('../spec/contracts/fixtures/native-product-members.json', import.meta.url)));
const project = wire => productMembersCensus(readProductMembers(wire, fixtures[1].selectors));

test('existing Node census agrees with independent Common root and child expectations', () => {
  for (const fixture of fixtures) {
    assert.deepEqual(productMembersCensus(readProductMembers(fixture.wire, fixture.selectors)), [
      {path: '', entries: [
        {name: 'README.md', kind: 'file'},
        {name: 'bin', kind: 'directory'},
        {name: 'local-product-members.json', kind: 'file'},
        {name: 'package.json', kind: 'file'},
      ]},
      {path: 'bin', entries: [{name: 'actql-native-client', kind: 'file'}]},
    ]);
  }
});

test('immediate directory names have their own ASCII order', () => {
  assert.deepEqual(project(fixtures[1].wire.replace('README.md', 'bin.a'))[0].entries.map(x => x.name),
    ['bin', 'bin.a', 'local-product-members.json', 'package.json']);
});

test('existing Node census refuses file-directory and self-exception collisions', () => {
  assert.throws(() => project(fixtures[1].wire.replace('README.md', 'bin')));
  assert.throws(() => project(fixtures[1].wire.replace('bin/actql-native-client', 'local-product-members.json/member')));
});

test('nested descriptor basename remains an ordinary hashed file', () => {
  const wire = fixtures[1].wire.replace('bin/actql-native-client', 'bin/local-product-members.json');
  const value = readProductMembers(wire, fixtures[1].selectors);
  assert.equal(value.files[1].bytes, 2);
  assert.equal(value.files[1].sha256, 'c'.repeat(64));
  assert.deepEqual(productMembersCensus(value)[1], {
    path: 'bin', entries: [{name: 'local-product-members.json', kind: 'file'}],
  });
});

test('one shared directory is derived without unknown empty or dependency routes', () => {
  const result = project(fixtures[1].wire.replace('package.json', 'bin/z'));
  assert.deepEqual(result.map(x => x.path), ['', 'bin']);
  assert.deepEqual(result[1].entries, [
    {name: 'actql-native-client', kind: 'file'}, {name: 'z', kind: 'file'},
  ]);
});
