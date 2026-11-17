///|
/// Final projection bounds come from the original writer's scalar usage. The
/// base's structural census is supplied by the same retained wire owner. This
/// fold neither emits nor parses a Task, and is selected once per Environment.
pub fn public_model_task_environment_limits(
  base_bytes : Int,
  base_nodes : Int,
  base_depth : Int,
  base_members : Int,
  base_tasks : Int,
  tasks : Array[NormalizedPublicModelTask],
) -> ModelTaskLimits? {
  if base_bytes < 1 ||
    base_nodes < 1 ||
    base_depth < 1 ||
    base_depth > 64 ||
    base_members < 0 ||
    base_tasks < 0 ||
    base_tasks > base_members ||
    base_members > base_nodes {
    return None
  }
  let mut bytes = base_bytes.to_int64()
  let mut nodes = base_nodes.to_int64()
  let mut depth = base_depth
  for task in tasks {
    bytes += task.task_bytes.to_int64() + 1L
    nodes += task.task_nodes.to_int64()
    depth = Int::max(depth, task.task_depth + 2)
  }
  let count = tasks.length().to_int64() + base_tasks.to_int64()
  let members = tasks.length().to_int64() + base_members.to_int64()
  // Six bounded read traversals, both complete emissions and hashes, and the
  // insertion sort's worst-case comparisons of two original SHA256 CIDs.
  if count > 0L && count > 2147483647L / 143L / count {
    return None
  }
  let work = 30L * (bytes + nodes) + 143L * count * count
  if bytes > 2147483647L ||
    nodes > 2147483647L ||
    work > 2147483647L ||
    depth > 64 {
    return None
  }
  Some({
    bodies: {
      max_bytes: bytes.to_int(),
      max_nodes: nodes.to_int(),
      max_depth: depth,
      max_members: members.to_int(),
    },
    contracts: {
      max_nodes: nodes.to_int(),
      max_depth: depth,
      max_text_bytes: bytes.to_int(),
    },
    max_work: work.to_int(),
  })
}

///|
/// Complete overlap of the original outer reader, ordered entry/vector copy,
/// both final writers, original Task Contract emitters and UTF8/hash buffers.
/// Successful output retains this finite peak conservatively on the same Host.
pub fn public_model_task_environment_construction_extent(
  base_bytes : Int,
  base_nodes : Int,
  base_depth : Int,
  base_members : Int,
  base_tasks : Int,
  tasks : Array[NormalizedPublicModelTask],
) -> RegistryConstructionExtent? {
  guard public_model_task_environment_limits(
      base_bytes, base_nodes, base_depth, base_members, base_tasks, tasks,
    )
    is Some(limits) &&
    @decode.preserving_json_admission_construction_inventory(
      base_bytes, base_nodes, base_depth,
    )
    is Some(parsed) &&
    model_task_decode_construction(base_nodes, base_depth) is Some(index) &&
    @encode.text_writer_construction_inventory(
      limits.bodies.max_bytes,
      limits.bodies.max_nodes,
      limits.bodies.max_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(
      limits.bodies.max_nodes,
      limits.bodies.max_depth,
    )
    is Some(hash) else {
    return None
  }
  let count = limits.bodies.max_members.to_int64()
  let entries = @shape.collection_construction_extent({
    records: 4L * count + 18L,
    record_references: 7L * count + 28L,
    record_words: 3L * count + 32L,
    reference_arrays: 4L,
    reference_items: 4L * count,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let mut extent = wire_admission_add(index, wire_admission_units(entries))
  extent = wire_admission_add(extent, {
    record_headers: parsed.record_headers +
    2L * writer.record_headers +
    3L * hash.record_headers,
    reference_slots: parsed.reference_slots +
    2L * writer.reference_slots +
    3L * hash.reference_slots,
    scalar_words: parsed.scalar_words +
    2L * writer.scalar_words +
    3L * hash.scalar_words,
    owned_utf16_units: parsed.owned_utf16_units +
    2L * writer.owned_utf16_units +
    3L * hash.owned_utf16_units +
    142L * count,
    owned_wire_bytes: base_bytes.to_int64() +
    2L * limits.bodies.max_bytes.to_int64() +
    3L * hash.owned_wire_bytes,
  })
  for task in tasks {
    let nodes = task.declaration.input.nodes.to_int64() +
      task.declaration.output.nodes.to_int64()
    if nodes > 2147483647L {
      return None
    }
    guard @value_contract.checked_emission_construction_extent(nodes.to_int())
      is Some(emission) else {
      return None
    }
    // Both sequential writers may keep their final outputs. Co-count all
    // original Contract emitter scratch; no earlier Task normalization runs.
    extent = wire_admission_add(extent, {
      record_headers: 2L * emission.record_headers,
      reference_slots: 2L * emission.reference_slots,
      scalar_words: 2L * emission.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  }
  Some(extent)
}
