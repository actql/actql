///|
fn catalog_current_program() -> @syntax.Program {
  @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
    funded_json_bounds(),
    format=Json,
  ).unwrap()
}

///|
// The same pure checked empty evidence feeds both the portable observer
// and the original Node current-boundary fixture. It creates no Node owner.
fn catalog_current_empty_sources() -> @binding_host.HostSources {
  let witness = @binding_wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @binding_wire.check_mixed_program_claims(witness, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @binding_host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  sources
}

///|
test "binding observer retains changed evidence geometry and bounded original visits" {
  let program = catalog_current_program()
  let entries : Array[@context.StageCapacityInput] = []
  let (empty, initial_work) = @context.observe_capacity_input_construction_inventory(
    program, entries,
  )
  let empty = empty.unwrap()
  assert_eq(initial_work, 1L)
  let sources = catalog_current_empty_sources()
  entries.push({ stage: "missing", sources, uses: [], })
  let (changed, changed_work) = @context.observe_capacity_input_construction_inventory(
    program, entries,
  )
  let changed = changed.unwrap()
  assert_eq(changed_work, 2L)
  // One retained material and its two references; one escaping consumer Array,
  // one transient limit Map, and one assigned Stage entry. No uses were added.
  assert_eq(changed.records, empty.records + 1L)
  assert_eq(changed.record_references, empty.record_references + 2L)
  assert_eq(changed.reference_arrays, empty.reference_arrays + 1L)
  assert_eq(changed.maps, empty.maps + 1L)
  assert_eq(changed.map_entries, empty.map_entries + 1L)
  assert_eq(
    (
      changed.record_words,
      changed.reference_items,
      changed.scalar_arrays,
      changed.scalar_items,
    ),
    (
      empty.record_words,
      empty.reference_items,
      empty.scalar_arrays,
      empty.scalar_items,
    ),
  )
  // Only min(Stage count, entry count) can construct consumers. This DATA
  // observation neither admits either unknown Stage nor grants any capacity.
  entries.push({ stage: "also-missing", sources, uses: [], })
  let (bounded, bounded_work) = @context.observe_capacity_input_construction_inventory(
    program, entries,
  )
  assert_eq(bounded, Some(changed))
  assert_eq(bounded_work, 2L)
}
