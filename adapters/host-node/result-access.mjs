// Node installation for the portable Result access service. Node owns the
// incremental physical delivery digest; grant and delivery meaning remain in
// the MoonBit publication control used by the common service.
import {createHash} from 'node:crypto';
import {
  deliverAuthorizedResult,
  describeAuthorizedResult,
  inspectAuthorizedDeliveryAttempt,
  installResultAccessAuthority,
  installResultAccessService,
} from '../host-common/result-access.mjs';

const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

export {deliverAuthorizedResult, describeAuthorizedResult, inspectAuthorizedDeliveryAttempt,
  installResultAccessAuthority};

export function installNodeResultAccessService(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits', 'frameLimits',
  ])) {
    throw new TypeError('InvalidNodeResultAccessService');
  }
  return installResultAccessService({
    ...configuration,
    createDigest() {
      const hash = createHash('sha256');
      return Object.freeze({
        update: bytes => hash.update(bytes),
        finish: () => hash.digest('hex'),
      });
    },
  });
}
