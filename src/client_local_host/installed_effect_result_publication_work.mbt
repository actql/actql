///|
pub(all) enum ClientInstalledEffectResultPublicationIssue {
  Operation(ClientInstalledManagedRunIssue)
  Transform(@publication_host.CapturedClientResultTransformationIssue)
}

///|
// The shared receipt is already prepaid by Result work or authenticated Read
// recovery before the later pin census. No replacement work allowance exists.
fn installed_effect_publication_work_receipt_bytes() -> Int64? {
  let phase = @resources.preparation_phase_work_continuation64_construction_inventory()
  @execution.preparation_representation_cost({
    record_headers: phase.record_headers,
    reference_slots: phase.reference_slots,
    scalar_words: phase.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
fn installed_effect_result_publication_work_capacity() -> @execution.ExecutionCapacity? {
  guard installed_effect_publication_work_receipt_bytes() is Some(receipt) &&
    @execution.preparation_execution_capacity({
      retained: {
        // The fixed Node progress closure holds only this original tuple and
        // methods, one Run, and its two synchronous busy/failure observations.
        record_headers: 1L,
        reference_slots: 11L,
        scalar_words: 2L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      workspace: {
        // Existing Resource view9H/17R/17W; closed caller's original/live/task
        // closures3H/8R/1W, original control Some1H/1R; progress/return and
        // remaining-work Result carriers7H/4R/7W. No row/index storage here.
        // The actual Node call additionally coholds its seven-argument
        // Array/backing2H/2R/7W; no new result DTO or source-body copy.
        record_headers: 22L,
        reference_slots: 32L,
        scalar_words: 32L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: receipt,
      workspace_bytes: 0L,
    })
    is Some(capacity) else {
    return None
  }
  Some(capacity)
}

///|
/// Initialize the same Effect publication continuation BEFORE the first Result
/// view. The later dependency pin/export/capture reuses this exact receipt.
/// The original preparation/Plan/Run and finite policy remain authoritative.
pub fn prepare_installed_effect_result_publication_work(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  run : @strategy.CapturedEffectRunDAG,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    owner.source_free_captured is Some(captured) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    !@strategy.captured_effect_run_matches_preparation(
      run,
      captured,
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      ),
    ) {
    return Err(ForeignOriginal)
  }
  if control.dependency_work is Some(_) ||
    control.dependency_started ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) {
    return Err(AlreadyBound)
  }
  guard installed_effect_result_publication_work_capacity() is Some(capacity) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, capacity,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  begin_installed_effect_dependency_work(admission, plan, ledger, control)
}

///|
/// One synchronous Result poll under the SAME Effect work continuation. Grant
/// no more than its remaining amount, debit failed progress before examining
/// its issue, and return the original work view before any await or cleanup.
pub fn advance_installed_effect_result_publication(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  run : @strategy.CapturedEffectRunDAG,
  transformation : @publication_host.CapturedClientResultTransformation,
  quantum : Int,
) -> Result[(Bool, Int), ClientInstalledEffectResultPublicationIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(Operation(ForeignOriginal))
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(Operation(AlreadyBound))
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard quantum > 0 &&
    owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    physical_equal(plan, expected_plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_work is Some(receipt) &&
    !control.dependency_started &&
    !control.construction_active &&
    !control.ledger_codec_active &&
    control.constructor_frame is None &&
    owner.source_free_captured is Some(captured) else {
    return Err(Operation(ForeignOriginal))
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(Operation(issue))
    Ok(_) => ()
  }
  if !@strategy.captured_effect_run_matches_preparation(
      run,
      captured,
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      ),
    ) ||
    !@publication_host.captured_client_result_transformation_matches_run(
      transformation,
      @strategy.captured_effect_run_dag(run),
    ) {
    return Err(Operation(ForeignOriginal))
  }
  let progress = match
    with_installed_effect_dependency_work(
      control,
      admission,
      plan,
      ledger,
      () => {
        check_installed_effect_operation_original(
          owner,
          ledger,
          preparation,
          Some(control),
        )
      },
      control.reservation,
      () => {
        owner.effect_operation_opening &&
        !owner.effect_operation_closing &&
        @publication_host.captured_client_result_transformation_retained(
          transformation,
        )
      },
      spend => {
        let remaining = match
          @resources.remaining_preparation_phase_work_continuation64(receipt) {
          Ok(value) if value > 0L => value
          _ =>
            return Err(
              @resources.NodeManagedRunOperationIssue::Control(PlanningLimit),
            )
        }
        let granted = Int64::min(quantum.to_int64(), remaining).to_int()
        let (ready, work, issue) = transformation.advance_progress(granted)
        if work < 0 || work > granted {
          return Err(
            @resources.NodeManagedRunOperationIssue::Control(InvalidCharge),
          )
        }
        match spend(work) {
          Err(issue) =>
            return Err(@resources.NodeManagedRunOperationIssue::Control(issue))
          Ok(_) => ()
        }
        Ok((ready, work, issue))
      },
    ).map_err(installed_effect_operation_reservation_issue) {
    Err(issue) => return Err(Operation(issue))
    Ok(value) => value
  }
  match progress {
    (_, _, Some(issue)) => Err(Transform(issue))
    (ready, work, None) => Ok((ready, work))
  }
}
