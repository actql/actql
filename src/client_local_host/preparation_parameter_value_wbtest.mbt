///|
fn funded_value_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_literal(text, {
      max_input_bytes: 100000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap().node,
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn funded_value_limits() -> @parameters.DeclarationLimits {
  {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 10,
    max_text_bytes: 100000,
  }
}

///|
fn prepare_funded_value_prefix(
  owner : ClientParameterDeclarationPreflight[Array[String], Array[Int]],
) -> @parameters.DeclarationReadInput {
  prepare_parameter_declaration_preflight(owner).unwrap()
  let reader = parameter_declaration_preflight_outcome(owner).unwrap().0.unwrap()
  reconcile_parameter_declaration_preflight(owner).unwrap()
  prepare_parameter_declaration_header(owner).unwrap()
  prepare_parameter_declaration_inventory(owner).unwrap()
  reconcile_parameter_declaration_inventory(owner).unwrap()
  reader
}

///|
test "actual complete Value phase waits for one-byte parent growth and retries original syntax once" {
  let rows = Array::makei(100, i => i.to_string())
  let root = funded_value_cursor(
    "{\"x\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[" +
    rows.join(",") +
    "],\"meta\":{\"label\":\"x\"}}}",
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 200000L,
    execution_bytes: 200018L,
  }).unwrap()
  let input = ["same original complete Value"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_declaration_preflight(
    capacity,
    input,
    Some(root),
    funded_value_limits(),
  ).unwrap()
  assert_eq(parameter_preflight_initial_bytes, 11728L)
  let reader = prepare_funded_value_prefix(owner)
  prepare_parameter_declaration_type(owner).unwrap()
  let syntax = @parameters.declaration_read_pending_syntax(reader)
  let facts = @parameters.declaration_read_current_construction(reader)
  let work = @parameters.declaration_read_construction_work(reader)
  // Header1808+own fact vector616+actual Array Type768. Value113H435R209W
  // is6960; its maximum sequential temporary410H1626R1198W is28936.
  assert_eq(owner.body_bytes, 3192L)
  assert_eq(
    parameter_value_construction_bytes(reader, 0),
    Some((6960L, 29152L)),
  )
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let sibling = @resources.reserve_capacity(ledger, 148896L, 148896L).unwrap()
  // R0=73 + domain11256 + retained10152 + next temporary28936=51105.
  // The SAME unused sibling makes50409+148896=200001, exactly one short.
  assert_true(
    prepare_parameter_declaration_value(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.phase == ValueQuoted)
  assert_eq(owner.quote, Some((51105L, 51123L)))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(before),
  )
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationValue,
  )
  assert_true(
    physical_equal(syntax, @parameters.declaration_read_pending_syntax(reader)),
  )
  assert_true(
    physical_equal(
      facts,
      @parameters.declaration_read_current_construction(reader),
    ),
  )
  assert_true(
    physical_equal(work, @parameters.declaration_read_construction_work(reader)),
  )
  let quote = owner.quote
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_declaration_value(owner).unwrap()
  assert_true(physical_equal(quote, owner.quote))
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationComplete,
  )
  let completed = @parameters.finish_declaration_read(reader)
  assert_true(
    physical_equal(completed, @parameters.finish_declaration_read(reader)),
  )
  let declarations = completed.unwrap()
  assert_eq(@parameters.declaration_count(declarations), 1)
  assert_true(
    physical_equal(
      @parameters.declaration_at(declarations, 0).unwrap().parameter_type,
      syntax.unwrap().parameter_type,
    ),
  )
  // Existing bind is only a separate result-inspection consumer here; its
  // own preflight/BoundValues constructor is NOT claimed funded by this phase.
  guard @parameters.bind(declarations, None, {
      max_nodes: 1000,
      max_depth: 10,
      max_text_bytes: 100000,
    })
    is Ok(@parameters.Ready(bound)) else {
    fail("original cached default")
  }
  let original = @parameters.bound_value_at(bound, 0).unwrap()
  guard original.value.value is @admitted.Array(items) else {
    fail("original Array default")
  }
  assert_eq(@admitted.element_count(items), 100)
  for i in 0..<100 {
    assert_true(
      @admitted.element_at(items, i).unwrap() is @admitted.Number(n) &&
      n == i.to_double(),
    )
  }
  assert_true(prepare_parameter_declaration_value(owner) is Err(WrongPhase))
  reconcile_parameter_declarations(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((21953L, 21971L)),
  )
  assert_true(
    physical_equal(completed, @parameters.finish_declaration_read(reader)),
  )
  assert_true(reconcile_parameter_declarations(owner) is Err(WrongPhase))
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_true(owner.current_syntax is None && owner.current_type_facts is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((21953L, 21971L)),
  )
  assert_eq(
    (
      @resources.ledger_usage(ledger).attempts,
      @resources.ledger_usage(ledger).live_reservations,
    ),
    (0, 1),
  )
}

///|
test "same parent completes multiple original declarations without repeating quantity inventory" {
  let root = funded_value_cursor(
    "{\"z\":{\"type\":\"number\",\"integer\":true,\"minimum\":0,\"maximum\":5,\"default\":3},\"d\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"1h\"},\"a\":{\"type\":\"object\",\"fields\":{\"xs\":{\"type\":\"array\",\"items\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2}},\"ok\":{\"type\":\"boolean\"}},\"default\":{\"xs\":[\"1.20\"],\"ok\":true},\"meta\":{\"label\":\"kept\"}},\"c\":{\"type\":\"timestamp\",\"nullable\":true,\"default\":null},\"b\":{\"type\":\"string\"}}",
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 10000000L,
    execution_bytes: 10000000L,
  }).unwrap()
  let input = ["same five originals"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_declaration_preflight(
    capacity,
    input,
    Some(root),
    funded_value_limits(),
  ).unwrap()
  let reader = prepare_funded_value_prefix(owner)
  let work = @parameters.declaration_read_construction_work(reader)
  let originals : Array[@contract.ParameterType] = []
  for i in 0..<5 {
    assert_true(
      physical_equal(
        work,
        @parameters.declaration_read_construction_work(reader),
      ),
    )
    prepare_parameter_declaration_type(owner).unwrap()
    let syntax = @parameters.declaration_read_pending_syntax(reader).unwrap()
    originals.push(syntax.parameter_type)
    prepare_parameter_declaration_value(owner).unwrap()
    if i < 4 {
      assert_eq(
        @parameters.declaration_read_phase(reader),
        @parameters.DeclarationType,
      )
    }
  }
  let result = @parameters.finish_declaration_read(reader)
  let declarations = result.unwrap()
  assert_eq(@parameters.declaration_count(declarations), 5)
  for i in 0..<5 {
    assert_true(
      physical_equal(
        @parameters.declaration_at(declarations, i).unwrap().parameter_type,
        originals[i],
      ),
    )
  }
  assert_eq(
    Array::makei(5, i => {
      @parameters.declaration_at(declarations, i).unwrap().name
    }),
    ["a", "b", "c", "d", "z"],
  )
  assert_true(
    !@parameters.has_default(
      @parameters.declaration_at(declarations, 1).unwrap(),
    ),
  )
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  reconcile_parameter_declarations(owner).unwrap()
  let retained = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  assert_true(retained.0 < before.0 && retained.1 < before.1)
  assert_true(
    physical_equal(result, @parameters.finish_declaration_read(reader)),
  )
  assert_true(prepare_parameter_declaration_type(owner) is Err(WrongPhase))
  assert_true(prepare_parameter_declaration_inventory(owner) is Err(WrongPhase))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}

///|
test "funded Value preserves metadata before Value before constraints and keeps refusal backing" {
  for
    text in [
      "{\"x\":{\"type\":\"number\",\"integer\":true,\"default\":1.5}}", "{\"x\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"0ms\"}}",
      "{\"x\":{\"type\":\"array\",\"length\":2,\"items\":{\"type\":\"number\"},\"default\":[1]}}",
      "{\"x\":{\"type\":\"number\",\"default\":\"bad\"}}", "{\"x\":{\"type\":\"number\",\"default\":\"bad\",\"meta\":{}}}",
      "{\"x\":{\"type\":\"number\",\"default\":\"bad\",\"meta\":{\"actql_bad\":0}}}",
      "{\"x\":{\"type\":\"number\",\"default\":\"bad\",\"meta\":null}}",
    ] {
    let root = funded_value_cursor(text)
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 10000000L,
      execution_bytes: 10000000L,
    }).unwrap()
    let input = ["same original refusal"]
    let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      73L,
      91L,
      max_borrowers=1,
    ).unwrap()
    let owner = begin_parameter_declaration_preflight(
      capacity,
      input,
      Some(root),
      funded_value_limits(),
    ).unwrap()
    let reader = prepare_funded_value_prefix(owner)
    prepare_parameter_declaration_type(owner).unwrap()
    let syntax = @parameters.declaration_read_pending_syntax(reader).unwrap()
    prepare_parameter_declaration_value(owner).unwrap()
    let error = @parameters.finish_declaration_read(reader)
    if text.contains("\"integer\"") {
      assert_true(
        error
        is Err(@parameters.ParameterIssue(@parameters.NumericConstraint, ..)),
      )
    } else if text.contains("\"format\"") {
      assert_true(
        error
        is Err(@parameters.ParameterIssue(@parameters.DurationConstraint, ..)),
      )
    } else if text.contains("\"length\"") {
      assert_true(
        error
        is Err(@parameters.ParameterIssue(@parameters.LengthConstraint, ..)),
      )
    } else if text.contains("\"meta\":null") {
      assert_true(
        error is Err(@parameters.Decode({ kind: @decode.WrongType, .. })),
      )
    } else if text.contains("actql_bad") {
      assert_true(
        error
        is Err(@parameters.ParameterIssue(@parameters.ReservedMetadataKey, ..)),
      )
    } else if text.contains("\"meta\":{}") {
      assert_true(
        error
        is Err(@parameters.ParameterIssue(@parameters.InvalidMetadata, ..)),
      )
    } else {
      assert_true(
        error
        is Err(@parameters.Value(@admitted.ValueIssue(@admitted.WrongType, ..))),
      )
    }
    assert_true(syntax.default_value is Some(_))
    assert_true(
      physical_equal(error, @parameters.finish_declaration_read(reader)),
    )
    let debit = @resources.preparation_capacity_working_extents(capacity, input)
    assert_true(reconcile_parameter_declarations(owner) is Err(WrongPhase))
    clear_parameter_declaration_preflight(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      debit,
    )
  }
}

///|
test "complete absent original declarations reconcile while empty original refusal keeps backing" {
  for root in [None, Some(funded_value_cursor("{}"))] {
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 100000L,
      execution_bytes: 100000L,
    }).unwrap()
    let input = ["original absent and empty"]
    let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      73L,
      91L,
      max_borrowers=1,
    ).unwrap()
    let owner = begin_parameter_declaration_preflight(
      capacity,
      input,
      root,
      funded_value_limits(),
    ).unwrap()
    prepare_parameter_declaration_preflight(owner).unwrap()
    let reader = parameter_declaration_preflight_outcome(owner).unwrap().0.unwrap()
    reconcile_parameter_declaration_preflight(owner).unwrap()
    prepare_parameter_declaration_header(owner).unwrap()
    assert_eq(
      @parameters.declaration_read_phase(reader),
      @parameters.DeclarationComplete,
    )
    let result = @parameters.finish_declaration_read(reader)
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    )
    match root {
      None => {
        assert_eq(@parameters.declaration_count(result.unwrap()), 0)
        assert_eq(before, Ok((12905L, 12923L)))
        reconcile_parameter_declarations(owner).unwrap()
        assert_eq(
          @resources.preparation_capacity_working_extents(capacity, input),
          before,
        )
        assert_true(owner.phase == RetainedDeclarations)
      }
      Some(_) => {
        assert_true(
          result
          is Err(@parameters.ParameterIssue(@parameters.EmptyDeclarations, ..)),
        )
        assert_true(reconcile_parameter_declarations(owner) is Err(WrongPhase))
      }
    }
    assert_true(
      physical_equal(result, @parameters.finish_declaration_read(reader)),
    )
    clear_parameter_declaration_preflight(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      before,
    )
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 1)
  }
}
