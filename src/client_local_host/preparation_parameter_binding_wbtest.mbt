///|
fn binding_header_definitions() -> @parameters.Declarations {
  @parameters.read_declarations(
    Some(funded_parameter_cursor("{\"x\":{\"type\":\"number\"}}")),
    funded_parameter_limits(),
  ).unwrap()
}

///|
fn binding_header_limits() -> @admitted.Limits {
  { max_nodes: 1000, max_depth: 16, max_text_bytes: 10000, }
}

///|
test "binding Header ancestry uses one original work receipt before later constructors" {
  let source = funded_parameter_cursor("{\"outer\":{\"input\":{\"x\":7}}}")
  let supplied = @decode.field_at(@decode.field_at(source, 0).unwrap().1, 0).unwrap().1
  assert_eq(@decode.observe_cursor_path_depth(supplied), (2, 3L))
  let ledger = @resources.create_ledger({
    planning_work: 5,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100000L,
    execution_bytes: 100018L,
  }).unwrap()
  let input = ["one original Header metadata receipt"]
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
    binding_header_definitions(),
    Some(supplied),
    binding_header_limits(),
  ).unwrap()
  let repeated = @resources.begin_preparation_phase_work64(
    capacity,
    input,
    @resources.ParameterBindingHeaderInventory,
    0L,
  )
  let already_claimed = match repeated {
    Err(@resources.AlreadyClaimed) => true
    Ok(receipt) => {
      // Preserve finite accounting even when the original counter is red.
      @resources.finish_preparation_phase_work64(receipt).unwrap() |> ignore
      false
    }
    _ => false
  }
  assert_true(already_claimed)
  // A closed work receipt must not obstruct the original next resize.
  prepare_parameter_binding_header(owner).unwrap()
  clear_parameter_binding_preparation(owner).unwrap()
}

///|
test "binding Header waits for exact one-short SAME parent then retains original quote and reader" {
  let inventory = parameter_binding_preparation_initial_inventory()
  assert_eq(
    (
      inventory.record_headers,
      inventory.reference_slots,
      inventory.scalar_words,
    ),
    (299L, 91L, 635L),
  )
  assert_eq(parameter_binding_initial_bytes, 10592L)
  let ledger = @resources.create_ledger({
    planning_work: 5,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 20000L,
    execution_bytes: 20018L,
  }).unwrap()
  let input = ["same binding original"]
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
    binding_header_definitions(),
    Some(funded_parameter_cursor("{\"x\":7}")),
    binding_header_limits(),
  ).unwrap()
  let original = parameter_binding_preparation_outcome(owner)
  let reader = original.unwrap().unwrap()
  assert_eq(parameter_binding_header_construction_bytes(reader, 0), Some(2784L))
  let sibling = @resources.reserve_capacity(ledger, 6552L, 6552L).unwrap()
  assert_true(
    prepare_parameter_binding_header(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.phase == BindingHeaderQuoted)
  assert_eq(@parameters.binding_read_phase(reader), @parameters.BindingHeader)
  assert_true(@parameters.binding_read_pending_source(reader) is None)
  let quote = owner.quote.unwrap()
  assert_eq(quote, (13449L, 13467L))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((10665L, 10683L)),
  )
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_binding_header(owner).unwrap()
  assert_true(physical_equal(quote, owner.quote.unwrap()))
  assert_true(
    physical_equal(original, parameter_binding_preparation_outcome(owner)),
  )
  assert_eq(
    @parameters.binding_read_phase(reader),
    @parameters.BindingSelection,
  )
  assert_true(@parameters.binding_read_pending_source(reader) is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((13449L, 13467L)),
  )
  assert_true(prepare_parameter_binding_header(owner) is Err(WrongPhase))
  clear_parameter_binding_preparation(owner).unwrap()
  assert_true(parameter_binding_preparation_outcome(owner) is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((13449L, 13467L)),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq((usage.attempts, usage.live_reservations), (0, 1))
}

///|
test "binding Header funds all supplied fields and preserves known original refusal without Value work" {
  let wide = "{" +
    Array::makei(9, i => "\"k" + i.to_string() + "\":null").join(",") +
    "}"
  let supplied = funded_parameter_cursor(wide)
  let ledger = @resources.create_ledger({
    planning_work: 5,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100000L,
    execution_bytes: 100018L,
  }).unwrap()
  let input = ["original supplied9 not allowed1"]
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
    binding_header_definitions(),
    Some(supplied),
    binding_header_limits(),
  ).unwrap()
  let reader = parameter_binding_preparation_outcome(owner).unwrap().unwrap()
  assert_eq(
    parameter_binding_header_construction_bytes(reader, 0),
    Some(12056L),
  )
  prepare_parameter_binding_header(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((22721L, 22739L)),
  )
  guard @parameters.finish_binding_read(reader)
    is Err(
      @parameters.BindingInput(@parameters.Supplied, @parameters.Decode(issue))
    ) else {
    fail("original supplied unknown field")
  }
  assert_eq(issue.kind, @decode.UnknownField)
  assert_eq(issue.path, [@source.Key("k0")])
  assert_true(@parameters.binding_read_pending_source(reader) is None)
  clear_parameter_binding_preparation(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((22721L, 22739L)),
  )
}

///|
test "binding initial retains invalid limits empty completion and original foreign input fence" {
  let ledger = @resources.create_ledger({
    planning_work: 5,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100000L,
    execution_bytes: 100018L,
  }).unwrap()
  let input = ["same binding empty"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  assert_true(
    begin_parameter_binding_preparation(
      capacity,
      ["same binding empty"],
      binding_header_definitions(),
      None,
      binding_header_limits(),
    )
    is Err(Capacity(ForeignOriginal)),
  )
  let invalid = begin_parameter_binding_preparation(
    capacity,
    input,
    binding_header_definitions(),
    None,
    { ..binding_header_limits(), max_nodes: -1, },
  ).unwrap()
  assert_true(
    parameter_binding_preparation_outcome(invalid).unwrap()
    is Err(@parameters.InvalidLimits),
  )
  assert_true(prepare_parameter_binding_header(invalid) is Err(WrongPhase))
  clear_parameter_binding_preparation(invalid).unwrap()
  let definitions = @parameters.read_declarations(
    None,
    funded_parameter_limits(),
  ).unwrap()
  let owner = begin_parameter_binding_preparation(
    capacity,
    input,
    definitions,
    None,
    binding_header_limits(),
  ).unwrap()
  let reader = parameter_binding_preparation_outcome(owner).unwrap().unwrap()
  prepare_parameter_binding_header(owner).unwrap()
  assert_eq(@parameters.binding_read_phase(reader), @parameters.BindingComplete)
  let completed = @parameters.finish_binding_read(reader)
  assert_true(
    physical_equal(completed, @parameters.finish_binding_read(reader)),
  )
  guard completed.unwrap() is @parameters.Ready(values) else {
    fail("empty original bindings")
  }
  assert_eq(@parameters.bound_value_count(values), 0)
  clear_parameter_binding_preparation(owner).unwrap()
}
