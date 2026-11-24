import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {ControlWork, prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';

type InstalledConstruction = ReturnType<typeof prepareInstalledEffectControlConstruction>;
type CodecFrames = Partial<Pick<InstalledConstruction, 'ledgerCodec' | 'receiptCodec'>>;
type LedgerFrames = ControlWork & Partial<Pick<InstalledConstruction, 'ledgerRow' | 'ledgerFamily'>>;
type LedgerMethod<Receiver> = (this: Receiver, ...args: unknown[]) => SynchronousRuntimeData;
type ReceiptCarrier = Extract<SynchronousRuntimeData, object>;
type ReceiptArguments = [rows: number, entryBytes: number, outcomeNodes: number, outcomeDepth: number];
type ReceiptConstructor = (...args: ReceiptArguments) => unknown;
type LedgerPolicy = Readonly<{
  maxEntries: number;
  maxEntryBytes: number;
  maxReadResponseBytes: number;
  maxNodes: number;
  maxDepth: number;
  maxOutcomeNodes: number;
  maxOutcomeDepth: number;
  runtime: object;
  receiptConstruction?: ReceiptConstructor;
}>;

export const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};

// Ledger and Receipt codecs keep their genuine parser/writer families. Their
// immutable original wires can refine workspace without supplying admission.
// These are closed installing-code methods, never caller callbacks.
export function bindEffectLedgerCodecs<Control extends object>(original: Control, construction?: CodecFrames): Readonly<Control> {
  if (typeof construction?.ledgerCodec !== 'function') return original;
  const codec = construction.ledgerCodec;
  const control = {...original};
  for (const name of ['admitLedgerEntry', 'issuePreparedLedgerEntry',
    'issueNextLedgerEntry', 'issueRowReceiptTerminalEntry',
    'issueRowReceiptTerminalEntryFromResponse']) {
    const method = (original as Record<string, unknown>)[name];
    if (typeof method !== 'function') fail('EffectLedgerControlRuntimeUnavailable');
    (control as Record<string, unknown>)[name] = (...args: unknown[]) => Reflect.apply(codec, construction,
      [original, method as LedgerMethod<Control>, args, name === 'admitLedgerEntry' ? args[0] as string : undefined,
        args.at(-2) as number, args.at(-1) as number]);
  }
  const receiptCodec = construction.receiptCodec;
  if (typeof receiptCodec === 'function') {
    for (const [name, wireIndex, receiptWire] of [
      ['issueRowOutcomeReceipt', 7, false],
      ['issueRowOutcomeReceiptFromResponse', 5, false],
      ['admitRowOutcomeReceipt', 7, true],
      ['admitRowOutcomeReceiptFromResponse', 5, true],
      ['issueRowReceiptTerminalEntry', 13, true],
      ['issueRowReceiptTerminalEntryFromResponse', 11, true],
    ] as const) {
      const method = (original as Record<string, unknown>)[name];
      if (typeof method !== 'function') fail('EffectLedgerControlRuntimeUnavailable');
      (control as Record<string, unknown>)[name] = (...args: unknown[]) => Reflect.apply(receiptCodec, construction,
        [original, method as LedgerMethod<Control>, args, args[wireIndex] as string,
          args.at(-2) as number, args.at(-1) as number, receiptWire]);
    }
  }
  return Object.freeze(control);
}

// MoonBit admits the canonical fact and its transition. SQLite only owns
// durable bytes and the atomic compare-and-swap of one item head.
// Original receivers select closed row or frontier construction classes;
// unknown work keeps the generic frame. The funded quantity call below
// constructs only a fixed numeric quote before the real member Receipt body.
// Its returned carrier stays on the same control until the next body call;
// the body then grows its aggregate workspace before any Receipt allocation.
function prepareMemberReceiptConstruction(this: LedgerPolicy, args: unknown[]): ReceiptCarrier | undefined {
  const rowOwners = (args[0] as {rowOwners?: unknown} | undefined)?.rowOwners;
  if (nodeTypes.isProxy(rowOwners) || !Array.isArray(rowOwners)) fail('InvalidEffectMemberReceiptEvidence');
  const rows = rowOwners.length;
  if (rows > this.maxEntries) fail('InvalidEffectMemberReceiptEvidence');
  args[2] = rows; args[3] = rowOwners;
  if (rows === 0) return undefined;
  return checked(Reflect.apply(this.receiptConstruction!, this.runtime,
    [rows, this.maxEntryBytes, this.maxOutcomeNodes, this.maxOutcomeDepth])) as ReceiptCarrier;
}

export function bindEffectLedgerConstruction<Ledger extends object>(
  ledger: Ledger, construction: LedgerFrames, policy: LedgerPolicy): Readonly<Ledger> {
  const caller: Record<string, unknown> = {};
  for (const name of Object.keys(ledger)) {
    const method = (ledger as Record<string, unknown>)[name];
    caller[name] = typeof method !== 'function' ? method : name === 'close'
      ? (...args: unknown[]) => Reflect.apply(method, ledger, args)
      : (...args: unknown[]) => {
        if ((name === 'issueMemberReceiptFromRowPartition' || name === 'checkMemberReceiptRowPartitionEvidence') &&
            typeof policy.receiptConstruction === 'function') {
          const prepared = typeof construction.ledgerRow === 'function'
            ? construction.ledgerRow(policy, prepareMemberReceiptConstruction, [args], 'quantity',
              policy.maxEntryBytes, policy.maxNodes, policy.maxDepth, policy.maxReadResponseBytes)
            : construction(policy, prepareMemberReceiptConstruction, [args]);
          // This is the existing private Ledger receiver. Public callers cannot
          // inject a quote: their second argument is replaced at this boundary.
          args[1] = prepared;
          return construction(ledger, method as LedgerMethod<Ledger>, args, prepared === undefined ? undefined : runtimeField(prepared, 0), prepared !== undefined);
        }
        const rowKind = name === 'claimDispatch' || name === 'beginPhysicalFlight' || name === 'readClaimedResponse'
          ? 'entry' : name === 'recordResponse' ? 'response'
            : name === 'recordAdmittedRowOutcome' || name === 'commitAdmittedRowOutcome' || name === 'readAdmittedTerminalOutcome'
              ? 'receipt' : undefined;
        if (rowKind !== undefined && typeof construction.ledgerRow === 'function') {
          return construction.ledgerRow(ledger, method as LedgerMethod<Ledger>, args, rowKind,
            policy.maxEntryBytes, policy.maxNodes, policy.maxDepth, policy.maxReadResponseBytes);
        }
        // These family selections read only frozen DATA lengths. Mutable or
        // nonstandard callers keep their exact original generic path.
        const members = args[1];
        let counts: number[] | undefined;
        if ((name === 'current' || name === 'currentAdmitted') &&
            typeof construction.ledgerFamily === 'function') {
          // One original CID lookup returns at most one durable head. Reuse
          // the SAME common family quote; validation and absence remain with
          // physical.current/validateStored, including their nested codec.
          counts = [1];
        } else if ((name === 'frontierFromDurableHeads' || name === 'frontierFromCapturedHeads' ||
             name === 'recoveredTargetGuards' || name === 'prepareSetIntents' ||
             name === 'prepareCapturedSetIntents') && typeof construction.ledgerFamily === 'function' &&
            !nodeTypes.isProxy(members) && Array.isArray(members) && Object.isFrozen(members) &&
            members.length > 0 && members.length <= 1000) {
          counts = new Array(members.length);
          for (let index = 0; index < members.length; index++) {
            const member: unknown = Object.getOwnPropertyDescriptor(members, index)?.value;
            if (member === null || typeof member !== 'object' || nodeTypes.isProxy(member) || !Object.isFrozen(member)) {counts = undefined; break;}
            const claims: unknown = Object.getOwnPropertyDescriptor(member, 'claims')?.value;
            if (nodeTypes.isProxy(claims) || !Array.isArray(claims) || !Object.isFrozen(claims)) {counts = undefined; break;}
            counts[index] = claims.length;
          }
        }
        return counts === undefined ? construction(ledger, method as LedgerMethod<Ledger>, args)
          : construction.ledgerFamily!(ledger, method as LedgerMethod<Ledger>, args, Object.freeze(counts),
            policy.maxEntries, policy.maxEntryBytes, policy.maxNodes, policy.maxDepth);
      };
  }
  return Object.freeze(caller) as Readonly<Ledger>;
}
