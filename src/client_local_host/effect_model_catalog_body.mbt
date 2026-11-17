///|
fn reserve_effect_unit_catalog_controls(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  holder : @resources.PreparationBodyBorrow[ClientInstalledEffectManagedPlan],
  parts : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) &&
    effect_unit_catalog_selection_capacity(parts) is Some(controls) &&
    @resources.preparation_body_borrow_reserved_extents(holder)
    is Ok((base_r, base_e)) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_retained_bytes(controls),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base_r,
      @execution.execution_capacity_execution_bytes(controls),
      1L,
    )
    is Some(e) else {
    return Err(ForeignOriginal)
  }
  match
    @resources.reserve_preparation_publication_phase(
      holder,
      plan,
      r,
      Int64::max(base_e, e),
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Retired)
  }
  Ok(())
}

///|
/// SAME Model holder, checked Program and original ledger. This is a private
/// DATA selector: Source/Model/Effect authorization stays at its outer use.
fn prepare_effect_model_catalog_body(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  program : @checked.CheckedProgram,
  unit : Int,
  role : String,
  cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@checked.CheckedLocalDependencyBody, Int),
  ClientEffectUnitPreparationIssue,
] {
  let holder = match effect_unit_publication_body(value, plan, request) {
    Err(issue) => return Err(Run(issue))
    Ok(value) => value
  }
  guard plan.model is Some(_) &&
    value.ledger is Some(ledger) &&
    physical_equal(
      program,
      @checked.effect_program_static_checked_computation(
        @publication_host.prepared_client_effect_computation_candidate(
          plan.prepared,
        ),
      ),
    ) else {
    return Err(Run(ForeignOriginal))
  }
  // Back O(1) cursor/member/decode wrappers before selecting any Catalog body.
  match reserve_effect_unit_catalog_controls(value, plan, request, holder, 0) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let selected = match
    @checked.begin_checked_local_catalog_selection(program, unit, role, cid) {
    Err(issue) => return Err(Evidence(Dependency(issue)))
    Ok(value) => value
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  while @checked.checked_local_catalog_selection_remaining(selected) > 0 {
    let visits = Int::min(
      256,
      @checked.checked_local_catalog_selection_remaining(selected),
    )
    // The same finite planning policy pays the next actual lookup chunk before
    // its walk. Failure consumes the paid chunk; it never creates extra credit.
    match @resources.charge_planning(ledger, visits) {
      Err(issue) => return Err(Run(Ledger(issue)))
      Ok(_) => ()
    }
    guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
      physical_equal(actual, holder) else {
      return Err(Run(Retired))
    }
    match
      @checked.advance_checked_local_catalog_selection(
        selected,
        visits,
        work=Some(units => {
          match @resources.charge_planning(ledger, units) {
            Ok(_) => true
            Err(issue) => {
              refused.val = Some(issue)
              false
            }
          }
        }),
      ) {
      Err(issue) =>
        return match refused.val {
          Some(primary) => Err(Run(Ledger(primary)))
          None => Err(Evidence(Dependency(issue)))
        }
      Ok(_) => ()
    }
  }
  guard @checked.checked_local_catalog_selection_geometry(selected)
    is Some((bytes, nodes, depth)) else {
    return Err(Evidence(Dependency(MissingDependency)))
  }
  match
    reserve_effect_unit_catalog_body(
      value, plan, request, holder, bytes, nodes, depth,
    ) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let body = match
    @checked.finish_checked_local_catalog_selection(
      selected, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(Evidence(Dependency(issue)))
    Ok(value) => value
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Run(Retired))
  }
  Ok((body, bytes))
}

///|
// The existing before_body recipe, now shared by the managed selector. Exact
// cached member geometry funds wire plus writer before the SAME emitter.
fn reserve_effect_unit_catalog_body(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  holder : @resources.PreparationBodyBorrow[ClientInstalledEffectManagedPlan],
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) &&
    @resources.preparation_body_borrow_reserved_extents(holder) is Ok((r, e)) else {
    return Err(ForeignOriginal)
  }
  guard @execution.preparation_execution_capacity({
      retained: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: bytes.to_int64(),
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: bytes.to_int64(),
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(capacity) &&
    @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_retained_bytes(capacity),
      1L,
    )
    is Some(next_r) &&
    @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_execution_bytes(capacity),
      1L,
    )
    is Some(next_e) else {
    return Err(InsufficientCapacity)
  }
  match
    @resources.reserve_preparation_publication_phase(
      holder,
      plan,
      next_r,
      Int64::max(e, next_e),
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  guard effect_unit_publication_body(value, plan, request) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(Retired)
  }
  Ok(())
}
