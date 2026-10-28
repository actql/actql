///|
/// Fixed live observer packet only. The caller funds this before inspecting
/// original typed dimensions. Quotation helpers/Result controls are separate.
pub fn capacity_input_construction_observation_inventory() -> @shape.CollectionConstructionInventory {
  capacity_input_observer_controls
}

///|
// Original observer controls plus its actual work Ref and returned tuple.
let capacity_input_observer_controls : @shape.CollectionConstructionInventory = {
  records: 14L,
  record_references: 9L,
  record_words: 34L,
  reference_arrays: 0L,
  reference_items: 0L,
  scalar_arrays: 0L,
  scalar_items: 0L,
  maps: 0L,
  map_entries: 0L,
}

///|
/// Construction counts of the ORIGINAL bind_capacity_inputs. No Source wire,
/// row, parameter or proof body is parsed/hashed here. Admitted HostSources,
/// claims, CIDs and original Program/Environment backing remain borrowed.
/// Unknown/duplicate Stages still receive the original binder's typed refusal.
/// At most min(Stage count,entry count) definitions can pass unique selection;
/// later entries cannot construct consumers. Per-entry limit Maps/ordinal
/// closures never escape: only their maximum overlaps all retained consumers.
/// All returned counts are DATA, not a semantic verdict or capacity grant.
pub fn capacity_input_construction_inventory(
  program : @syntax.Program,
  entries : Array[StageCapacityInput],
) -> @shape.CollectionConstructionInventory? {
  observe_capacity_input_construction_inventory(program, entries).0
}

///|
/// Original dimension-observer visits, not checker work, invocations or CPU.
/// Two original observations can share one receipt around an external current
/// callback; a failed grow does not cause either observation to be repeated.
pub fn observe_capacity_input_construction_inventory(
  program : @syntax.Program,
  entries : Array[StageCapacityInput],
) -> (@shape.CollectionConstructionInventory?, Int64) {
  let work = Ref(1L)
  let result = capacity_input_construction_inventory_owned(
    program, entries, work,
  )
  (result, work.val)
}

///|
fn capacity_input_construction_inventory_owned(
  program : @syntax.Program,
  entries : Array[StageCapacityInput],
  work : Ref[Int64],
) -> @shape.CollectionConstructionInventory? {
  let stages = @syntax.stage_count(program).to_int64()
  let selected = Int::min(@syntax.stage_count(program), entries.length())
  let mut uses = 0L
  let mut largest_limits = 0L
  for index in 0..<selected {
    work.val += 1L
    let entry = entries[index]
    guard @counts.checked_nonnegative_add_product(
        uses,
        entry.uses.length().to_int64(),
        1L,
      )
      is Some(total) else {
      return None
    }
    uses = total
    let mixed = @wire.program_claim_mixed(@host.source_claims(entry.sources))
    let limits = match mixed {
      Some(value) => @wire.mixed_limit_count(value).to_int64()
      None => 0L
    }
    largest_limits = Int64::max(largest_limits, limits)
  }
  let selected = selected.to_int64()
  guard @counts.checked_nonnegative_add_product(0L, selected, 1L) is Some(h) &&
    @counts.checked_nonnegative_add_product(h, largest_limits, 1L) is Some(h) &&
    @counts.checked_nonnegative_add_product(h, uses, 1L) is Some(h) &&
    @counts.checked_nonnegative_add_product(0L, selected, 2L) is Some(r) &&
    @counts.checked_nonnegative_add_product(r, largest_limits, 1L) is Some(r) &&
    @counts.checked_nonnegative_add_product(largest_limits, uses, 4L) is Some(w) &&
    @counts.checked_nonnegative_add_product(0L, stages, 2L) is Some(items) &&
    @counts.checked_nonnegative_add_product(items, uses, 1L) is Some(items) &&
    @counts.checked_nonnegative_add_product(stages, selected, 1L)
    is Some(map_entries) &&
    @counts.checked_nonnegative_add_product(map_entries, largest_limits, 1L)
    is Some(map_entries) else {
    return None
  }
  @shape.compose_collection_construction_inventories([
    @host.empty_host_sources_construction_inventory(),
    capacity_input_binding_fixed_inventory,
    {
      records: h,
      record_references: r,
      record_words: w,
      // Stage copy, material slots, and one escaping consumer array/definition.
      reference_arrays: 2L + selected,
      reference_items: items,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L + (if selected > 0L { 1L } else { 0L }),
      map_entries,
    },
  ])
}

///|
// Default factory's four literal argument arrays and empty consumers; three
// Limits, material, Budget, result owner/Result and observation tuple:8H6R15W.
// Fixed read/control majorant22H25R32W: object/array length options; one field
// Cursor/tuple/option; selected-name and ordinal Map lookups; one mixed limit
// option, ordinal closure and step/consumer tuple; first typed failure path.
// These transient slots are replaced per iteration, not multiplied by rows.
let capacity_input_binding_fixed_inventory : @shape.CollectionConstructionInventory = {
  records: 8L + 22L,
  record_references: 6L + 25L,
  record_words: 15L + 32L,
  reference_arrays: 5L,
  reference_items: 0L,
  scalar_arrays: 0L,
  scalar_items: 0L,
  maps: 0L,
  map_entries: 0L,
}
