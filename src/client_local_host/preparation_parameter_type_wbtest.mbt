///|
test "actual Parameter Type builder waits for same-parent grow and preserves original quote association" {
  let root = funded_parameter_cursor("{\"x\":{\"type\":\"number\"}}")
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 50000L,
    execution_bytes: 50018L,
  }).unwrap()
  let input = ["same original Type"]
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
    funded_parameter_limits(),
  ).unwrap()
  assert_eq(parameter_preflight_initial_bytes, 7080L)
  prepare_parameter_declaration_preflight(owner).unwrap()
  let original = parameter_declaration_preflight_outcome(owner)
  let reader = original.unwrap().0.unwrap()
  reconcile_parameter_declaration_preflight(owner).unwrap()
  prepare_parameter_declaration_header(owner).unwrap()
  prepare_parameter_declaration_inventory(owner).unwrap()
  reconcile_parameter_declaration_inventory(owner).unwrap()
  let cursor = @parameters.declaration_read_type_cursor(reader)
  let facts = @parameters.declaration_read_current_construction(reader)
  let work = @parameters.declaration_read_construction_work(reader)
  // Existing returned488 plus ONE8-byte logical scalar word; tariff unchanged.
  assert_eq(parameter_type_construction_bytes(reader, 0), Some((496L, 15980L)))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((9577L, 9595L)),
  )
  let sibling = @resources.reserve_capacity(ledger, 23948L, 23948L).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 33525L)
  assert_true(
    prepare_parameter_declaration_type(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.phase == TypeQuoted)
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationType,
  )
  assert_true(@parameters.declaration_read_pending_syntax(reader) is None)
  assert_true(physical_equal(owner.current_type, cursor))
  assert_true(physical_equal(owner.current_type_facts, facts))
  let quote = owner.quote.unwrap()
  assert_eq(quote, (26053L, 26071L))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((9577L, 9595L)),
  )
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_declaration_type(owner).unwrap()
  assert_true(physical_equal(quote, owner.quote.unwrap()))
  assert_true(
    physical_equal(original, parameter_declaration_preflight_outcome(owner)),
  )
  assert_true(
    physical_equal(work, @parameters.declaration_read_construction_work(reader)),
  )
  assert_true(
    physical_equal(
      facts,
      @parameters.declaration_read_current_construction(reader),
    ),
  )
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationValue,
  )
  let syntax = @parameters.declaration_read_pending_syntax(reader)
  assert_true(
    physical_equal(syntax, @parameters.declaration_read_pending_syntax(reader)),
  )
  assert_true(syntax.unwrap().parameter_type.rule is @contract.Numeric(..))
  assert_true(
    syntax.unwrap().default_value is None && syntax.unwrap().metadata is None,
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((26053L, 26071L)),
  )
  assert_true(prepare_parameter_declaration_type(owner) is Err(WrongPhase))
  assert_true(
    reconcile_parameter_declaration_inventory(owner) is Err(WrongPhase),
  )
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_true(owner.current_type is None && owner.current_type_facts is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((26053L, 26071L)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}

///|
test "funded Type retains original name NULL and nested field refusals without Value work" {
  for
    text in [
      "{\"bad-name\":null}", "{\"x\":{\"type\":\"unknown\"}}", "{\"x\":{\"type\":\"object\",\"fields\":{\"bad.name\":{\"type\":\"number\"}}}}",
    ] {
    let root = funded_parameter_cursor(text)
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 1000000L,
      execution_bytes: 1000000L,
    }).unwrap()
    let input = ["original Type refusal"]
    let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      73L,
      91L,
      max_borrowers=1,
    ).unwrap()
    let limits : @parameters.DeclarationLimits = {
      max_parameters: 2,
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 10000,
    }
    let owner = begin_parameter_declaration_preflight(
      capacity,
      input,
      Some(root),
      limits,
    ).unwrap()
    prepare_parameter_declaration_preflight(owner).unwrap()
    let reader = parameter_declaration_preflight_outcome(owner).unwrap().0.unwrap()
    reconcile_parameter_declaration_preflight(owner).unwrap()
    prepare_parameter_declaration_header(owner).unwrap()
    prepare_parameter_declaration_inventory(owner).unwrap()
    reconcile_parameter_declaration_inventory(owner).unwrap()
    let current = @parameters.declaration_read_type_cursor(reader).unwrap()
    prepare_parameter_declaration_type(owner).unwrap()
    assert_eq(
      @parameters.declaration_read_phase(reader),
      @parameters.DeclarationComplete,
    )
    let refused = @parameters.finish_declaration_read(reader)
    if text.has_prefix("{\"bad-name\"") {
      guard refused is Err(@parameters.ParameterIssue(kind, path~, span~)) else {
        fail("original name refusal before NULL")
      }
      assert_eq(kind, @parameters.InvalidName)
      assert_eq(path, @decode.cursor_path(current))
      assert_eq(span, @decode.cursor_key_span(current).unwrap())
    } else if text.contains("unknown") {
      assert_true(
        refused
        is Err(
          @parameters.Contract(
            @contract.ContractIssue(@contract.UnknownType("unknown"), ..)
          )
        ),
      )
    } else {
      guard refused
        is Err(
          @parameters.Contract(@contract.ContractIssue(kind, path~, span~))
        ) else {
        fail("original invalid field")
      }
      assert_eq(kind, @contract.InvalidFieldName("bad.name"))
      let fields = @decode.field_at(current, 1).unwrap().1
      let child = @decode.field_at(fields, 0).unwrap().1
      assert_eq(path, @decode.cursor_path(child))
      assert_eq(span, @decode.cursor_key_span(child).unwrap())
    }
    assert_true(@parameters.declaration_read_pending_syntax(reader) is None)
    let charged = @resources.preparation_capacity_working_extents(
      capacity, input,
    )
    clear_parameter_declaration_preflight(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      charged,
    )
  }
}
