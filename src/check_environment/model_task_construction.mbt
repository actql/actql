///|
/// The actual empty ModelTask registry still owns its entries and selector
/// containers. This recipe deliberately does not describe populated ModelTask
/// grammar, schemas, hashing, generation or data-handling construction.
pub fn empty_model_tasks_construction_extent(
  original : WireEnvironment,
) -> RegistryConstructionExtent? {
  if member_count(original, ModelTaskContracts) != 0 {
    return None
  }
  let retained = empty_model_tasks_retained_units()
  // Original budget, outer/body/contract limits, successful Result and typed
  // refusal alternatives. The WireEnvironment is borrowed, never copied.
  Some({
    record_headers: retained.record_headers + 7L,
    reference_slots: retained.reference_slots + 5L,
    scalar_words: retained.scalar_words + 15L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
pub fn empty_model_tasks_retained_extent(
  original : WireEnvironment,
) -> RegistryConstructionExtent? {
  if member_count(original, ModelTaskContracts) != 0 {
    return None
  }
  Some(wire_admission_units(empty_model_tasks_retained_units()))
}

///|
fn empty_model_tasks_retained_units() -> @shape.CollectionConstructionExtent {
  // ModelTasks(environment, entries, selectors; bytes/nodes/work and both
  // contract counters), original empty entries Array and original empty Map.
  @shape.collection_construction_extent({
    records: 1L,
    record_references: 3L,
    record_words: 5L,
    reference_arrays: 1L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: 0L,
  }).unwrap()
}

///|
/// Default Host admission follows the SAME already-admitted member inventory.
/// These are finite rejection/work bounds, not physical capacity. Explicit
/// check_model_tasks callers retain their supplied smaller policy unchanged.
pub fn original_model_tasks_admission_limits(
  original : WireEnvironment,
) -> ModelTaskLimits? {
  let mut bytes = 0L
  let mut nodes = 0L
  let mut text = 0L
  for entry in original.sections[position(ModelTaskContracts)] {
    bytes += entry.bytes.to_int64()
    nodes += entry.nodes.to_int64()
    // Complete encoded member bytes bound decoded Contract text independently
    // of its node count. Do not read the whole arena usage through a child.
    text += entry.bytes.to_int64()
  }
  // Per member the three subset hashes and two Contract reconstructions each
  // debit full (bytes+nodes). Closed-object field/name, selected text, number,
  // classification/region loops together are bounded by the other five full
  // traversals. This is work, never a claim that bytes are value nodes.
  let work = 10L * (bytes + nodes)
  if bytes > 2147483647L ||
    nodes > 2147483647L ||
    text > 2147483647L ||
    work > 2147483647L {
    return None
  }
  Some({
    bodies: {
      max_bytes: bytes.to_int(),
      max_nodes: nodes.to_int(),
      max_depth: 64,
      max_members: member_count(original, ModelTaskContracts),
    },
    contracts: {
      max_nodes: nodes.to_int(),
      max_depth: 64,
      max_text_bytes: text.to_int(),
    },
    max_work: work.to_int(),
  })
}

///|
/// Populated counterpart of the original empty registry recipe. Original wire,
/// member cursors/keys and borrowed field Strings remain with their prior
/// reader. This fold inspects only the current final inventory, once; no Task
/// declaration, normalized body or Provider is reissued to quote its capacity.
pub fn model_tasks_admission_construction_extent(
  original : WireEnvironment,
) -> RegistryConstructionExtent? {
  guard original_model_tasks_admission_limits(original) is Some(limits) else {
    return None
  }
  let count = member_count(original, ModelTaskContracts).to_int64()
  let collections = @shape.collection_construction_extent({
    records: 1L,
    record_references: 3L,
    record_words: 5L,
    reference_arrays: 1L,
    reference_items: count,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: count,
  }).unwrap()
  let mut peak = wire_admission_add(wire_admission_units(collections), {
    record_headers: 7L,
    reference_slots: 5L,
    scalar_words: 15L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
  for entry in original.sections[position(ModelTaskContracts)] {
    let n = entry.nodes
    let text = entry.bytes
    guard model_task_contract_read_bounds(n, entry.depth, text)
      is Some(contracts) &&
      wire_hash_construction_extent(n) is Some(hash) else {
      return None
    }
    // Contract readers retain their typed trees while subsequent hashes run.
    // Their keys/scalars borrow the original wire arena. Co-count both complete
    // valid Contract envelopes, without treating every node as both containers.
    let contract : RegistryConstructionExtent = {
      record_headers: contracts.retained.record_headers +
      contracts.scratch.record_headers,
      reference_slots: contracts.retained.reference_slots +
      contracts.scratch.reference_slots,
      scalar_words: contracts.retained.scalar_words +
      contracts.scratch.scalar_words,
      owned_utf16_units: contracts.scratch_utf16_units,
      owned_wire_bytes: 0L,
    }
    let lists = @shape.collection_construction_extent({
      // Task1H16R1W, Generation1H1R3W, Handling1H3R1W; Member/Cursor,
      // ObjectView, numeric/Text helpers and all selected Option/Result sites.
      records: 24L,
      record_references: 43L,
      record_words: 26L,
      reference_arrays: 2L,
      reference_items: 2L * n.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: n.to_int64(),
    }).unwrap()
    peak = wire_admission_add(peak, wire_admission_units(lists))
    peak = wire_admission_add(peak, wire_admission_add(contract, contract))
    peak = wire_admission_add(
      peak,
      wire_admission_add(hash, wire_admission_add(hash, hash)),
    )
  }
  // Limits are consumed only as DATA above; retain the expression so a future
  // independent overflow refusal cannot be silently removed by a caller.
  if limits.max_work < 0 {
    return None
  }
  Some(peak)
}
