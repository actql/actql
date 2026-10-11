// Retain verified reader observations across the profile loop and its final
// transport inventory check. This fixture utility performs no Client I/O.
export function createCteValueTableReceipts(mode, writeFile) {
  const cases = [];
  const persist = async complete => {
    if (cases.length === 0) return;
    await writeFile(`cte-value-table-receipts.${mode}.json`, JSON.stringify({
      version: 'actql-cte-value-table-acceptance/0.1', mode, complete, cases,
    }) + '\n');
  };
  return {
    async record(item, caseMode = mode) {
      cases.push({mode: caseMode, name: item.name, ref: item.ref,
        results: item.observedResults, beforeSubmit: item.beforeSubmit, beforeRead: item.beforeRead});
      await persist(false);
    },
    async complete() { await persist(true); },
  };
}
