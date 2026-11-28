///|
/// One exact Run row successor built from the retained captured Task.
pub struct LocalCapturedTaskPublicationStep[Store, E] {
  candidate : @host.ClientCapturedTaskFirstRunRows
  adopted : @host.ClientLocalAdoptedHostMaterial[Store, E]
  store : Store
  account_id : String
  tuple : @authorization.AccessTuple
  store_authority_cid : String
  body : Bytes
}

///|
/// Same-Store readback of the actual publication row, before dispatch.
pub struct LocalCapturedTaskPublicationBinding[Store, E] {
  step : LocalCapturedTaskPublicationStep[Store, E]
}

///|
/// Project just the original physical publication binding onto the first Run.
/// The original Task, finite policy and publication policy stay in the row.
/// The caller funds all construction and fences each fund callback to its Read.
pub fn[Store, E] prepare_local_captured_task_publication_binding(
  preparing : @host.ClientSavedSubmissionSnapshot,
  saved : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  candidate : @host.ClientCapturedTaskFirstRunRows,
  materials : @host.ClientCapturedTaskRunMaterials,
  adopted : @host.ClientLocalAdoptedHostMaterial[Store, E],
  store : Store,
  account_id : String,
  tuple : @authorization.AccessTuple,
  namespace_id : String,
  store_authority_cid : String,
  device : UInt64,
  inode : UInt64,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
  fund_store_binding : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
  fund_decode : (@host.ClientRunJournalConstruction) -> Result[
    Unit,
    @host.ClientJournalDecodingIssue,
  ],
  fund_encode : (Int, Int, Int) -> Result[
    Unit,
    @host.ClientJournalEncodingIssue,
  ],
) -> Result[
  LocalCapturedTaskPublicationStep[Store, E],
  LocalRunPublicationBindingIssue[E],
] {
  fn current() -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
    validate_read()
    .bind(_ => {
      local_publication_store_current(
        adopted,
        store,
        account_id,
        tuple,
        materials.request,
      )
    })
    .bind(_ => validate_read())
  }
  current()
  .bind(_ => {
    @host.client_first_captured_task_saved_rows(
      preparing, saved, materials, candidate, locator,
    ).map_err(_ => CustodyLost)
  })
  .bind(first => {
    let (record, finite_policy, observations) = match
      @host.decode_client_run_journal_row_with_retained_identity(
        first.run.body,
        materials.request,
        materials.definition,
        before_construction=Some(fund_decode),
      ) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    guard record.publication_binding is None &&
      record.task_materials_cid == Some(candidate.task_materials.cid) &&
      record.publication_policy_originals ==
      Some(candidate.task_materials.publication_policy_originals) &&
      finite_policy is Some(_) &&
      observations is Some(_) &&
      record.checkpoint is None &&
      record.effect_material_originals is None &&
      !record.cancellation_requested() &&
      !record.dispatch_reserved &&
      !record.physical_start_claimed else {
      return Err(CustodyLost)
    }
    if @publication.run_definition_namespace(materials.definition) !=
      Some(namespace_id) {
      return Err(ForeignScope)
    }
    let binding = match
      current()
      .bind(_ => fund_store_binding())
      .bind(_ => current())
      .bind(_ => {
        local_publication_store_binding_body(
          namespace_id, store_authority_cid, device, inode,
        )
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    @host.client_run_journal_row_body(
      { ..record, publication_binding: Some(binding), },
      local_run_policy_originals=finite_policy,
      run_observation_originals=observations,
      before_construction=Some(fund_encode),
    )
    .map_err(issue => LocalRunPublicationBindingIssue::Encoding(issue))
    .bind(body => {
      current().map(_ => {
        candidate,
        adopted,
        store,
        account_id,
        tuple,
        store_authority_cid,
        body,
      })
    })
  })
}

///|
/// Use the original Run key, revision and body for the one physical CAS.
pub fn[Store, E] local_captured_task_publication_rows(
  step : LocalCapturedTaskPublicationStep[Store, E],
) -> (@host.ClientJournalPhysicalRow, Bytes) {
  let (key, body, _, _) = @host.client_run_journal_append_rows(
    step.candidate.run,
  )
  ({ key, revision: 0L, body, }, step.body)
}

///|
fn[Store, E] captured_task_publication_current(
  step : LocalCapturedTaskPublicationStep[Store, E],
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  local_publication_store_current(
    step.adopted,
    step.store,
    step.account_id,
    step.tuple,
    step.candidate.task_materials.plan.request,
  )
}

///|
fn[Store, E] captured_task_publication_companions_match(
  step : LocalCapturedTaskPublicationStep[Store, E],
  submitted : @host.ClientJournalPhysicalRow,
  locator : @host.ClientJournalPhysicalRow,
) -> Bool {
  let candidate = step.candidate
  submitted.key == candidate.preparing.key &&
  submitted.revision == candidate.preparing.revision + 1L &&
  submitted.body == candidate.ready &&
  captured_task_publication_locator_matches(step, locator)
}

///|
fn[Store, E] captured_task_publication_locator_matches(
  step : LocalCapturedTaskPublicationStep[Store, E],
  locator : @host.ClientJournalPhysicalRow,
) -> Bool {
  let (key, body) = step.candidate.locator
  locator.key == key && locator.revision == 0L && locator.body == body
}

///|
/// Revalidate the still-current predecessor in the actual write transaction.
pub fn[Store, E] validate_local_captured_task_publication_binding(
  step : LocalCapturedTaskPublicationStep[Store, E],
  preparing : @host.ClientSavedSubmissionSnapshot,
  saved : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  validate_read()
  .bind(_ => captured_task_publication_current(step))
  .bind(_ => {
    @host.client_first_captured_task_saved_rows(
      preparing,
      saved,
      step.candidate.task_materials.plan,
      step.candidate,
      locator,
    ).map_err(_ => CustodyLost)
  })
  .bind(_ => validate_read())
}

///|
/// Confirm the actual successor and its unchanged companions in the original
/// adopted Store. Even a confirmed publication row grants no physical start.
pub fn[Store, E] confirm_local_captured_task_publication_binding(
  step : LocalCapturedTaskPublicationStep[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
  locator : @host.ClientJournalPhysicalRow,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
) -> Result[
  LocalCapturedTaskPublicationBinding[Store, E],
  LocalRunPublicationBindingIssue[E],
] {
  validate_read()
  .bind(_ => captured_task_publication_current(step))
  .bind(_ => {
    let (prior, body) = local_captured_task_publication_rows(step)
    guard run.key == prior.key &&
      run.revision == prior.revision + 1L &&
      run.body == body &&
      captured_task_publication_companions_match(step, submitted, locator) else {
      return Err(CustodyLost)
    }
    validate_read().map(_ => { step, })
  })
}
