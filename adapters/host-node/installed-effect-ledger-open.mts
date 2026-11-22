import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {openEffectLedger} from './effect-ledger.mjs';

type RequestIdentityReader<Identity> = Readonly<{
  clientRequestAuthorityScopeCid(identity: Identity): string;
  clientRequestCallerId(identity: Identity): string;
}>;
type LedgerOwner = Extract<SynchronousRuntimeData, object>;
type LedgerConstruction = NonNullable<Parameters<typeof openEffectLedger>[0]['controlConstruction']>;
type LedgerOpen<Runtime, Value extends LedgerOwner> = (options: Readonly<{
  moon: Runtime;
  root: string;
  authorityScopeCid: string;
  callerRequestId: string;
  maxEntryBytes: number;
  maxReadResponseBytes: number;
  controlConstruction?: LedgerConstruction;
}>) => Value;

// Same installed request and control frame. Receiver bounds constrain physical
// reads; they do not rewrite the installation's durable response policy.
export function openInstalledEffectLedger<Identity, Runtime extends RequestIdentityReader<Identity>>(
  moon: Runtime, root: string, identity: Identity, maxEntryBytes: number,
  maxReadResponseBytes: number, controlConstruction: LedgerConstruction | undefined, open?: undefined): ReturnType<typeof openEffectLedger>;
export function openInstalledEffectLedger<Identity, Runtime extends RequestIdentityReader<Identity>, Value extends LedgerOwner>(
  moon: Runtime, root: string, identity: Identity, maxEntryBytes: number,
  maxReadResponseBytes: number, controlConstruction: LedgerConstruction | undefined, open: LedgerOpen<Runtime, Value>): Value;
export function openInstalledEffectLedger<Identity, Runtime extends RequestIdentityReader<Identity>>(
  moon: Runtime, root: string, identity: Identity, maxEntryBytes: number,
  maxReadResponseBytes: number, controlConstruction: LedgerConstruction | undefined,
  open: LedgerOpen<Runtime, LedgerOwner> = openEffectLedger): LedgerOwner {
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
