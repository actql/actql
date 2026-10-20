///|
pub(all) enum LocalRunPublicationBindingIssue[E] {
  Current(@host.ClientLocalAdoptedCurrentIssue[E])
  AuthorizationMismatch
  ForeignScope
  ForeignPreparation
  CustodyLost
  MissingOriginal
  CapacityExceeded
  SavedRows(LocalSubmittedRunRowsIssue)
  Policy(@host.ClientRunPolicyOriginalsIssue)
  Encoding(@host.ClientJournalEncodingIssue)
  StoreEncoding(@host.ClientPublicationStoreBindingIssue)
}

///|
/// Original saved publication binding/current custody, never a permission or ACK.
pub struct LocalRunPublicationBinding[Store, E] {
  plan : LocalRunPlan
  rows : LocalSubmittedRunRows
  preparation : @input.LocalSubmittedPreparation
  material : @host.ClientLocalAdoptedHostMaterial[Store, E]
  store : Store
  binding : String
  policy : String
}

///|
/// Original row CAS candidate. No caller chooses Run fields or a terminal state.
pub struct LocalRunPublicationBindingStep[Store, E] {
  original : LocalRunPublicationBinding[Store, E]
  prior : @host.ClientJournalPhysicalRow
  body : Bytes
}

///|
pub(all) enum LocalRunPublicationBindingPlan[Store, E] {
  Retained(LocalRunPublicationBinding[Store, E])
  Append(LocalRunPublicationBindingStep[Store, E])
}

///|
fn[Store, E] publication_binding_current(
  original : LocalRunPublicationBinding[Store, E],
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  let account = match
    @host.client_local_adopted_current_account(
      original.material,
      original.store,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Current(issue))
  }
  if account.account_id() != original.plan.account_id {
    return Err(AuthorizationMismatch)
  }
  let tuple : @authorization.AccessTuple = {
    ..original.plan.tuple,
    resource: "run",
    operation: "publish",
  }
  match
    @host.client_local_adopted_account_outcome(
      original.material,
      original.store,
      tuple,
    ) {
    Ok(@authorization.Allow(_)) => ()
    Ok(_) => return Err(AuthorizationMismatch)
    Err(issue) => return Err(Current(issue))
  }
  let scope = match
    @host.client_local_adopted_authority_scope_body(
      original.material,
      original.store,
      original.plan.tuple.principal,
      original.plan.tuple.connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Current(issue))
  }
  if "sha256:" + @sha.hex(scope) !=
    @host.client_request_authority_scope_cid(original.plan.request) {
    return Err(ForeignScope)
  }
  Ok(())
}

///|
fn[Store, E] publication_binding_saved_rows(
  original : LocalRunPublicationBinding[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
) -> Result[
  (@host.ClientRunJournalEncoding, String?, String?),
  LocalRunPublicationBindingIssue[E],
] {
  match
    validate_local_saved_submitted_rows(
      original.rows,
      original.plan,
      original.preparation,
      run.key,
      run.revision,
      run.body,
      submitted.key,
      submitted.revision,
      submitted.body,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(SavedRows(issue))
  }
  let decoded = match
    @host.decode_client_run_journal_row_with_observation_originals(run.body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let (encoding, _, _) = decoded
  if encoding.cancellation_requested ||
    encoding.checkpoint is Some(_) ||
    encoding.effect_material_originals is Some(_) {
    return Err(CustodyLost)
  }
  Ok(decoded)
}

///|
/// Reuse original checked policy/row/adoption Owners before dispatch. The
/// physical Host supplies this Store's namespace/target/file facts; a codec
/// result cannot authenticate that supplier. Current scope/publish and actual
/// saved Run/submission relationships are checked independently. No policy is
/// issued from current defaults, and a started Run cannot repair missing custody.
pub fn[Store, E] prepare_local_run_publication_binding(
  plan : LocalRunPlan,
  rows : LocalSubmittedRunRows,
  preparation : @input.LocalSubmittedPreparation,
  material : @host.ClientLocalAdoptedHostMaterial[Store, E],
  store : Store,
  namespace_id : String,
  store_authority_cid : String,
  device : UInt64,
  inode : UInt64,
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
) -> Result[
  LocalRunPublicationBindingPlan[Store, E],
  LocalRunPublicationBindingIssue[E],
] {
  if !physical_equal(rows.plan, plan) ||
    !physical_equal(rows.preparation, preparation) {
    return Err(ForeignPreparation)
  }
  // Match the existing Native installation selector bounds. The pure binding
  // codec remains a byte projection, not admission of arbitrary selectors.
  if namespace_id.is_empty() ||
    namespace_id.length() > 128 ||
    store_authority_cid.length() != 71 ||
    !store_authority_cid.has_prefix("sha256:") {
    return Err(CustodyLost)
  }
  for index in 7..<store_authority_cid.length() {
    let code = store_authority_cid[index]
    if !((code >= '0' && code <= '9') || (code >= 'a' && code <= 'f')) {
      return Err(CustodyLost)
    }
  }
  let binding = match
    @host.client_publication_store_binding_body(
      namespace_id, store_authority_cid, device, inode,
    ) {
    Ok(value) => value
    Err(issue) => return Err(StoreEncoding(issue))
  }
  let policy = match
    @host.issue_client_run_policy_originals(
      plan.prepared,
      compiled=plan.compiled,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  let original = { plan, rows, preparation, material, store, binding, policy, }
  match publication_binding_current(original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (encoding, finite_policy, observation_originals) = match
    publication_binding_saved_rows(original, run, submitted) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if encoding.publication_binding is Some(value) && value != binding {
    return Err(CustodyLost)
  }
  if encoding.publication_policy_originals is Some(value) && value != policy {
    return Err(CustodyLost)
  }
  if encoding.publication_binding == Some(binding) &&
    encoding.publication_policy_originals == Some(policy) {
    match publication_binding_current(original) {
      Ok(_) => return Ok(Retained(original))
      Err(issue) => return Err(issue)
    }
  }
  if encoding.dispatch_reserved || encoding.physical_start_claimed {
    return Err(MissingOriginal)
  }
  if run.revision < 0L || run.revision == 9223372036854775807L {
    return Err(CapacityExceeded)
  }
  let body = match
    @host.client_run_journal_row_body(
      {
        ..encoding,
        publication_binding: Some(binding),
        publication_policy_originals: Some(policy),
      },
      local_run_policy_originals=finite_policy,
      run_observation_originals=observation_originals,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  match publication_binding_current(original) {
    Ok(_) => Ok(Append({ original, prior: run, body, }))
    Err(issue) => Err(issue)
  }
}

///|
/// Original CAS fields only; this output proves no physical write or admission.
pub fn[Store, E] local_run_publication_binding_rows(
  step : LocalRunPublicationBindingStep[Store, E],
) -> (String, Int64, Bytes) {
  (step.prior.key, step.prior.revision, step.body)
}

///|
/// Validate the actual prior under the same trusted current write snapshot.
pub fn[Store, E] validate_local_run_publication_binding(
  step : LocalRunPublicationBindingStep[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  match publication_binding_current(step.original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if run.key != step.prior.key ||
    run.revision != step.prior.revision ||
    run.body != step.prior.body {
    return Err(CustodyLost)
  }
  match publication_binding_saved_rows(step.original, run, submitted) {
    Ok(_) => publication_binding_current(step.original)
    Err(issue) => Err(issue)
  }
}

///|
/// Readmit the actual same-Store successor, never a Bool/generation tuple or
/// copied candidate. Retained custody still grants no publisher, read or ACK.
pub fn[Store, E] confirm_local_run_publication_binding(
  step : LocalRunPublicationBindingStep[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
) -> Result[
  LocalRunPublicationBinding[Store, E],
  LocalRunPublicationBindingIssue[E],
] {
  match publication_binding_current(step.original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if run.key != step.prior.key ||
    run.revision != step.prior.revision + 1L ||
    run.body != step.body {
    return Err(CustodyLost)
  }
  match publication_binding_saved_rows(step.original, run, submitted) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match publication_binding_current(step.original) {
    Ok(_) => Ok(step.original)
    Err(issue) => Err(issue)
  }
}

///|
/// Revalidate the same confirmed/retained originals at later saved revisions.
/// This does not reserve dispatch, replace missing policy, or confirm an index.
pub fn[Store, E] validate_local_run_publication_binding_original(
  original : LocalRunPublicationBinding[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  match publication_binding_current(original) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (encoding, _, _) = match
    publication_binding_saved_rows(original, run, submitted) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if encoding.publication_binding != Some(original.binding) ||
    encoding.publication_policy_originals != Some(original.policy) {
    return Err(MissingOriginal)
  }
  publication_binding_current(original)
}
