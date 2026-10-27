///|
fn binding_body_definitions(text : String) -> @parameters.Declarations {
  @parameters.read_declarations(
    Some(funded_value_cursor(text)),
    funded_value_limits(),
  ).unwrap()
}

///|
fn binding_body_value_limits() -> @admitted.Limits {
  { max_nodes: 1000, max_depth: 10, max_text_bytes: 100000, }
}

///|
fn binding_body_prefix(
  owner : ClientParameterBindingPreparation[Array[String], Array[Int]],
) -> @parameters.BindingReadInput {
  prepare_parameter_binding_header(owner).unwrap()
  let original = parameter_binding_preparation_outcome(owner).unwrap().unwrap()
  prepare_parameter_binding_inventory(owner).unwrap()
  reconcile_parameter_binding_inventory(owner).unwrap()
  original
}

///|
fn finish_funded_binding_body(
  owner : ClientParameterBindingPreparation[Array[String], Array[Int]],
  original : @parameters.BindingReadInput,
) -> Result[@parameters.BindingResult, @parameters.Issue] {
  while @parameters.binding_read_phase(original) != @parameters.BindingComplete {
    match @parameters.binding_read_phase(original) {
      @parameters.BindingSelection =>
        prepare_parameter_binding_selection(owner).unwrap()
      @parameters.BindingPreflight =>
        prepare_parameter_binding_preflight(owner).unwrap()
      @parameters.BindingValue =>
        prepare_parameter_binding_value(owner).unwrap()
      _ => abort("original funded binding boundary")
    }
  }
  @parameters.finish_binding_read(original)
}

///|
test "confirmed binding inventory scratch is not regrown for a smaller original selection" {
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 20000L,
    execution_bytes: 20018L,
  }).unwrap()
  let input = ["confirmed scratch retired, original Header retained"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_binding_preparation(
    capacity,
    input,
    binding_body_definitions("{\"x\":{\"type\":\"number\"}}"),
    Some(funded_value_cursor("{\"x\":7}")),
    binding_body_value_limits(),
  ).unwrap()
  let original = binding_body_prefix(owner)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((14033L, 14051L)),
  )
  let sibling = @resources.reserve_capacity(ledger, 5800L, 5800L).unwrap()
  // Only the32-byte original declaration Option is new. Regrowing the old
  //344-byte completed inventory scratch would incorrectly refuse this entry.
  prepare_parameter_binding_selection(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((14065L, 14083L)),
  )
  assert_eq(
    @parameters.binding_read_phase(original),
    @parameters.BindingPreflight,
  )
  @resources.settle_capacity(ledger, sibling).unwrap()
  clear_parameter_binding_preparation(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((14065L, 14083L)),
  )
}

///|
test "actual supplied binding Value waits one byte short then reuses original source facts and quote" {
  assert_eq(parameter_binding_initial_bytes, 10592L)
  let definitions = binding_body_definitions(
    "{\"x\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}",
  )
  let rows = Array::makei(100, i => i.to_string())
  let supplied = funded_value_cursor("{\"x\":[" + rows.join(",") + "]}")
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 200000L,
    execution_bytes: 200018L,
  }).unwrap()
  let input = ["same original supplied Value"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_binding_preparation(
    capacity,
    input,
    definitions,
    Some(supplied),
    binding_body_value_limits(),
  ).unwrap()
  let original = binding_body_prefix(owner)
  let work = @parameters.binding_read_construction_work(original)
  let current = @parameters.binding_read_current_construction(original)
  prepare_parameter_binding_selection(owner).unwrap()
  prepare_parameter_binding_preflight(owner).unwrap()
  assert_eq(
    parameter_binding_step_construction_bytes(
      original,
      @parameters.BindingValue,
    ),
    Some((6904L, 29024L)),
  )
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_eq(before, (25409L, 25427L))
  let sibling = @resources.reserve_capacity(ledger, 150008L, 150008L).unwrap()
  assert_true(
    prepare_parameter_binding_value(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_eq(@parameters.binding_read_phase(original), @parameters.BindingValue)
  assert_true(physical_equal(current, owner.current))
  assert_true(
    physical_equal(
      current,
      @parameters.binding_read_current_construction(original),
    ),
  )
  assert_true(
    physical_equal(work, @parameters.binding_read_construction_work(original)),
  )
  let quote = owner.quote.unwrap()
  assert_eq(quote, (49993L, 50011L))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(before),
  )
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_binding_value(owner).unwrap()
  assert_true(physical_equal(quote, owner.quote.unwrap()))
  let result = @parameters.finish_binding_read(original)
  assert_true(physical_equal(result, @parameters.finish_binding_read(original)))
  guard result.unwrap() is @parameters.Ready(values) else {
    fail("original supplied Array")
  }
  let value = @parameters.bound_value_at(values, 0).unwrap()
  assert_true(value.origin is @parameters.Supplied)
  guard value.value.value is @admitted.Array(items) else {
    fail("original Array")
  }
  assert_eq(@admitted.element_count(items), 100)
  reconcile_parameter_bindings(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((20969L, 20987L)),
  )
  clear_parameter_binding_preparation(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((20969L, 20987L)),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq((usage.attempts, usage.live_reservations), (0, 1))
}

///|
test "funded binding mixed supplied explicit NULL and original int64 default use one inventory receipt" {
  let definitions = binding_body_definitions(
    "{\"a\":{\"type\":\"number\"},\"s\":{\"type\":\"string\",\"nullable\":true,\"default\":\"fallback\"},\"z\":{\"type\":\"int64\",\"default\":\"9007199254740993\"}}",
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 1000000L,
    execution_bytes: 1000018L,
  }).unwrap()
  let input = ["same three original bindings"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_binding_preparation(
    capacity,
    input,
    definitions,
    Some(funded_value_cursor("{\"a\":7,\"s\":null}")),
    binding_body_value_limits(),
  ).unwrap()
  let original = binding_body_prefix(owner)
  assert_true(
    @resources.begin_preparation_phase_work64(
      capacity,
      input,
      @resources.ParameterBindingBodyInventory,
      0L,
    )
    is Err(@resources.AlreadyClaimed),
  )
  assert_true(prepare_parameter_binding_inventory(owner) is Err(WrongPhase))
  guard finish_funded_binding_body(owner, original).unwrap()
    is @parameters.Ready(values) else {
    fail("all original bindings")
  }
  assert_true(
    physical_equal(@parameters.bound_declarations(values), definitions),
  )
  assert_eq(@parameters.bound_value_count(values), 3)
  assert_true(
    @parameters.bound_value_at(values, 1).unwrap().value.value is @admitted.Null,
  )
  let default = @parameters.bound_value_at(values, 2).unwrap()
  assert_true(default.origin is @parameters.Default)
  assert_true(default.value.value is @admitted.Signed64(9007199254740993L))
  reconcile_parameter_bindings(owner).unwrap()
  clear_parameter_binding_preparation(owner).unwrap()
}

///|
test "funded binding keeps missing later invalid and cached-default budget refusal backing" {
  for
    (decls, supplied, text_limit, is_default) in [
      (
        "{\"a\":{\"type\":\"number\"},\"z\":{\"type\":\"number\",\"integer\":true}}",
        Some("{\"z\":1.5}"),
        100000,
        false,
      ),
      ("{\"x\":{\"type\":\"string\",\"default\":\"long\"}}", None, 1, true),
    ] {
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 1000000L,
      execution_bytes: 1000018L,
    }).unwrap()
    let input = ["original refusal"]
    let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      73L,
      91L,
      max_borrowers=1,
    ).unwrap()
    let owner = begin_parameter_binding_preparation(
      capacity,
      input,
      binding_body_definitions(decls),
      supplied.map(funded_value_cursor),
      { max_nodes: 1000, max_depth: 10, max_text_bytes: text_limit, },
    ).unwrap()
    let original = binding_body_prefix(owner)
    let result = finish_funded_binding_body(owner, original)
    if is_default {
      guard result
        is Err(
          @parameters.BindingInput(
            @parameters.Default,
            @parameters.ParameterIssue(kind, path~, ..)
          )
        ) else {
        fail("original default refusal")
      }
      assert_eq(kind, @parameters.BudgetExceeded)
      assert_eq(path, [@source.Key("x"), @source.Key("default")])
    } else {
      assert_true(
        result
        is Err(
          @parameters.BindingInput(
            @parameters.Supplied,
            @parameters.ParameterIssue(@parameters.NumericConstraint, ..)
          )
        ),
      )
    }
    assert_true(reconcile_parameter_bindings(owner) is Err(WrongPhase))
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    )
    clear_parameter_binding_preparation(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      before,
    )
  }
}

///|
test "funded missing original names reconcile only complete unready result with spent usage" {
  let definitions = binding_body_definitions(
    "{\"a\":{\"type\":\"number\"},\"z\":{\"type\":\"number\"}}",
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 1000000L,
    execution_bytes: 1000018L,
  }).unwrap()
  let input = ["unready original bindings"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_binding_preparation(
    capacity,
    input,
    definitions,
    Some(funded_value_cursor("{\"z\":7}")),
    binding_body_value_limits(),
  ).unwrap()
  let original = binding_body_prefix(owner)
  assert_true(reconcile_parameter_bindings(owner) is Err(WrongPhase))
  let result = finish_funded_binding_body(owner, original).unwrap()
  guard result is @parameters.NeedsBindings(missing) else {
    fail("original missing inventory")
  }
  assert_eq(@parameters.missing_count(missing), 1)
  assert_true(
    physical_equal(
      @parameters.missing_at(missing, 0).unwrap(),
      @parameters.declaration_at(definitions, 0).unwrap(),
    ),
  )
  assert_eq(@parameters.binding_usage(result), (1, 1))
  reconcile_parameter_bindings(owner).unwrap()
  clear_parameter_binding_preparation(owner).unwrap()
}
