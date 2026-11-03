///|
fn leaf_geometry_limits(rows : Int) -> SequenceExecutionLimits {
  let values : ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
    max_work: 100000,
  }
  {
    rows: {
      max_rows: rows,
      retained_entries: 10000,
      metadata_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
}

///|
test "bounded leaf geometry uses same kernel and preserves row root occurrences" {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":{\"c\":\"a\",\"d\":\"1\"}}"),
  )
  let context = sequence_fragment_context(sequence, 1, 2L)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let selected = select_generated_sequence_step(generated, 1).unwrap()
  let limits = leaf_geometry_limits(3)
  let bytes = bounded_leaf_fragment_capacity(selected, context, limits).unwrap()
  assert_true(bytes > 0L)
  // Two independent full-side row root occurrences, including failed prefixes.
  let larger = bounded_leaf_fragment_capacity(
    selected,
    context,
    leaf_geometry_limits(4),
  ).unwrap()
  let root = preparation_representation_cost({
    record_headers: 8L,
    reference_slots: 16L,
    scalar_words: 16L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(larger - bytes, 2L * root)
  assert_true(
    bounded_leaf_fragment_capacity(generated, context, limits) is None,
  )
  assert_true(
    bounded_leaf_fragment_capacity(selected, context, leaf_geometry_limits(-1))
    is None,
  )
  let foreign = prepared_sequence(
    row_owner(",{\"derive\":{\"c\":\"a\",\"d\":\"1\"}}"),
  )
  assert_true(
    bounded_leaf_fragment_capacity(
      selected,
      sequence_fragment_context(foreign, 1, 2L),
      limits,
    )
    is None,
  )
  // Logical/physical guards do not determine the alias metadata inventory.
  let changed = {
    ..context,
    limits: { ..context.limits, max_live_value_bytes: 1L, },
  }
  assert_eq(
    bounded_leaf_fragment_capacity(selected, changed, limits),
    Some(bytes),
  )
}

///|
test "bounded leaf geometry rejects constructing expressions" {
  let sequence = prepared_sequence(row_owner(",{\"derive\":{\"c\":\"a + 1\"}}"))
  let context = sequence_fragment_context(sequence, 1, 2L)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  assert_true(
    bounded_leaf_fragment_capacity(
      select_generated_sequence_step(generated, 1).unwrap(),
      context,
      leaf_geometry_limits(3),
    )
    is None,
  )
}

///|
test "bounded leaf geometry accepts repeated prior slots without deduplicating roots" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"old\":\"a\"},{\"copy\":\"old\"},{\"again\":\"old\"}]}",
    ),
  )
  let context = ordered_sequence_fragment_context(sequence, 100000L)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  assert_true(
    bounded_leaf_fragment_capacity(
      select_generated_sequence_step(generated, 1).unwrap(),
      context,
      leaf_geometry_limits(3),
    )
    is Some(_),
  )
}
