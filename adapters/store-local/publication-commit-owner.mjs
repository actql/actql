// One public-index commit attempt owns the transition from prepared custody
// to a durably confirmed index. The Store supplies its existing I/O and
// capacity owners; this owner neither accounts capacity nor changes the wire.
const custodyFailure = (primary, custody, reconciliation, makeFailure) => {
  if (custody.status().pending !== true) return primary;
  const code = typeof primary?.code === 'string'
    ? primary.code : 'PublicationCommitUnknown';
  const failure = makeFailure(code, primary);
  failure.primaryFailure = primary;
  failure.reconciliationFailure = reconciliation;
  failure.cleanupPending = true;
  failure.cleanupErrors = Object.freeze(
    reconciliation === undefined ? [] : [reconciliation],
  );
  failure.cleanupHandle = custody;
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
      custody = operations.beginCustody();
      try {
        await operations.install(() => { installed = true; });
        await operations.adopt();
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
        return Object.freeze({
          entry: existing,
          committed: installed,
          idempotent: !installed,
        });
      }
    },
  });
}
