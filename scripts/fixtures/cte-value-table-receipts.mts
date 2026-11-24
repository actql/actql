import type {exercisePublicQueryInput} from './public-query-input.mjs';

type Hooks = Parameters<typeof exercisePublicQueryInput>[2];
type CompletedCase = Parameters<NonNullable<Hooks['completedCase']>>[0];
type CompletedRefusal = Parameters<NonNullable<Hooks['completedRefusal']>>[0];
type RecordedCase = Pick<CompletedCase, 'name' | 'ref' | 'submissionRef' | 'observedResults' | 'beforeSubmit' | 'beforeRead'> &
  Partial<Pick<CompletedCase, 'afterReplay'>>;
type CaseReceipt = Omit<RecordedCase, 'observedResults'> & {mode: string; results: RecordedCase['observedResults']};
type RefusalReceipt = CompletedRefusal & {mode: string};
type WriteReceipt = (path: string, contents: string) => unknown;

// Retain verified reader observations across the profile loop and its final
// transport inventory check. This fixture utility performs no Client I/O.
export function createCteValueTableReceipts(mode: string, writeFile: WriteReceipt) {
  return createVerifiedCaseReceipts(mode, writeFile, {
    prefix: 'cte-value-table', version: 'actql-cte-value-table-acceptance/0.1',
  });
}

// The completed-case hook supplies observations only after public comparison.
// This transport-lifetime collector performs no additional Client operation.
export function createVerifiedCaseReceipts(
  mode: string, writeFile: WriteReceipt, {prefix, version}: {prefix: string; version: string},
) {
  const cases: CaseReceipt[] = [], refusals: RefusalReceipt[] = [];
  const persist = async (complete: boolean) => {
    if (cases.length === 0 && refusals.length === 0) return;
    await writeFile(`${prefix}-receipts.${mode}.json`, JSON.stringify({
      version, mode, complete, cases,
      ...(refusals.length === 0 ? {} : {refusals}),
    }) + '\n');
  };
  return {
    async record(item: RecordedCase, caseMode = mode) {
      cases.push({mode: caseMode, name: item.name, ref: item.ref,
        submissionRef: item.submissionRef,
        results: item.observedResults, beforeSubmit: item.beforeSubmit, beforeRead: item.beforeRead,
        ...(item.afterReplay === undefined ? {} : {afterReplay: item.afterReplay})});
      await persist(false);
    },
    async recordRefusal(item: CompletedRefusal, caseMode = mode) {
      refusals.push({mode: caseMode, name: item.name, submissionRef: item.submissionRef,
        outcome: item.outcome, beforeSubmit: item.beforeSubmit, afterRefusal: item.afterRefusal});
      await persist(false);
    },
    async complete() { await persist(true); },
  };
}
