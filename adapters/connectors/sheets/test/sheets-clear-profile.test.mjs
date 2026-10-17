import assert from 'node:assert/strict';
import test from 'node:test';
import {checkInstalledSheetsSourceProfile, checkInstalledSheetsEffectProfile,
  SHEETS_SOURCE_VERSION, SHEETS_EFFECT_VERSION} from '../host/installed-sheets.mjs';

const original = {siteProfilePath: '/fixture/site.json',
  publicationPath: '/fixture/publication.json', connectorId: 'sheets-book',
  accountConfigurationWire: '{}'};

test('the declared Sheets clear Command uses the existing closed installation selection', () => {
  const source = {...original, version: SHEETS_SOURCE_VERSION, rangeCommand: 'clear'};
  const effect = {...original, version: SHEETS_EFFECT_VERSION, rangeCommand: 'clear'};
  assert.deepEqual(checkInstalledSheetsSourceProfile(source), source);
  assert.deepEqual(checkInstalledSheetsEffectProfile(effect), effect);
  for (const check of [checkInstalledSheetsSourceProfile, checkInstalledSheetsEffectProfile]) {
    const valid = check === checkInstalledSheetsSourceProfile ? source : effect;
    for (const rangeCommand of ['CLEAR', 'update', false, null, {}, []]) {
      assert.throws(() => check({...valid, rangeCommand}),
        error => error.code === (valid === source
          ? 'InvalidInstalledSourceProfile' : 'InvalidInstalledEffectProfile'));
    }
    assert.throws(() => check({...valid, sources: []}));
    assert.throws(() => check({...valid, extra: true}));
  }
});
