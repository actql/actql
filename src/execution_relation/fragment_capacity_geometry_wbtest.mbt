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
test "bounded leaf prior slot guard refuses malformed and snapshot references" {
  assert_false(bounded_leaf_prior_slot_supported(true, 1, -1))
  assert_false(bounded_leaf_prior_slot_supported(true, 1, 1))
  assert_false(bounded_leaf_prior_slot_supported(true, 1, 2))
  assert_false(bounded_leaf_prior_slot_supported(false, 1, 0))
  assert_false(bounded_leaf_prior_slot_supported(true, 0, 0))
  assert_true(bounded_leaf_prior_slot_supported(true, 1, 0))
  assert_true(bounded_leaf_prior_slot_supported(true, 3, 1))
}

///|
test "bounded leaf callsite preserves physical envelopes and generic fallback" {
  let sequence = prepared_sequence(row_owner(",{\"derive\":{\"c\":\"a\"}}"))
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
  let measurement : FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let quote = fn(context : FragmentRuntimeContext) {
    generated_bounded_sequence_capacity(
      { ..selected, contexts: [context], },
      limits,
      measurement,
    ).unwrap().execution_bytes
  }
  let baseline = quote(context)
  assert_eq(
    quote({
      ..context,
      physical: {
        ..context.physical,
        max_body_nodes: context.physical.max_body_nodes + 1,
      },
    }) -
    baseline,
    256L,
  )
  assert_eq(
    quote({
      ..context,
      physical: {
        ..context.physical,
        max_body_bytes: context.physical.max_body_bytes + 1,
      },
    }) -
    baseline,
    8L,
  )
  assert_eq(
    quote({
      ..context,
      physical: {
        ..context.physical,
        max_body_depth: context.physical.max_body_depth + 1,
      },
    }) -
    baseline,
    256L,
  )
  let larger_live = {
    ..context,
    limits: {
      ..context.limits,
      max_live_value_bytes: context.limits.max_live_value_bytes + 1L,
    },
  }
  assert_eq(quote(larger_live), baseline)
  let ordinary = generated_sequence_capacity(selected, limits, measurement).unwrap()
  let larger = generated_sequence_capacity(
    { ..selected, contexts: [larger_live], },
    limits,
    measurement,
  ).unwrap()
  assert_eq(larger.execution_bytes - ordinary.execution_bytes, 264L)
  let unselected = generated_bounded_sequence_capacity(
    generated, limits, measurement,
  ).unwrap()
  let generic = generated_sequence_capacity(generated, limits, measurement).unwrap()
  assert_eq(unselected.retained_bytes, generic.retained_bytes)
  assert_eq(unselected.execution_bytes, generic.execution_bytes)
}

///|
test "bounded nonleaf callsite retains full logical live value premium" {
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
  let selected = select_generated_sequence_step(generated, 1).unwrap()
  let limits = leaf_geometry_limits(3)
  let measurement : FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let ordinary = generated_bounded_sequence_capacity(
    selected, limits, measurement,
  ).unwrap()
  let larger_context = {
    ..context,
    limits: {
      ..context.limits,
      max_live_value_bytes: context.limits.max_live_value_bytes + 1L,
    },
  }
  let larger = generated_bounded_sequence_capacity(
    { ..selected, contexts: [larger_context], },
    limits,
    measurement,
  ).unwrap()
  assert_eq(larger.execution_bytes - ordinary.execution_bytes, 264L)
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

///|
test "bounded leaf geometry accepts actual checked typed null parameter" {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"n\":{\"type\":\"number\",\"nullable\":true}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let pipeline = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":{\"$param\":\"n\"}}}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 100,
    max_references: 100,
    max_work: 1000,
    max_identifier_bytes: 1000,
  }).unwrap()
  guard @parameter.bind(declarations, Some(input_cursor("{\"n\":null}")), {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is @parameter.Ready(values) else {
    fail("complete binding")
  }
  let owner = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=1,
    max_name_bytes=1,
  ).unwrap()
  let sequence = prepared_sequence(owner)
  let context = sequence_fragment_context(sequence, 1, 1L)
  let bindings = @lower.kernel_bindings(context.kernel).unwrap()
  let expression = @lower.binding_at(bindings, 0).unwrap().1
  assert_true(@lower.expression_body(expression) is @lower.TypedNull)
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
      leaf_geometry_limits(1),
    )
    is Some(_),
  )
}

///|
fn text_number_geometry_sequence() -> (
  GeneratedSequence,
  FragmentRuntimeContext,
) raise {
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"title":{"type":"string","nullable":false}},"rows":[{"title":"Issue 5"}]},"as":"seed"},{"derive":{"clock_ms":{"cast":{"value":{"substring":{"value":{"field":"title"},"start":{"literal":7}}},"target":{"type":"number"}}}},"as":"out"}]
    ),
  )
  let sequence = prepared_sequence(owner)
  let context = sequence_fragment_context(sequence, 1, 1L)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  (select_generated_sequence_step(generated, 1).unwrap(), context)
}

///|
test "bounded text-number leaf geometry retains the actual scalar copy allowance" {
  let (selected, context) = text_number_geometry_sequence()
  let limits = leaf_geometry_limits(100)
  let original = bounded_leaf_fragment_capacity(selected, context, limits).unwrap()
  let larger = bounded_leaf_fragment_capacity(
    selected,
    {
      ..context,
      limits: {
        ..context.limits,
        max_live_value_bytes: context.limits.max_live_value_bytes + 1L,
      },
    },
    limits,
  ).unwrap()
  let one = preparation_representation_cost({
    record_headers: 2L,
    reference_slots: 2L,
    scalar_words: 2L,
    owned_utf16_units: 4L,
    owned_wire_bytes: 4L,
  }).unwrap()
  assert_eq(larger - original, one)
  assert_true(one < execution_capacity_node_bytes())
  assert_true(
    bounded_leaf_fragment_capacity(
      selected,
      {
        ..context,
        limits: {
          ..context.limits,
          max_live_value_bytes: 9223372036854775807L,
        },
      },
      limits,
    )
    is None,
  )
  let physical : FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let capacity = generated_bounded_sequence_capacity(selected, limits, physical).unwrap()
  let larger_context = {
    ..context,
    physical: {
      ..context.physical,
      max_body_nodes: context.physical.max_body_nodes + 1,
    },
  }
  let larger_capacity = generated_bounded_sequence_capacity(
    { ..selected, contexts: [larger_context], },
    limits,
    physical,
  ).unwrap()
  assert_eq(
    larger_capacity.execution_bytes - capacity.execution_bytes,
    execution_capacity_node_bytes(),
  )
  assert_true(
    run_expr(
      cast_test_expression(
        "{\"substring\":{\"value\":{\"literal\":\"Issue 5\"},\"start\":{\"literal\":7}}}",
        "{\"type\":\"number\"}",
      ),
    )
    is Ok(Number(5.0)),
  )
  assert_true(
    run_expr(
      cast_test_expression(
        "{\"substring\":{\"value\":{\"literal\":\"Issue nope\"},\"start\":{\"literal\":7}}}",
        "{\"type\":\"number\"}",
      ),
    )
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
}
