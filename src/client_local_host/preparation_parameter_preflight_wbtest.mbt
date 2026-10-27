///|
fn funded_parameter_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_literal(text, {
      max_input_bytes: 10000,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap().node,
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn funded_parameter_limits() -> @parameters.DeclarationLimits {
  { max_parameters: 2, max_nodes: 3, max_depth: 2, max_text_bytes: 11, }
}

///|
test "Parameter preflight grows same parent once and retains exact metadata across one-short refusal" {
  let root = funded_parameter_cursor("{\"x\":{\"type\":\"number\"}}")
  // Independent3nodes/2fields/maxKey4/wholeDepth2. Traversal19H43R17W,
  // full refusal11H32R13W, SAME NFC100H123R668W/162U =>9572 logicalB.
  // Fixed quote/driver/receipt197H70R421W =>7080 logicalB.
  assert_true(
    parameter_declaration_preflight_initial_inventory() ==
    {
      record_headers: 197L,
      reference_slots: 70L,
      scalar_words: 421L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  )
  assert_eq(parameter_preflight_initial_bytes, 7080L)
  assert_eq(
    parameter_preflight_construction_bytes(
      @decode.observe_subtree_construction_geometry(root),
      0,
      funded_parameter_limits(),
    ),
    Some(9572L),
  )
  assert_eq(program_json_initial_control_bytes, 20232L)
  let core = 16652L
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 73L + core,
    execution_bytes: 91L + core + 1L,
  }).unwrap()
  let sibling = @resources.reserve_capacity(ledger, 1L, 1L).unwrap()
  let input = ["same original"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  assert_true(
    begin_parameter_declaration_preflight(
      capacity,
      ["same original"],
      Some(root),
      funded_parameter_limits(),
    )
    is Err(Capacity(ForeignOriginal)),
  )
  let owner = begin_parameter_declaration_preflight(
    capacity,
    input,
    Some(root),
    funded_parameter_limits(),
  ).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((7153L, 7171L)),
  )
  assert_true(
    prepare_parameter_declaration_preflight(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.phase == Inspected && owner.prepared is None)
  let geometry = owner.geometry.unwrap()
  let quote = owner.quote.unwrap()
  assert_eq(geometry.work, 8L)
  assert_eq(quote, (73L + core, 91L + core))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((7153L, 7171L)),
  )
  // Return only the sibling's unused reservation. No cap or spent attempt is
  // changed, and a replayed metadata receipt would refuse AlreadyClaimed.
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_declaration_preflight(owner).unwrap()
  assert_true(physical_equal(owner.geometry.unwrap(), geometry))
  assert_true(physical_equal(owner.quote.unwrap(), quote))
  guard parameter_declaration_preflight_outcome(owner) is Some((Ok(_), n, b)) else {
    fail("original prepared preflight")
  }
  assert_eq((n, b), (3, 11))
  let first = parameter_declaration_preflight_outcome(owner)
  assert_true(
    physical_equal(first, parameter_declaration_preflight_outcome(owner)),
  )
  assert_true(prepare_parameter_declaration_preflight(owner) is Err(WrongPhase))
  reconcile_parameter_declaration_preflight(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((7153L, 7171L)),
  )
  assert_true(
    physical_equal(first, parameter_declaration_preflight_outcome(owner)),
  )
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_true(parameter_declaration_preflight_outcome(owner) is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((7153L, 7171L)),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq((usage.attempts, usage.transferred_bytes), (0, 0L))
  assert_eq(@decode.object_length(root), Some(1))
}

///|
test "funded Parameter preflight retains original partial refusal and does not clear its path as scratch" {
  let root = funded_parameter_cursor(
    "{\"x\":{\"type\":\"string\",\"default\":\"é\"}}",
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100000L,
    execution_bytes: 100000L,
  }).unwrap()
  let input = ["same original error"]
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
    { ..funded_parameter_limits(), max_text_bytes: 100, },
  ).unwrap()
  prepare_parameter_declaration_preflight(owner).unwrap()
  guard parameter_declaration_preflight_outcome(owner)
    is Some((Err(issue), n, b)) else {
    fail("original node budget refusal")
  }
  assert_true(
    issue is @parameters.ParameterIssue(@parameters.BudgetExceeded, ..),
  )
  assert_eq((n, b), (2, 1))
  let quote = @resources.preparation_capacity_working_extents(capacity, input)
  assert_true(
    reconcile_parameter_declaration_preflight(owner) is Err(WrongPhase),
  )
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    quote,
  )
  assert_true(
    issue is @parameters.ParameterIssue(@parameters.BudgetExceeded, ..),
  )
}

///|
test "Parameter constructor quote uses original node budget and exact cursor ancestry" {
  let root = funded_parameter_cursor("[" + "0,".repeat(31) + "0]")
  let limits = { ..funded_parameter_limits(), max_nodes: 1, }
  let (geometry, depth, work) = @parameters.observe_declaration_preflight_construction(
    Some(root),
    limits,
  )
  assert_eq((geometry.unwrap().nodes, depth, work), (33, 0, 36L))
  let inventory = @parameters.declaration_preflight_construction_inventory(
    geometry.unwrap(),
    depth,
    limits,
  ).unwrap()
  // Only the original one-node budget may schedule work. Original preflight
  // refuses before constructing the other32 child Cursors or detached views.
  assert_eq(
    (
      inventory.traversal.record_headers,
      inventory.traversal.reference_slots,
      inventory.traversal.scalar_words,
    ),
    (15L, 31L, 13L),
  )
  assert_eq(
    parameter_preflight_construction_bytes(geometry.unwrap(), depth, limits),
    Some(1128L),
  )
  let whole = funded_parameter_cursor(
    "{\"outside\":" +
    "[".repeat(8) +
    "0" +
    "]".repeat(8) +
    ",\"params\":{\"x\":{\"type\":\"number\"}}}",
  )
  let selected = @decode.field_at(whole, 1).unwrap().1
  let (same, depth, work) = @parameters.observe_declaration_preflight_construction(
    Some(selected),
    funded_parameter_limits(),
  )
  assert_eq((same.unwrap().nodes, depth, work), (3, 1, 10L))
  assert_true(@decode.admission_usage(selected).depth > depth + 2)
  // One real ancestor adds one path segment64logicalB, independent of the
  // unrelated eight-deep sibling. The original source backing stays borrowed.
  assert_eq(
    parameter_preflight_construction_bytes(
      same.unwrap(),
      depth,
      funded_parameter_limits(),
    ),
    Some(9636L),
  )
}

///|
test "absent and invalid Parameter preflight keep original zero usage without input walk" {
  for invalid in [false, true] {
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 100000L,
      execution_bytes: 100000L,
    }).unwrap()
    let input = ["same zero path"]
    let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      73L,
      91L,
      max_borrowers=1,
    ).unwrap()
    let root = if invalid {
      Some(funded_parameter_cursor("[" + "0,".repeat(31) + "0]"))
    } else {
      None
    }
    let limits : @parameters.DeclarationLimits = {
      max_parameters: 0,
      max_nodes: if invalid {
        -1
      } else {
        0
      },
      max_depth: 0,
      max_text_bytes: 0,
    }
    let owner = begin_parameter_declaration_preflight(
      capacity, input, root, limits,
    ).unwrap()
    prepare_parameter_declaration_preflight(owner).unwrap()
    assert_true(owner.geometry is None)
    let (result, n, b) = parameter_declaration_preflight_outcome(owner).unwrap()
    assert_eq((n, b), (0, 0))
    if invalid {
      assert_true(result is Err(@parameters.InvalidLimits))
      assert_true(
        reconcile_parameter_declaration_preflight(owner) is Err(WrongPhase),
      )
    } else {
      assert_true(result is Ok(_))
      reconcile_parameter_declaration_preflight(owner).unwrap()
    }
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((7153L, 7171L)),
    )
    clear_parameter_declaration_preflight(owner).unwrap()
  }
}
