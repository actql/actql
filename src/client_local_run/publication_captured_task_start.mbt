///|
/// One exact dispatch reservation or physical-start claim for the same File
/// Run. The expected predecessor body is already retained by its issuer.
pub struct LocalCapturedTaskStartStep[Store, E] {
  publication : LocalCapturedTaskPublicationBinding[Store, E]
  dispatch : Bool
  expected : @host.ClientJournalPhysicalRow
  body : Bytes
}

///|
/// The actual retained successor from a fresh same-Store read. This fact
/// alone does not invoke Source or count as a physical start acknowledgement.
pub struct LocalCapturedTaskStartObservation[Store, E] {
  step : LocalCapturedTaskStartStep[Store, E]
}

///|
fn[Store, E] captured_task_activation_current(
  publication : LocalCapturedTaskPublicationBinding[Store, E],
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  let step = publication.step
  let original = step.candidate.task_materials.plan
  let admission = @host.client_compiled_run_admission(original.compiled)
  validate_read()
  .bind(_ => captured_task_publication_current(step))
  .bind(_ => {
    guard account.account_id() == step.account_id &&
      @publication.run_publication_execution_context(admission) == context &&
      @authorization.bind_dispatch_authorization(
        account,
        step.tuple,
        @authorization.Activation,
        @host.client_request_program_cid(original.request),
        context,
      )
      is Ok(_) else {
      return Err(AuthorizationMismatch)
    }
    validate_read()
  })
}

///|
fn captured_task_same_physical_row(
  row : @host.ClientJournalPhysicalRow,
  exact : @host.ClientJournalPhysicalRow,
) -> Bool {
  row.key == exact.key &&
  row.revision == exact.revision &&
  row.body == exact.body
}

///|
/// Use the same Common reservation decisions after observing the exact
/// publication or confirmed dispatch reservation. The caller funds decoding
/// and encoding in its original Read before constructing any new bytes.
pub fn[Store, E] prepare_local_captured_task_start_step(
  publication : LocalCapturedTaskPublicationBinding[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
  fund_decode : (@host.ClientRunJournalConstruction) -> Result[
    Unit,
    @host.ClientJournalDecodingIssue,
  ],
  fund_encode : (Int, Int, Int) -> Result[
    Unit,
    @host.ClientJournalEncodingIssue,
  ],
  dispatch? : LocalCapturedTaskStartObservation[Store, E]? = None,
) -> Result[
  LocalCapturedTaskStartStep[Store, E],
  LocalRunPublicationBindingIssue[E],
] {
  let binding = publication.step
  let original = binding.candidate.task_materials.plan
  let expected : @host.ClientJournalPhysicalRow = match dispatch {
    None => {
      let (prior, body) = local_captured_task_publication_rows(binding)
      { key: prior.key, revision: prior.revision + 1L, body, }
    }
    Some(confirmed) => {
      guard confirmed.step.dispatch &&
        physical_equal(confirmed.step.publication, publication) else {
        return Err(CustodyLost)
      }
      local_captured_task_start_successor(confirmed.step)
    }
  }
  fn current() -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
    captured_task_activation_current(
      publication, account, context, validate_read,
    )
  }
  current().bind(_ => {
    guard captured_task_same_physical_row(run, expected) &&
      captured_task_publication_companions_match(binding, submitted, locator) else {
      return Err(CustodyLost)
    }
    let (record, finite_policy, observations) = match
      @host.decode_client_run_journal_row_with_retained_identity(
        run.body,
        original.request,
        original.definition,
        before_construction=Some(fund_decode),
      ) {
      Ok(decoded) => decoded
      Err(_) => return Err(CustodyLost)
    }
    guard record.publication_binding is Some(_) &&
      record.task_materials_cid == Some(binding.candidate.task_materials.cid) &&
      record.publication_policy_originals ==
      Some(binding.candidate.task_materials.publication_policy_originals) &&
      finite_policy is Some(_) &&
      observations is Some(_) &&
      record.checkpoint is None &&
      record.effect_material_originals is None &&
      !record.cancellation_requested() &&
      !record.physical_start_claimed else {
      return Err(CustodyLost)
    }
    let definition = @publication.publication_contract_identity(
      original.definition,
    )
    match current() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let changed = if dispatch is None {
      guard @host.prepare_client_run_start(
          original.request,
          record.request,
          record.definition,
          definition,
          record.dispatch_reserved,
          true,
        )
        is Ok(@host.ReserveDispatch) else {
        return Err(CustodyLost)
      }
      { ..record, dispatch_reserved: true, }
    } else {
      guard @host.prepare_client_run_physical_start(
          original.request,
          record.request,
          record.definition,
          definition,
          record.dispatch_reserved,
          !record.physical_start_claimed,
          true,
          cancellation_requested=record.cancellation_requested(),
        )
        is Ok(true) else {
        return Err(CustodyLost)
      }
      { ..record, physical_start_claimed: true, }
    }
    @host.client_run_journal_row_body(
      changed,
      local_run_policy_originals=finite_policy,
      run_observation_originals=observations,
      before_construction=Some(fund_encode),
    )
    .map_err(issue => LocalRunPublicationBindingIssue::Encoding(issue))
    .bind(body => {
      current().map(_ => {
        publication,
        dispatch: dispatch is None,
        expected,
        body,
      })
    })
  })
}

///|
pub fn[Store, E] local_captured_task_start_rows(
  step : LocalCapturedTaskStartStep[Store, E],
) -> (@host.ClientJournalPhysicalRow, Bytes) {
  (step.expected, step.body)
}

///|
pub fn[Store, E] local_captured_task_start_successor(
  step : LocalCapturedTaskStartStep[Store, E],
) -> @host.ClientJournalPhysicalRow {
  {
    key: step.expected.key,
    revision: step.expected.revision + 1L,
    body: step.body,
  }
}

///|
/// Check the exact predecessor again in the write transaction.
pub fn[Store, E] validate_local_captured_task_start_step(
  step : LocalCapturedTaskStartStep[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  captured_task_activation_current(
    step.publication,
    account,
    context,
    validate_read,
  ).bind(_ => {
    if captured_task_same_physical_row(run, step.expected) &&
      captured_task_publication_companions_match(
        step.publication.step,
        submitted,
        locator,
      ) {
      validate_read()
    } else {
      Err(CustodyLost)
    }
  })
}

///|
/// Adopt only the exact successor and unchanged companions in the same
/// Store. A candidate, a failed write and a returned CAS ACK cannot enter it.
pub fn[Store, E] confirm_local_captured_task_start_step(
  step : LocalCapturedTaskStartStep[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
) -> Result[
  LocalCapturedTaskStartObservation[Store, E],
  LocalRunPublicationBindingIssue[E],
] {
  check_local_captured_task_start_successor(
    step, run, submitted, locator, account, context, validate_read,
  ).map(_ => { step, })
}

///|
fn[Store, E] check_local_captured_task_start_successor(
  step : LocalCapturedTaskStartStep[Store, E],
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  captured_task_activation_current(
    step.publication,
    account,
    context,
    validate_read,
  ).bind(_ => {
    if captured_task_same_physical_row(
        run,
        local_captured_task_start_successor(step),
      ) &&
      captured_task_publication_companions_match(
        step.publication.step,
        submitted,
        locator,
      ) {
      validate_read()
    } else {
      Err(CustodyLost)
    }
  })
}

///|
/// After the File state CAS, only the original Submission row may have
/// changed. The existing start and locator originals still bind the Read.
fn[Store, E] check_local_captured_task_saved_state_successor(
  step : LocalCapturedTaskStartStep[Store, E],
  run : @host.ClientJournalPhysicalRow,
  snapshot : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  account : @authorization.AdmittedAccountConfiguration,
  context : String,
  validate_read : () -> Result[Unit, LocalRunPublicationBindingIssue[E]],
  update : @host.ClientSavedRunStateUpdate,
) -> Result[Unit, LocalRunPublicationBindingIssue[E]] {
  let binding = step.publication.step
  let original = binding.candidate
  captured_task_activation_current(
    step.publication,
    account,
    context,
    validate_read,
  ).bind(_ => {
    let predecessor : @host.ClientJournalPhysicalRow = {
      key: original.preparing.key,
      revision: original.preparing.revision + 1L,
      body: original.ready,
    }
    guard captured_task_same_physical_row(
        run,
        local_captured_task_start_successor(step),
      ) &&
      captured_task_publication_locator_matches(binding, locator) &&
      @host.validate_client_saved_run_state_update_predecessor(
        update, predecessor,
      )
      is Ok(_) &&
      @host.confirm_client_saved_run_state_update(update, snapshot) is Ok(_) else {
      return Err(CustodyLost)
    }
    validate_read()
  })
}

///|
/// Borrow the finite policy encoded in the first Run row and carried unchanged
/// through the observed publication binding, reservation and physical start.
/// A caller must still re-observe the same Store and authorize publication.
pub fn[Store, E] local_captured_task_start_finite_policy(
  observed : LocalCapturedTaskStartObservation[Store, E],
  candidate : @host.ClientCapturedTaskFirstRunRows,
) -> @host.ClientLocalRunPolicyOriginal? {
  let step = observed.step
  if step.dispatch ||
    !physical_equal(step.publication.step.candidate, candidate) {
    return None
  }
  Some(candidate.finite_policy)
}
