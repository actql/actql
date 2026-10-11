// Retain verified reader observations across the profile loop and its final
// transport inventory check. This fixture utility performs no Client I/O.
export function createCteValueTableReceipts(mode, writeFile) {
  return createVerifiedCaseReceipts(mode, writeFile, {
    prefix: 'cte-value-table', version: 'actql-cte-value-table-acceptance/0.1',
  });
}

// The completed-case hook supplies observations only after public comparison.
// This transport-lifetime collector performs no additional Client operation.
export function createVerifiedCaseReceipts(mode, writeFile, {prefix, version}) {
  const cases = [];
  const persist = async complete => {
    if (cases.length === 0) return;
    await writeFile(`${prefix}-receipts.${mode}.json`, JSON.stringify({
      version, mode, complete, cases,
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
