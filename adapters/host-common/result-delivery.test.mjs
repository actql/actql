import test from 'node:test';
import * as source from './result-access.mjs';
import * as packaged from '../../packages/run-host-core/result-access.mjs';
import {openResultDeliveryControl} from '../../packages/run-host-core/index.mjs';
import {deliveryAcceptanceCases} from '../../scripts/fixtures/result-delivery-acceptance.mjs';

for (const [entry, api] of [['source', source], ['packaged', packaged]]) {
  for (const [name, run] of Object.entries(deliveryAcceptanceCases)) {
    test(`${entry}: ${name}`, () => run(api, openResultDeliveryControl()));
  }
}
