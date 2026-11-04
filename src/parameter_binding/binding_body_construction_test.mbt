///|
fn binding_body_original(
  definitions : @parameter_binding.Declarations,
  supplied : @decode.Cursor?,
  value_limits : @value.Limits,
) -> @parameter_binding.BindingReadInput {
  let original = @parameter_binding.prepare_binding_read(
    definitions, supplied, value_limits,
  ).unwrap()
  @parameter_binding.advance_binding_read(original)
  original
}

///|
test "original binding construction observes selection once and forwards SAME source default and work" {
  let definitions = declarations(
    "{\"x\":{\"type\":\"number\"},\"z\":{\"type\":\"string\",\"default\":\"hi\"}}",
  )
  let original = binding_body_original(
    definitions,
    Some(cursor("{\"x\":7}")),
    values_limit(),
  )
  assert_eq(
    @parameter_binding.binding_read_construction_maximum_work(original),
    Some(52L),
  )
  let work = @parameter_binding.observe_binding_read_construction(original)
  assert_eq(work, Some(13L))
  assert_true(
    physical_equal(
      work,
      @parameter_binding.observe_binding_read_construction(original),
    ),
  )
  let current = @parameter_binding.binding_read_current_construction(original)
  assert_true(current.unwrap().provided)
  assert_eq(current.unwrap().depth, 1)
  @parameter_binding.advance_binding_read(original)
  assert_true(
    physical_equal(
      current.unwrap().selected,
      @parameter_binding.binding_read_pending_source(original),
    ),
  )
  assert_true(
    physical_equal(
      current.unwrap().declaration,
      @parameter_binding.binding_read_pending_declaration(original).unwrap(),
    ),
  )
  let complete = @parameter_binding.finish_binding_read(original).unwrap()
  guard complete is @parameter_binding.Ready(values) else {
    fail("original Ready")
  }
  let independently_bound = original_default_values(
    definitions,
    Some("{\"x\":7}"),
  )
  assert_true(
    physical_equal(
      @parameter_binding.bound_value_at(values, 1).unwrap().value,
      @parameter_binding.bound_value_at(independently_bound, 1).unwrap().value,
    ),
  )
  assert_eq(identity_cid(values), identity_cid(independently_bound))
}

///|
test "original binding supplied Value uses same constraints and default Value is not constructed again" {
  let definitions = declarations("{\"x\":{\"type\":\"number\",\"default\":4}}")
  for supplied in [None, Some(cursor("{\"x\":7}"))] {
    let original = binding_body_original(definitions, supplied, values_limit())
    @parameter_binding.observe_binding_read_construction(original).unwrap()
    |> ignore
    @parameter_binding.advance_binding_read(original)
    let preflight = @parameter_binding.binding_preflight_construction_inventory(
      original,
    ).unwrap()
    if supplied is Some(_) {
      assert_eq(
        (
          preflight.traversal.record_headers,
          preflight.traversal.reference_slots,
          preflight.traversal.scalar_words,
        ),
        (15L, 31L, 13L),
      )
      assert_eq(
        (
          preflight.refusal.record_headers,
          preflight.refusal.reference_slots,
          preflight.refusal.scalar_words,
        ),
        (11L, 29L, 13L),
      )
    }
    @parameter_binding.advance_binding_read(original)
    let v = @parameter_binding.binding_value_construction_inventory(original).unwrap()
    if supplied is Some(_) {
      assert_true(v.value is Some(_))
      assert_eq(
        (
          v.returned.record_headers,
          v.returned.reference_slots,
          v.returned.scalar_words,
        ),
        (8L, 15L, 8L),
      )
      assert_eq(
        (
          v.constraints.record_headers,
          v.constraints.reference_slots,
          v.constraints.scalar_words,
        ),
        (37L, 88L, 44L),
      )
    } else {
      assert_true(v.value is None)
      assert_eq(
        (
          v.returned.record_headers,
          v.returned.reference_slots,
          v.returned.scalar_words,
        ),
        (6L, 12L, 6L),
      )
      assert_eq(
        (
          v.constraints.record_headers,
          v.constraints.reference_slots,
          v.constraints.scalar_words,
        ),
        (0L, 0L, 0L),
      )
    }
    @parameter_binding.advance_binding_read(original)
    assert_true(
      @parameter_binding.binding_value_construction_inventory(original) is None,
    )
  }
}

///|
test "observed binding still refuses later invalid supplied value after missing original and charges defaults" {
  let definitions = declarations(
    "{\"a\":{\"type\":\"number\"},\"z\":{\"type\":\"number\",\"integer\":true}}",
  )
  let original = binding_body_original(
    definitions,
    Some(cursor("{\"z\":1.5}")),
    values_limit(),
  )
  @parameter_binding.observe_binding_read_construction(original).unwrap()
  |> ignore
  @parameter_binding.advance_binding_read(original)
  assert_eq(
    @parameter_binding.binding_read_phase(original),
    @parameter_binding.BindingSelection,
  )
  assert_true(
    @parameter_binding.finish_binding_read(original)
    is Err(
      @parameter_binding.BindingInput(
        @parameter_binding.Supplied,
        @parameter_binding.ParameterIssue(
          @parameter_binding.NumericConstraint,
          ..
        )
      )
    ),
  )
  let defaults = declarations(
    "{\"x\":{\"type\":\"string\",\"default\":\"long\"}}",
  )
  let original = binding_body_original(defaults, None, values_limit(text=1))
  @parameter_binding.observe_binding_read_construction(original).unwrap()
  |> ignore
  @parameter_binding.advance_binding_read(original)
  @parameter_binding.advance_binding_read(original)
  assert_true(
    @parameter_binding.finish_binding_read(original)
    is Err(
      @parameter_binding.BindingInput(
        @parameter_binding.Default,
        @parameter_binding.ParameterIssue(@parameter_binding.BudgetExceeded, ..)
      )
    ),
  )
  assert_true(
    @parameter_binding.binding_value_construction_inventory(original) is None,
  )
}
