// One public-index commit attempt owns the transition from prepared custody
// to a durably confirmed index. The Store supplies its existing I/O and
// capacity owners; this owner neither accounts capacity nor changes the wire.
const custodyFailure = (primary, custody, reconciliation, makeFailure) => {
  if (custody.status().pending !== true) return primary;
  const child = primary?.cleanupHandle;
  const childStatus = child?.status, childRetry = child?.retry;
  let cleanup = custody;
  if (child !== undefined && child !== custody) {
    let flight;
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
  const code = typeof primary?.code === 'string'
    ? primary.code : 'PublicationCommitUnknown';
  const failure = makeFailure(code, primary);
  failure.primaryFailure = primary;
  if (primary?.outcome === 'unknown') failure.outcome = 'unknown';
  failure.reconciliationFailure = reconciliation;
  failure.cleanupPending = true;
  failure.cleanupErrors = Object.freeze(
    reconciliation === undefined ? [] : [reconciliation],
  );
  failure.cleanupHandle = cleanup;
  return failure;
};

export function createPublicationCommitOwner({entry, admitted, key}, operations) {
  let installed = false;
  let custody;
  const sameContent = existing => operations.sameContent(existing, admitted);

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
        await operations.adoptSchemas();
        await custody.settleAdopted();
        return Object.freeze({
          entry: existing,
          committed: installed,
          idempotent: !installed,
        });
      }
    },
  });
}
