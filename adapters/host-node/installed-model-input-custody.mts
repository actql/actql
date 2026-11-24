import type {createModelResumeState} from './model-resume-state.mjs';
import type {createGeneratedContentRunRecovery} from './generated-content-run-recovery.mjs';

type Verifier = NonNullable<Parameters<typeof createModelResumeState>[1]['verifier']>;
type Originals = Omit<Parameters<NonNullable<Verifier['admitCallSet']>>[0], 'fixedInputReceiptWire'> &
  Readonly<{inputArtifactWire: string; expectedBoundary: Readonly<Record<string, unknown>>}>;
type RestoredContent = NonNullable<Parameters<ReturnType<typeof createGeneratedContentRunRecovery>>[0]['restoredInput']>;
type Receipt = Readonly<{ownerId: string; cid: string; runId: string; runDefinitionCid: string}>;
type Snapshot = Readonly<{
  version: 'actql-installed-model-input/0.1';
  scopeCid: string; inputArtifactCid: string; originals: Originals;
  binding: string; descriptorWire: string; rows: readonly unknown[];
  callScopeSnapshotWire: string; providerOriginals?: unknown; submission: unknown;
  sourceContinuation?: unknown; providerInputs?: readonly unknown[];
  contentGeneration?: RestoredContent['snapshot']['contentGeneration'];
  capturedContent?: RestoredContent['capturedContent']; capturedContentBinding?: RestoredContent['capturedContentBinding'];
}>;
type Token = Readonly<{receipt: Receipt; snapshot: Snapshot | undefined; available: boolean}>;
type Lease = Readonly<{
  receiptWire: string; tokens: Set<Token>;
  state: {available: boolean; snapshot: Snapshot | undefined}; bytes: number;
}>;
type Failure = {code?: string; message?: string} | null | undefined;
type Inputs = Readonly<{
  inventorySize(): number; retireReceipt(receiptWire: string): void;
  diagnostic(name: string, detail: object): void;
  fail(code: string): never;
}>;

// The input lease owns only the decoded payload and its local accounting.
// Journal retirement, durable Store custody, and send admission belong to
// the installed continuation's existing owners.
export function createInstalledModelInputCustody({inventorySize, retireReceipt, diagnostic, fail}: Inputs) {
  const custody = new Map<string, Set<Token>>();
  const leases = new WeakMap<Token, Lease>();
  let retainedInputs = 0, retainedInputBytes = 0;
  const usage = () => Object.freeze({retainedInputScopes: custody.size,
    retainedInputs, retainedInputBytes, retainedInventoryScopes: inventorySize()});
  const changed = () => diagnostic('model_input_custody_changed', usage());
  function retain(receiptWire: string, receipt: Receipt, snapshot: Snapshot, bytes: number): Token {
    immutableInput(receipt);
    immutableInput(snapshot);
    let tokens = custody.get(receiptWire);
    if (tokens === undefined) custody.set(receiptWire, tokens = new Set());
    const state: Lease['state'] = {available: true, snapshot};
    const token = Object.freeze({receipt, get snapshot() { return state.snapshot; },
      get available() { return state.available; }});
    leases.set(token, {receiptWire, tokens, state, bytes});
    tokens.add(token);
    retainedInputs++;
    retainedInputBytes += bytes;
    changed();
    return token;
  }
  function ownedInput(token: Token, runDefinitionCid: string): Snapshot {
    const lease = leases.get(token);
    if (lease === undefined || !lease.state.available ||
        lease.tokens.has(token) !== true || token.receipt.runDefinitionCid !== runDefinitionCid) {
      fail('ModelFixedInputCustodyUnavailable');
    }
    return token.snapshot!;
  }
  // The authenticated receipt covers these exact values. Borrowers may not
  // replace a captured reference or scope after receipt verification. Walk
  // the already byte-bounded decoded tree without another serialized copy.
  function immutableInput<Value>(value: Value) {
    const pending: unknown[] = [value];
    while (pending.length > 0) {
      const next = pending.pop();
      if (next !== null && typeof next === 'object') {
        for (const child of Object.values(next)) {
          if (child !== null && typeof child === 'object') pending.push(child);
        }
        Object.freeze(next);
      }
    }
    return value;
  }
  function release(token: Token | undefined) {
    const lease = leases.get(token!);
    if (lease === undefined) return;
    lease.state.available = false;
    // Retire only this lease's decoded input. Escaped borrows and
    // independently retained consumers keep their own original custody.
    lease.state.snapshot = undefined;
    leases.delete(token!);
    lease.tokens.delete(token!);
    if (lease.tokens.size === 0 && custody.get(lease.receiptWire) === lease.tokens) {
      custody.delete(lease.receiptWire);
    }
    retainedInputs--;
    retainedInputBytes -= lease.bytes;
    try { retireReceipt(lease.receiptWire); }
    catch (error) {
      // A later sweep can retire small journal metadata. It cannot undo the
      // payload release or replace an earlier execution/admission failure.
      diagnostic('model_input_retirement_pending', {code: (error as Failure)?.code ?? (error as Failure)?.message});
    }
    changed();
  }
  return Object.freeze({retain, ownedInput, release, usage, changed,
    hasRetainedReceipt: (receiptWire: string) => custody.has(receiptWire),
    firstRetained: (receiptWire: string) => custody.get(receiptWire)?.values().next().value,
    leaseReceiptWire: (token: Token) => leases.get(token)?.receiptWire,
  });
}
