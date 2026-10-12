///|
#external
type OriginalModelJournalReference

///|
// The pinned compiler does not accept relative #module imports. Node's fixed
// physical module loader resolves the same owned adapter at the runtime's
// existing package layout; no caller supplies this loader or its module path.
#external
priv type OriginalModelJournalModuleLoader

///|
#module("node:module")
extern "js" fn original_model_journal_module_loader(
  url : String,
) -> OriginalModelJournalModuleLoader = "createRequire"

///|
extern "js" fn original_model_runtime_module_url() -> String =
  #|() => import.meta.url

///|
extern "js" fn assert_original_model_journal_invalidation(
  loader : OriginalModelJournalModuleLoader,
  port : OriginalModelJournalReference,
  receipt : OriginalModelJournalReference,
  reference : OriginalModelJournalReference,
  park : @publication_host.ClientModelResourcePark,
  request : @publication_host.ClientModelResourceInvalidationRequest,
) -> Unit =
  #|(loader, port, receipt, reference, park, request) => {
  #|  const journal = loader('../../../../../adapters/host-node/model-resume-state.mjs');
  #|  journal.assertOriginalModelJournalInvalidation(port, receipt, reference, park, request);
  #|}

///|
#export_name("clientProgramBeginInferOriginalModelInvalidation")
pub fn client_program_begin_infer_original_model_invalidation(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
) -> Result[
  @publication_host.ClientModelResourceInvalidationRequest,
  @infer_host.Issue,
] {
  @infer_host.begin_original_model_resource_invalidation(active, scope, park)
}

///|
#export_name("clientProgramInferOriginalModelInvalidationCurrent")
pub fn client_program_infer_original_model_invalidation_current(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  request : @publication_host.ClientModelResourceInvalidationRequest,
) -> @publication_host.ClientModelResourceInvalidationRequest? {
  @infer_host.original_model_resource_invalidation_current(
    active, scope, park, request,
  )
}

///|
// No bare consume export: a copied tag, arbitrary function, CID or Bool cannot
// pass the fixed actual-journal issuer's WeakMap and exact four-reference check.
// Recheck the original Core lifecycle AFTER that check and consume once. No
// await/user callback/new request occurs between the final check and transition.
#export_name("clientProgramCompleteInferOriginalJournalInvalidation")
pub fn client_program_complete_infer_original_journal_invalidation(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  port : OriginalModelJournalReference,
  receipt : OriginalModelJournalReference,
  reference : OriginalModelJournalReference,
  park : @publication_host.ClientModelResourcePark,
  request : @publication_host.ClientModelResourceInvalidationRequest,
) -> Result[Unit, @infer_host.Issue] {
  let loader = original_model_journal_module_loader(
    original_model_runtime_module_url(),
  )
  assert_original_model_journal_invalidation(
    loader, port, receipt, reference, park, request,
  )
  @infer_host.consume_original_model_resource_invalidation(
    active, scope, park, request,
  )
}
