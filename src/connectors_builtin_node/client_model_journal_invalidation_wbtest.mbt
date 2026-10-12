///|
extern "js" fn journal_loader_refuses_foreign_port(
  loader : OriginalModelJournalModuleLoader,
) -> Bool =
  #|(loader) => {
  #|  const journal = loader('../../../../../adapters/host-node/model-resume-state.mjs');
  #|  try {
  #|    journal.assertOriginalModelJournalInvalidation({}, {}, {}, {}, {});
  #|    return false;
  #|  } catch (error) {
  #|    return error?.code === 'ForeignModelOriginalJournalPort';
  #|  }
  #|}

///|
test "Node journal module imports load in the same ESM test artifact" {
  let loader = original_model_journal_module_loader(
    original_model_runtime_module_url(),
  )
  assert_true(journal_loader_refuses_foreign_port(loader))
}
