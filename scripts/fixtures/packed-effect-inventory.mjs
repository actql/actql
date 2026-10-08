import {connect} from '@actql/sdk';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {publishEffect} from '@actql/local-node';
import {runInstalledEffectInventoryAcceptance} from
  './scripts/fixtures/installed-effect-inventory-acceptance.mjs';

const result = await runInstalledEffectInventoryAcceptance({connect,
  openInstalledRemoteHttpHost, publishEffect});
console.log('PACKED_EFFECT_INVENTORY', JSON.stringify(result));
