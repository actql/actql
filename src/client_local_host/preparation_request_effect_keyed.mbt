///|
// Mutable census extents on the same existing preparation body. This retains
// the issued identity, never a replacement reservation, Root or permission.
priv struct ClientInstalledEffectKeyedInventory {
  identity : @resources.OriginalLedgerIdentity
  mut reservations : Int
  mut holdings : Int
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
  // The Plan's optional reference keeps the checked binding through failed
  // completion/adoption. The Plan field itself is funded before construction.
  let bytes = match
    @execution.preparation_representation_cost({
      record_headers: original.record_headers + 3L + selected.0 - initial.0,
      reference_slots: original.reference_slots + 3L + selected.1 - initial.1,
      scalar_words: original.scalar_words + 5L + selected.2 - initial.2,
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
  let children = plan.held_children.to_int64() +
    plan.captures.length().to_int64() +
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
