// One public-index commit attempt owns the transition from prepared custody
// to a durably confirmed index. The Store supplies its existing I/O and
// capacity owners; this owner neither accounts capacity nor changes the wire.
type Awaitable<T> = T | PromiseLike<T>;
type CleanupStatus = Readonly<{pending: boolean}>;
type Cleanup = Readonly<{status(): CleanupStatus; retry(): unknown}>;
type Custody<Entry> = Cleanup & Readonly<{
  settleAdopted(): unknown;
  resolveConfirmed(existing: Entry | undefined): unknown;
}>;
type Failure = Error & {
  primaryFailure?: unknown;
  outcome?: 'unknown';
  reconciliationFailure?: unknown;
  cleanupPending?: boolean;
  cleanupErrors?: readonly unknown[];
  cleanupHandle?: Cleanup;
};
type FailureFactory = (code: string, cause: unknown) => Failure;
type PrimaryFailure = Readonly<{
  code?: unknown; outcome?: unknown;
  cleanupHandle?: Readonly<{status?: () => CleanupStatus; retry?: () => unknown}>;
}> | null | undefined;
type CommitInput<Entry, Admitted, Key> = Readonly<{entry: Entry; admitted: Admitted; key: Key}>;
type Operations<Entry, Admitted, Key> = Readonly<{
  confirm(key: Key): Awaitable<Entry | undefined>;
  sameContent(existing: Entry, admitted: Admitted): Awaitable<boolean>;
  conflict(): never;
  verifyExistingInventory(existing: Entry): unknown;
  adopt(): unknown;
  stage(): unknown;
  beginCustody(): Awaitable<Custody<Entry>>;
  cancelStage?(): undefined;
  install(markInstalled: () => undefined): unknown;
  adoptObjects(): unknown;
  adoptSchemas(): unknown;
  makeFailure: FailureFactory;
}>;

const custodyFailure = (primary: unknown, custody: Cleanup, reconciliation: unknown, makeFailure: FailureFactory) => {
  if (custody.status().pending !== true) return primary;
  const child = (primary as PrimaryFailure)?.cleanupHandle;
  const childStatus = child?.status, childRetry = child?.retry;
  let cleanup = custody;
  if (child !== undefined && child !== custody) {
    let flight: Promise<CleanupStatus> | undefined;
    const status = () => Object.freeze({pending: typeof childStatus !== 'function' ||
      Reflect.apply(childStatus,child,[]).pending !== false || custody.status().pending});
    cleanup = Object.freeze({status,retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(async () => {
        if (typeof childStatus !== 'function' || typeof childRetry !== 'function') throw primary;
        if (Reflect.apply(childStatus,child,[]).pending !== false) await Reflect.apply(childRetry,child,[]);
        if (Reflect.apply(childStatus,child,[]).pending !== false) throw primary;
        if (custody.status().pending) await custody.retry();
        return status();
      }).finally(() => {flight = undefined;});
      return flight;
    }});
  }
  const code = typeof (primary as PrimaryFailure)?.code === 'string'
    ? (primary as PrimaryFailure)!.code as string : 'PublicationCommitUnknown';
  const failure = makeFailure(code, primary);
  failure.primaryFailure = primary;
  if ((primary as PrimaryFailure)?.outcome === 'unknown') failure.outcome = 'unknown';
  failure.reconciliationFailure = reconciliation;
  failure.cleanupPending = true;
  failure.cleanupErrors = Object.freeze(
    reconciliation === undefined ? [] : [reconciliation],
  );
  failure.cleanupHandle = cleanup;
  return failure;
};

export function createPublicationCommitOwner<Entry, Admitted, Key>(
  {entry, admitted, key}: CommitInput<Entry, Admitted, Key>, operations: Operations<Entry, Admitted, Key>) {
  let installed = false;
  let custody: Custody<Entry>;
  const sameContent = (existing: Entry) => operations.sameContent(existing, admitted);

  return Object.freeze({
    async commit() {
      const existingCommit = await operations.confirm(key);
      if (existingCommit !== undefined) {
        if (await sameContent(existingCommit) !== true) {
          operations.conflict();
        }
        await operations.verifyExistingInventory(existingCommit);
        await operations.adopt();
        return Object.freeze({
          entry: existingCommit,
          committed: false,
          idempotent: true,
        });
      }

      await operations.stage();
      try {custody = await operations.beginCustody();}
      catch (error) {operations.cancelStage?.(); throw error;}
      try {
        await operations.install(() => { installed = true; });
        await operations.adopt();
        await custody.settleAdopted();
        return Object.freeze({entry, committed: true, idempotent: false});
      } catch (primary) {
        let existing;
        try { existing = await operations.confirm(key); }
        catch (reconciliation) {
          throw custodyFailure(
            primary, custody, reconciliation, operations.makeFailure,
          );
        }
        if (existing === undefined) {
          await custody.resolveConfirmed(undefined);
          throw primary;
        }
        let same;
        try { same = await sameContent(existing); }
        catch (reconciliation) {
          throw custodyFailure(
            primary, custody, reconciliation, operations.makeFailure,
          );
        }
        if (same !== true) {
          await custody.resolveConfirmed(existing);
          operations.conflict();
        }
        try { await operations.adoptObjects(); }
        catch (reconciliation) {
          throw custodyFailure(
            primary, custody, reconciliation, operations.makeFailure,
          );
        }
        try {
          await operations.adoptSchemas();
          await custody.settleAdopted();
        } catch (reconciliation) {
          throw custodyFailure(primary, custody, reconciliation, operations.makeFailure);
        }
        return Object.freeze({
          entry: existing,
          committed: installed,
          idempotent: !installed,
        });
      }
    },
  });
}
