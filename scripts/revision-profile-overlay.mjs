// Test-only compatibility for historical row completion, not product behavior.
export const legacyCompletionViewPath = 'src/execution_relation/completed_legacy_view_wbtest.mbt';
export const legacyCompletionView = `///|
fn test_row_store(completion : CompletedSequence) -> TableStore[Table] {
  completion.store
}

///|
fn test_row_output(output : CompletedOutput) -> Table {
  output.table
}
`;

export function checkedProfileOverlay({ label, changed, untracked, fixtures, read }) {
  const allowed = new Set(fixtures);
  if (changed.some(path => !allowed.has(path))) throw new Error(`${label}: unauthorized source overlay`);
  if (untracked.some(path => path !== legacyCompletionViewPath)) {
    throw new Error(`${label}: unauthorized untracked overlay`);
  }
  if (untracked.length) {
    if (label !== 'baseline' || read(legacyCompletionViewPath) !== legacyCompletionView ||
        !/store\s*:\s*TableStore\[Table\]/.test(read('src/execution_relation/completion.mbt'))) {
      throw new Error(`${label}: invalid legacy completion view`);
    }
  }
  return [...changed, ...untracked];
}
