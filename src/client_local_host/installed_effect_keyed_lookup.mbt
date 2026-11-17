///|
/// Borrow only this Run's opaque keyed binding. The Ledger and its identity
/// remain private to the existing Core owners; every protocol consumer still
/// checks this original's current census and exact request association.
pub fn installed_effect_keyed_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @publication_host.ClientEffectKeyedOriginal,
  ClientInstalledManagedRunIssue,
] {
  let plan = match
    installed_effect_managed_operation_plan(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard plan.model is None &&
    plan.keyed_original is Some(original) &&
    @publication_host.client_effect_keyed_original_current(original) else {
    return Err(ForeignOriginal)
  }
  Ok(original)
}

///|
/// Project the ValueBudget policy retained by this exact installed Effect
/// Plan. This is neither the Ledger planning-work budget nor compiler work;
/// the lookup's row admission and external dependency charges share it.
pub fn installed_effect_keyed_input_work_limit(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Int, ClientInstalledManagedRunIssue] {
  let (plan, _) = match
    require_installed_effect_operation_plan(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard plan.model is None &&
    plan.keyed_original is Some(original) &&
    @publication_host.client_effect_keyed_original_current(original) else {
    return Err(ForeignOriginal)
  }
  Ok(plan.capacity_plan.values.max_work)
}

///|
/// Borrow the already-started lookup only through its same managed parent.
/// This is an original-reference projection, not permission to start a read.
pub fn installed_effect_keyed_lookup_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[
  @publication_host.ClientKeyedLookupInput,
  ClientInstalledManagedRunIssue,
] {
  let plan = match
    installed_effect_managed_operation_plan(owner, prepared, owner.request) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard owner.ledger is Some(ledger) &&
    plan.model is None &&
    plan.keyed_original is Some(original) &&
    @publication_host.client_effect_keyed_lookup_matches_parent(
      lookup, original, ledger,
    ) else {
    return Err(ForeignOriginal)
  }
  Ok(lookup)
}

///|
/// Start the existing lookup from this Run's exact captured left. The actual
/// count grows the same original census before allocating response receivers;
/// it neither predicts unseen rows nor grants their read/Effect permission.
pub fn start_installed_effect_keyed_capture_input(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  keyed_plan : @publication_host.ClientEffectKeyedPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  captures : Array[@row_source_host.RowSourceCapture],
  max_entries : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_work : Int,
) -> Result[
  @publication_host.ClientKeyedLookupInput,
  ClientInstalledManagedRunIssue,
] {
  let plan = match
    installed_effect_managed_operation_plan(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let ledger = match require_installed_managed_run(owner) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard max_work > 0 &&
    max_work <= plan.capacity_plan.values.max_work &&
    plan.model is None &&
    plan.keyed_original is Some(original) &&
    plan.keyed_inventory is Some(inventory) &&
    !inventory.started &&
    @publication_host.client_effect_keyed_original_matches(
      original, prepared, compiled, definition, request, keyed_plan, keyed, ledger,
    ) &&
    owner.preparation_retirement is Some(EffectPlanPreparation(retirement)) &&
    retirement.holder is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, plan) &&
    captures.length() == plan.captures.length() &&
    plan.direct_occurrences is Some(direct) else {
    return Err(ForeignOriginal)
  }
  let mut left_rows = None
  for index, capture in captures {
    guard @row_source_host.row_capture_original_borrowed_requirement(
        capture, ledger,
      )
      is Some(requirement) &&
      physical_equal(requirement, plan.captures[index].requirement) else {
      return Err(ForeignOriginal)
    }
    // This existing captured-left profile borrows the actual first task,
    // not the keyed request's declaration ordinal or caller input order.
    if @publication_host.client_direct_acquisition_occurrence_at(direct, index)
      is Some((_, _, 0)) {
      guard left_rows is None &&
        @row_source_host.row_capture_source(capture) is Ok(source) &&
        @query.captured_source_row_count(source) is Some(count) &&
        count >= 0 else {
        return Err(ForeignOriginal)
      }
      left_rows = Some(count)
    }
  }
  guard left_rows is Some(rows) &&
    rows <= 2147483647 - inventory.reservations &&
    rows <= 2147483647 - inventory.holdings &&
    owner.preparation is Some(PlannedEffectManaged(_, after)) &&
    physical_equal(after, plan) &&
    plan.keyed_inventory is Some(current) &&
    physical_equal(current, inventory) &&
    !inventory.started &&
    @publication_host.client_effect_keyed_original_current(original) else {
    return Err(ForeignOriginal)
  }
  let reservations = inventory.reservations + rows
  let holdings = inventory.holdings + rows
  guard @resources.preparation_inventory_initial_control_slots(
      inventory.reservations,
      inventory.holdings,
      0,
    )
    is Some(before) &&
    @resources.preparation_inventory_initial_control_slots(
      reservations, holdings, 0,
    )
    is Some(after) &&
    @publication_host.client_effect_keyed_capture_start_construction_inventory(
      original,
    )
    is Some(start) &&
    @execution.preparation_array_representation(
      1L,
      captures.length().to_int64(),
      false,
    )
    is Some(vector) &&
    @execution.compose_preparation_representation([
      start,
      vector,
      {
        record_headers: after.0 - before.0 + 3L * captures.length().to_int64(),
        reference_slots: after.1 - before.1 + 3L * captures.length().to_int64(),
        scalar_words: after.2 - before.2 + captures.length().to_int64(),
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      // The Source-only Row receiver reuses the existing read record and
      // spent-request history fields. Its retained callback captures the
      // original parent/Plan/binding/request; no additional read field exists.
      {
        record_headers: 10L * rows.to_int64(),
        reference_slots: 19L * rows.to_int64(),
        scalar_words: 3L * rows.to_int64(),
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(units) &&
    @execution.preparation_representation_cost(units) is Some(bytes) else {
    return Err(InsufficientCapacity)
  }
  let (r, e) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(InsufficientCapacity)
  }
  // A refused or reentrant start cannot open a fresh assembly on retry.
  inventory.started = true
  match
    @resources.grow_preparation_body_inventory(
      holder,
      plan,
      inventory.identity,
      r,
      e,
      reservations,
      holdings,
      0,
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  inventory.reservations = reservations
  inventory.holdings = holdings
  guard owner.preparation is Some(PlannedEffectManaged(_, selected)) &&
    physical_equal(selected, plan) &&
    owner.ledger is Some(actual) &&
    physical_equal(actual, ledger) &&
    !@resources.preparation_body_retirement_started(holder) else {
    return Err(Retired)
  }
  let inputs = []
  for capture in captures {
    guard @row_source_host.row_capture_input(capture) is Some(input) else {
      return Err(ForeignOriginal)
    }
    inputs.push(input)
  }
  guard @publication_host.client_keyed_acquisition_coordinates(keyed)
    is Some((_, task, _)) &&
    task >= 0 &&
    task < plan.sequences.length() else {
    return Err(ForeignOriginal)
  }
  @publication_host.start_client_effect_keyed_capture_lookup_input(
    original,
    inputs,
    max_entries,
    max_name_bytes,
    max_bytes,
    max_work,
    source_sequence=Some(plan.sequences[task]),
    // Preserve this adapter's existing node ceiling independently of the
    // original ValueWork policy. A tighter work cap remains tighter here.
    max_nodes=Int::min(max_work, 1000000),
  ).map_err(_ => ForeignOriginal)
}
