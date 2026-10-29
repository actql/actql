///|
/// Constructor DATA from the same original policy/registry. All retained
/// Contracts coexist; one original reader/Field assembler workspace is reused.
pub(all) struct ProtocolValueConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  scratch_utf16_units : Int64
  envelopes : Int
  command_inputs : Int
  work : Int64
} derive(Eq, Debug)

///|
pub fn protocol_value_construction_inspection_bound(
  policies : SourceDataPolicies,
) -> Int64 {
  let registry = policies.references.contents.registry
  // Actual admitted envelope nodes include each disjoint body. Each subtree
  // has the original Environment/body ancestry3. Three selected text-field
  // comparisons plus node/field visits and Command root metadata fit9N+10E.
  1L +
  9L * registry.nodes.to_int64() +
  10L * registry.entries.length().to_int64()
}

///|
/// Metadata only; no type grammar, canonicalization, body hash or permission.
/// The exact original value-role predicate selects bodies. A large enum/MIME
/// DATA value is not converted into an identifier-normalization workspace.
pub fn observe_protocol_value_construction(
  policies : SourceDataPolicies,
) -> ProtocolValueConstructionInventory {
  let registry = policies.references.contents.registry
  let mut retained = @shape.CollectionConstructionExtent::{
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  let mut scratch = retained
  let mut utf16 = 0L
  let mut envelopes = 0
  let mut commands = 0
  let mut command_fields = 0
  let mut work = 1L
  for envelope in registry.entries {
    work += 1L
    if !protocol_value_kind(envelope.kind) {
      continue
    }
    envelopes += 1
    let g = @value_contract.observe_read_construction_geometry(envelope.body)
    work += g.work
    let value = @value_contract.read_construction_inventory(g).unwrap()
    retained = @shape.add_collection_construction_extents(
      retained,
      value.retained,
    ).unwrap()
    let working = if envelope.kind == "command_input" {
      commands += 1
      let command = observe_command_input_construction(envelope.body)
      work += command.work
      command_fields = Int::max(command_fields, g.max_fields)
      retained = @shape.add_collection_construction_extents(
        retained,
        command_input_retained_construction(command),
      ).unwrap()
      @shape.add_collection_construction_extents(
        value.scratch,
        command_input_working_construction(command),
      ).unwrap()
    } else {
      value.scratch
    }
    // Per-axis upper envelope of non-overlapping original reader frames; keep
    // all typed outputs separately. This is not a sum of sequential body peaks.
    scratch = {
      record_headers: Int64::max(scratch.record_headers, working.record_headers),
      reference_slots: Int64::max(
        scratch.reference_slots,
        working.reference_slots,
      ),
      scalar_words: Int64::max(scratch.scalar_words, working.scalar_words),
    }
    utf16 = Int64::max(utf16, value.scratch_utf16_units)
  }
  let count = envelopes.to_int64()
  let roots = @shape.collection_construction_extent({
    records: 1L + 2L * count,
    record_references: 3L + 3L * count,
    record_words: 2L,
    reference_arrays: 1L,
    reference_items: count,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: count,
  }).unwrap()
  let child = @decode.indexed_child_construction_extent()
  let probe = if commands > 0 { 1L } else { 0L }
  // Original value meter/remaining limits/branch observation/error/result
  // controls. Command probe ObjectView+lookup/Map lives beside its reader.
  let caller = @shape.collection_construction_extent({
    records: 10L + probe * child.record_headers,
    record_references: 9L + probe * child.reference_slots,
    record_words: 14L + probe * child.scalar_words,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: probe,
    map_entries: probe * command_fields.to_int64(),
  }).unwrap()
  {
    retained: @shape.add_collection_construction_extents(retained, roots).unwrap(),
    scratch: @shape.add_collection_construction_extents(scratch, caller).unwrap(),
    scratch_utf16_units: utf16,
    envelopes,
    command_inputs: commands,
    work,
  }
}

///|
pub fn protocol_value_construction_extent(
  v : ProtocolValueConstructionInventory,
) -> RegistryConstructionExtent {
  let all = @shape.add_collection_construction_extents(v.retained, v.scratch).unwrap()
  {
    record_headers: all.record_headers,
    reference_slots: all.reference_slots,
    scalar_words: all.scalar_words,
    owned_utf16_units: v.scratch_utf16_units,
    owned_wire_bytes: 0L,
  }
}

///|
pub fn protocol_value_retained_extent(
  v : ProtocolValueConstructionInventory,
) -> RegistryConstructionExtent {
  {
    record_headers: v.retained.record_headers,
    reference_slots: v.retained.reference_slots,
    scalar_words: v.retained.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
