import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {installedSourcePaths} from './installed-source.mjs';
import {captureSourceAliasConstruction} from './source-alias-construction.mjs';

test('plural source configuration is copied and exclusive without a legacy registration ceiling', () => {
  const paths = ['/owned/left.json', '/owned/right.json'];
  const admitted = installedSourcePaths({sourceProfilePaths: paths});
  paths[0] = '/changed.json';
  assert.deepEqual(admitted, ['/owned/left.json', '/owned/right.json']);
  assert.equal(Object.isFrozen(admitted), true);
  assert.deepEqual(installedSourcePaths({sourceProfilePath: '/single.json'}, '/fallback.json'),
    ['/single.json']);
  const registered = Array.from({length: 129}, (_, index) => `/owned/source-${index}.json`);
  assert.deepEqual(installedSourcePaths({sourceProfilePaths: registered}), registered);
  for (const sourceProfilePaths of [[], ['/left'], ['/same', '/same'],
    ['relative', '/right'], 'not-an-array']) {
    assert.throws(() => installedSourcePaths({sourceProfilePaths}),
      {message: 'InvalidInstalledSourceProfiles'});
  }
  assert.throws(() => installedSourcePaths({sourceProfilePaths: [...admitted],
    sourceProfilePath: '/single.json'}), {message: 'InvalidInstalledSourceProfiles'});
  assert.throws(() => installedSourcePaths({sourceProfilePaths: [...admitted]}, '/env.json'),
    {message: 'InvalidInstalledSourceProfiles'});
});

// Actual initial Resource and native constructor, without file/provider reads.
// This qualifies path selection only, not an installed 129-Source Host.
test('same initial Source material selects all129 original profile paths before later installation', async t => {
  const f = await boundConstructionActualFixture(t);
  const reader = installedSourceConfigurationReader(f.services);
  const construct = captureSourceAliasConstruction(reader, f.moon);
  const paths = Object.freeze(Array.from({length: 129}, (_, index) => join(f.root, `source-${index}.json`)));
  const selected = installedSourcePaths({sourceProfilePaths: paths}, undefined, construct);
  assert.notStrictEqual(selected, paths);
  assert.deepEqual(selected, paths);
  assert.ok(Object.isFrozen(selected));
  assert.equal(selected.at(-1), paths[128]);
  for (const tail of [paths[0], 'relative-profile.json']) {
    assert.throws(() => installedSourcePaths({sourceProfilePaths: [...paths.slice(0, -1), tail]},
      undefined, construct), {message: 'InvalidInstalledSourceProfiles'});
  }
  assert.throws(() => installedSourcePaths({sourceProfilePath: paths[0], sourceProfilePaths: paths},
    undefined, construct), {message: 'InvalidInstalledSourceProfiles'});
  await f.close();
  assert.equal(f.retire(), true);
});

test('actual initial Source capacity refuses path construction before an unfunded large inventory', async t => {
  const f = await boundConstructionActualFixture(t);
  const construct = captureSourceAliasConstruction(installedSourceConfigurationReader(f.services), f.moon);
  // A sparse original avoids allocating the proposed dense result. Its actual
  // length is quoted first; the existing finite Resource must refuse before
  // plural validation could return InvalidInstalledSourceProfiles.
  const paths = Object.freeze(new Array(1073741824));
  assert.throws(() => installedSourcePaths({sourceProfilePaths: paths}, undefined, construct),
    {code: 'MoonBitHostFailure'});
  assert.equal(paths.length, 1073741824);
  await f.close();
  assert.equal(f.retire(), true);
});

test('same original current loss prevents Source path selection and preserves initial cleanup', async t => {
  const f = await boundConstructionActualFixture(t);
  const construct = captureSourceAliasConstruction(installedSourceConfigurationReader(f.services), f.moon);
  const paths = Object.freeze(Array.from({length: 129}, (_, index) => join(f.root, `source-${index}.json`)));
  const fault = f.failCurrentBeforeNextConstruction();
  assert.throws(() => installedSourcePaths({sourceProfilePaths: paths}, undefined, construct));
  assert.equal(fault.calls, 1);
  await f.close();
  assert.equal(f.retire(), true);
});
