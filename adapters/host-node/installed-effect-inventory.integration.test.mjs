import test from 'node:test';
import {connect} from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost, publishInstalledEffect} from './embedded-local.mjs';
import {runInstalledEffectInventoryAcceptance} from
  '../../scripts/fixtures/installed-effect-inventory-acceptance.mjs';

test('public installed Effect inventory selects one owner before Compute and survives restart', async () => {
  await runInstalledEffectInventoryAcceptance({connect, openInstalledRemoteHttpHost,
    publishEffect: publishInstalledEffect});
});
