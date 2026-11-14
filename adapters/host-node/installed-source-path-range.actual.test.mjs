import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {installedSourcePaths} from './installed-source.mjs';
import {captureSourceAliasConstruction} from './source-alias-construction.mjs';

// Actual initial Resource and native constructor, without file/provider reads.
// This qualifies path selection only, not an installed 129-Source Host.
test('same initial Source material selects all129 original profile paths before later installation', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const reader = installedSourceConfigurationReader(f.services);
  const construct = captureSourceAliasConstruction(reader, f.moon);
  const paths = Object.freeze(Array.from({length: 129}, (_, index) => join(f.root, `source-${index}.json`)));
  const selected = installedSourcePaths({sourceProfilePaths: paths}, undefined, construct);
  assert.notStrictEqual(selected, paths);
  assert.deepEqual(selected, paths);
  assert.ok(Object.isFrozen(selected));
  assert.equal(selected.at(-1), paths[128]);
  assert.ok(events.some(event => event.operation === 'clientProgramReserveInstalledSourceConstruction' && event.accepted));
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
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const construct = captureSourceAliasConstruction(installedSourceConfigurationReader(f.services), f.moon);
  // A sparse original avoids allocating the proposed dense result. Its actual
  // length is quoted first; the existing finite Resource must refuse before
  // plural validation could return InvalidInstalledSourceProfiles.
  const paths = Object.freeze(new Array(1073741824));
  const before = events.length;
  assert.throws(() => installedSourcePaths({sourceProfilePaths: paths}, undefined, construct),
    {code: 'MoonBitHostFailure'});
  assert.ok(events.slice(before).some(event =>
    event.operation === 'clientProgramReserveInstalledSourceConstruction' && !event.accepted));
  assert.equal(paths.length, 1073741824);
  await f.close();
  assert.equal(f.retire(), true);
});

test('same original current loss prevents Source path selection and preserves initial cleanup', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const construct = captureSourceAliasConstruction(installedSourceConfigurationReader(f.services), f.moon);
  const paths = Object.freeze(Array.from({length: 129}, (_, index) => join(f.root, `source-${index}.json`)));
  const fault = f.failCurrentOnNextReserve();
  assert.throws(() => installedSourcePaths({sourceProfilePaths: paths}, undefined, construct));
  assert.equal(fault.calls, 1);
  await f.close();
  assert.equal(f.retire(), true);
});
