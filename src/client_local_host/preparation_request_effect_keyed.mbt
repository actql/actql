///|
// Mutable census extents on the same existing preparation body. This retains
// the issued identity, never a replacement reservation, Root or permission.
priv struct ClientInstalledEffectKeyedInventory {
  identity : @resources.OriginalLedgerIdentity
  mut reservations : Int
  mut holdings : Int
  mut operation_children : Int
  mut started : Bool
}

///|
/// Bind the actual Source-only keyed component while the SAME Request still
/// owns its preparation census. The later installed Run borrows this opaque
/// binding, never a JS Ledger, Model scope, reconstructed identity or new Run.
pub fn[I] prepare_request_effect_keyed_original(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledEffectManagedPlan,
  compilation : @publication_host.ClientEffectCompilation,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  keyed_plan : @publication_host.ClientEffectKeyedPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.phase == EffectPlanReserved &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) &&
    physical_equal(plan.prepared, prepared) &&
    plan.model is None &&
    plan.keyed_original is None &&
    plan.keyed_inventory is None &&
    owner.program_domain_compilation_inputs
    is Some(RequestEffectKeyedGraph(p, k, c, g)) &&
    physical_equal(p, prepared) &&
    physical_equal(k, keyed) &&
    physical_equal(c, plan.installed_contracts) &&
    physical_equal(g, keyed_plan) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    (
      owner.effect_plan is None ||
      (owner.effect_plan is Some(original) && physical_equal(original, plan))
    ) else {
    return Err(ForeignOriginal)
  }
  // The same checked Plan supplies the fixed capture/task/operation census.
  // Actual keyed-response population is added only after its original left
  // capture exists; no parser byte ceiling is treated as allocated rows.
  guard installed_effect_keyed_base_inventory(plan) is Some((rslots, hslots)) else {
    return Err(InsufficientCapacity)
  }
  let selected = match
    @resources.preparation_inventory_initial_control_slots(rslots, hslots, 0) {
    None => return Err(InsufficientCapacity)
    Some(value) => value
  }
  let initial = request_preparation_inventory_slots
  let original = @publication_host.client_effect_keyed_original_construction_inventory()
  let growth = @resources.preparation_inventory_growth_entry_construction()
  // The Plan's optional reference keeps the checked binding through failed
  // completion/adoption. The Plan field itself is funded before construction.
  let bytes = match
    @execution.preparation_representation_cost({
      // Keep one synchronous growth entry and its own extent/slot/cost
      // observation carriers funded before any later actual child allocation.
      record_headers: original.record_headers +
      3L +
      selected.0 -
      initial.0 +
      growth.record_headers +
      8L,
      reference_slots: original.reference_slots +
      3L +
      selected.1 -
      initial.1 +
      growth.reference_slots +
      3L,
      scalar_words: original.scalar_words +
      6L +
      selected.2 -
      initial.2 +
      growth.scalar_words +
      17L,
      owned_utf16_units: original.owned_utf16_units,
      owned_wire_bytes: original.owned_wire_bytes,
    }) {
    None => return Err(InsufficientCapacity)
    Some(value) => value
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  // The earlier compiled getter has returned. Its actual validation chain
  // (candidate H1R3, DAG H1R2, prepared Run H1R3, two Results H2R2W2)
  // no longer coexists with this binder. Keep the compiled holder/Effects
  // 2H10R1W; reuse the 5H10R2W scratch rather than retaining it permanently.
  guard @execution.preparation_representation_cost({
      record_headers: 5L,
      reference_slots: 10L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(returned_scratch) &&
    r >= returned_scratch &&
    e >= returned_scratch &&
    @execution.checked_preparation_add_product(r - returned_scratch, bytes, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(e - returned_scratch, bytes, 1L)
    is Some(next_e) else {
    return Err(InsufficientCapacity)
  }
  let e = if next_e > e { next_e } else { e }
  owner.effect_plan = Some(plan)
  owner.phase = Selecting
  let result : Result[Unit, ClientInstalledManagedRunIssue] = match
    @resources.grow_preparation_capacity_inventory(
      capacity, input, r, e, rslots, hslots, 0,
    ) {
    Err(issue) => Err(Preparation(issue))
    Ok(_) => {
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.effect_capacity is Some(original) &&
        physical_equal(original, capacity) &&
        owner.effect_plan is Some(original) &&
        physical_equal(original, plan) &&
        plan.keyed_original is None else {
        if owner.phase == Selecting {
          owner.phase = EffectBodyFailed
        }
        return Err(ForeignOriginal)
      }
      match
        @resources.preparation_capacity_inventory_original(capacity, input) {
        Err(issue) => Err(Preparation(issue))
        Ok(identity) =>
          match
            @publication_host.bind_client_effect_keyed_original(
              prepared,
              compilation,
              compiled,
              definition,
              plan.request,
              keyed_plan,
              keyed,
              owner.ledger,
              identity,
            ) {
            Err(_) => Err(ForeignOriginal)
            Ok(original) => {
              plan.keyed_original = Some(original)
              plan.keyed_inventory = Some({
                identity,
                reservations: rslots,
                holdings: hslots,
                operation_children: 0,
                started: false,
              })
              Ok(())
            }
          }
      }
    }
  }
  owner.phase = if result is Ok(_) {
    EffectPlanReserved
  } else {
    EffectBodyFailed
  }
  result
}

///|
// Two borrowed optional-field slots in the existing Plan, present even when
// unselected. No Source binding or payload is created by this fixed quote.
fn installed_effect_keyed_plan_field_bytes() -> Int64 {
  @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 2L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
// Fixed coexistence inventory from this actual selected Plan. The input/body
// borrowers, Source/task children and operation controls remain independent
// original obligations; two slots cover the lookup assembly and its receiver.
fn installed_effect_keyed_base_inventory(
  plan : ClientInstalledEffectManagedPlan,
) -> (Int, Int)? {
  // held_children is a checked operation-coordinate CEILING, not allocated token
  // Map storage. Actual operation entries grow this same inventory below.
  let children = plan.captures.length().to_int64() +
    @strategy.graph_task_count(plan.graph).to_int64() +
    2L
  if children < 0L ||
    children > 2147483647L - request_preparation_borrow_limit.to_int64() {
    return None
  }
  Some(
    (request_preparation_borrow_limit + children.to_int(), children.to_int()),
  )
}

///|
// Called after the exact operation coordinate/current checks and BEFORE its
// Resource/control entry is constructed. Every spent occurrence stays in the
// original Run vector; no closed token returns work or permits replay.
fn grow_installed_effect_keyed_operation_inventory(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let inventory = match plan.keyed_inventory {
    None => return Ok(())
    Some(value) => value
  }
  let count = owner.effect_operations.length()
  if count >= plan.held_children || count == 2147483647 {
    return Err(InsufficientCapacity)
  }
  let needed = count + 1
  if needed <= inventory.operation_children {
    return Ok(())
  }
  let extra = needed - inventory.operation_children
  guard inventory.reservations <= 2147483647 - extra &&
    inventory.holdings <= 2147483647 - extra &&
    owner.preparation is Some(PlannedEffectManaged(_, selected)) &&
    physical_equal(selected, plan) &&
    owner.preparation_retirement is Some(EffectPlanPreparation(retirement)) &&
    retirement.holder is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, plan) else {
    return Err(ForeignOriginal)
  }
  let reservations = inventory.reservations + extra
  let holdings = inventory.holdings + extra
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
    @execution.preparation_representation_cost({
      record_headers: after.0 - before.0,
      reference_slots: after.1 - before.1,
      scalar_words: after.2 - before.2,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
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
  guard owner.preparation is Some(PlannedEffectManaged(_, current)) &&
    physical_equal(current, plan) &&
    plan.keyed_inventory is Some(current_inventory) &&
    physical_equal(current_inventory, inventory) &&
    !@resources.preparation_body_retirement_started(holder) else {
    return Err(Retired)
  }
  inventory.reservations = reservations
  inventory.holdings = holdings
  inventory.operation_children = needed
  Ok(())
}
