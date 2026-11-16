import {openEffectLedger} from './effect-ledger.mjs';

// Same installed request and control frame. Receiver bounds constrain physical
// reads; they do not rewrite the installation's durable response policy.
export function openInstalledEffectLedger(moon, root, identity, maxEntryBytes,
  maxReadResponseBytes, controlConstruction, open = openEffectLedger) {
  const options = {moon, root,
    authorityScopeCid: moon.clientRequestAuthorityScopeCid(identity),
    callerRequestId: moon.clientRequestCallerId(identity),
    maxEntryBytes, maxReadResponseBytes,
    ...(controlConstruction === undefined ? {} : {controlConstruction})};
  return controlConstruction === undefined ? open(options)
    : controlConstruction.ledgerOpen === undefined
      ? controlConstruction(undefined, open, [options])
      : controlConstruction.ledgerOpen(root, undefined, open, [options]);
}
