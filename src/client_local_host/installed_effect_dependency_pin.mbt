///|
// Managed-only bridge before pin/selection construction. The public legacy
// pin port and its explicit ceilings are unchanged. This creates no grant,
// read permission, execution, physical-owner sharing or replacement Ledger.
pub fn pin_installed_effect_sources(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  run : @strategy.CapturedEffectRunDAG,
  configured_max_pins : Int,
) -> Result[@strategy.CapturedEffectInputs, ClientInstalledManagedRunIssue] {
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
    control.dependency_started ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    !@strategy.captured_effect_run_matches_preparation(
      run,
      captured,
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      ),
    ) {
    return Err(ForeignOriginal)
  }
  let units = @strategy.captured_effect_dependency_unit_count(run)
  // Existing per-graph work/depth and explicit pin policy remain independent
  // of body entry count or wire bytes. No bytes-as-count credit is introduced.
  if units < 0 || units > 65536 || configured_max_pins < 0 {
    return Err(Unsupported)
  }
  guard installed_effect_dependency_fixed_capacity(0, units, 64) is Some(fixed) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, fixed,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  control.dependency_started = true
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let census = match
    @resources.with_prepared_run_operation_control_work(
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
        physical_equal(@strategy.captured_effect_run_dag(run), captured)
      },
      spend => {
        match
          @strategy.census_captured_effect_dependency_ports(run, 65536, 64, units => {
            match spend(units) {
              Ok(_) => true
              Err(issue) => {
                refused.val = Some(issue)
                false
              }
            }
          }) {
          Ok(value) => Ok(value)
          Err(_) =>
            Err(@resources.NodeManagedRunOperationIssue::Original(Unsupported))
        }
      },
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match refused.val {
          Some(issue) => Ledger(issue)
          None => installed_effect_operation_reservation_issue(issue)
        },
      )
  }
  let (observed_units, results, members, tables, names) = @strategy.captured_effect_dependency_port_census_geometry(
    census,
  )
  if observed_units != units {
    return Err(ForeignOriginal)
  }
  guard installed_effect_dependency_index_capacity(
      results,
      members,
      names~,
      tables~,
    )
    is Some(inventory) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, inventory,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // All actual request/map/key/borrow construction is finite. Debit its
  // observed coordinate/name spans before any String concat/hash or pin. The
  // synchronous view ends before original availability/retention callbacks.
  let work = 2L * units.to_int64() +
    32L * (results.to_int64() + members.to_int64() + tables.to_int64()) +
    4L * (names + 11L * (results.to_int64() + members.to_int64()))
  if work > 2147483647L {
    return Err(InsufficientCapacity)
  }
  match
    @resources.with_prepared_run_operation_control_work(
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
      () => owner.effect_operation_opening && !owner.effect_operation_closing,
      spend => {
        spend(work.to_int()).map_err(
          issue => @resources.NodeManagedRunOperationIssue::Control(issue),
        )
      },
    ).map_err(installed_effect_operation_reservation_issue) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let inputs = match
    @strategy.pin_censused_captured_effect_sources(
      census,
      Some(configured_max_pins),
    ) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  // Before any later current/error can reject, retain this SAME custody for
  // parent quiescence. Node owns normal release after a successful return.
  control.dependency_inputs = Some(inputs)
  match
    check_installed_effect_operation_original(
      owner,
      ledger,
      preparation,
      Some(control),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !@strategy.captured_effect_inputs_match_captured_run(inputs, captured) ||
    !@strategy.captured_effect_inputs_retained(inputs) {
    return Err(ForeignOriginal)
  }
  Ok(inputs)
}
