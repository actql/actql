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


test('range and clear capture quote receive the same cold recovery codec bounds', async () => {
  const {sheetsRangeDriverConstruction} = await import('../host/sheets-range-command.mjs');
  const {SHEETS_LIMITS} = await import('../site/sheets-exchange.mjs');
  for (const profileName of ['sheetsRangeConstructionProfile', 'sheetsClearConstructionProfile']) {
    const captureName = profileName === 'sheetsRangeConstructionProfile'
      ? 'sheetsRangeCaptureConstructionProfile' : 'sheetsClearCaptureConstructionProfile';
    const binding = Object.freeze({original: profileName});
    const opaque = Object.freeze({same: captureName});
    const moon = {[profileName]() { throw new Error('request profile not selected'); },
      [captureName](...args) {
        assert.equal(this, moon);
        assert.deepEqual(args, [binding, 1000000, 100000, 64, 100000, 10000, 16,
          SHEETS_LIMITS.maxResponseBytes, SHEETS_LIMITS.maxNodes, SHEETS_LIMITS.maxDepth]);
        return opaque;
      }};
    const selected = sheetsRangeDriverConstruction({moon, binding,
      site: {apiOrigin: 'https://sheets.example.test', spreadsheetId: 'book'},
      command: {commandCid: 'same-command'}, bindingCid: 'same-binding',
      targetWire: 'same-target', operation: 'same-operation', profileName});
    assert.equal(selected.managedPlanProvider.installedStandardDriverCaptureConstructionCapacity(
      1000000, 100000, 64, 100000, 10000, 16), opaque);
  }
});
