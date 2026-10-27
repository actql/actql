///|
test "Parameter Header grows SAME reservation before Map names and reader construction with one-short retry" {
  let root = funded_parameter_cursor("{\"x\":{\"type\":\"number\"}}")
  let limits = funded_parameter_limits()
  // Header storage37H96R56W=1808B; SAME sort16H18R36W=688B.
  // Original preflight quote9572B includes both boxed indexed Option tags.
  assert_eq(
    parameter_header_construction_bytes(Some(root), 0, limits),
    Some(2496L),
  )
  assert_eq(parameter_preflight_initial_bytes, 5152L)
  assert_true(
    parameter_declaration_quote_controls == parameter_preflight_quote_controls,
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 73L + 5152L + 9572L,
    execution_bytes: 91L + 5152L + 9572L,
  }).unwrap()
  let input = ["same original Header"]
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
    limits,
  ).unwrap()
  prepare_parameter_declaration_preflight(owner).unwrap()
  let original = parameter_declaration_preflight_outcome(owner)
  let reader = original.unwrap().0.unwrap()
  // Previous preflight scratch is still owned until its confirmed reconcile.
  assert_true(prepare_parameter_declaration_header(owner) is Err(WrongPhase))
  reconcile_parameter_declaration_preflight(owner).unwrap()
  let sibling = @resources.reserve_capacity(ledger, 7085L, 7085L).unwrap()
  assert_true(
    prepare_parameter_declaration_header(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.phase == HeaderQuoted)
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationHeader,
  )
  assert_true(@parameters.declaration_read_type_cursor(reader) is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((5225L, 5243L)),
  )
  let quoted = owner.quote.unwrap()
  assert_eq(quoted, (7721L, 7739L))
  // Only unused sibling bytes return; no work or physical attempt is refunded.
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_declaration_header(owner).unwrap()
  assert_true(physical_equal(quoted, owner.quote.unwrap()))
  assert_true(
    physical_equal(original, parameter_declaration_preflight_outcome(owner)),
  )
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationType,
  )
  assert_true(@parameters.declaration_read_pending_syntax(reader) is None)
  assert_true(@parameters.declaration_read_type_cursor(reader) is Some(_))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((7721L, 7739L)),
  )
  assert_true(prepare_parameter_declaration_header(owner) is Err(WrongPhase))
  assert_true(
    reconcile_parameter_declaration_preflight(owner) is Err(WrongPhase),
  )
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_true(parameter_declaration_preflight_outcome(owner) is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((7721L, 7739L)),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq((usage.attempts, usage.live_reservations), (0, 1))
}

///|
test "Parameter Header funds all original fields BEFORE count refusal and skips unreached sort" {
  let fields = Array::makei(32, i => {
    "\"p" + i.to_string() + "\":{\"type\":\"number\"}"
  })
  let root = funded_parameter_cursor("{" + fields.join(",") + "}")
  let limits : @parameters.DeclarationLimits = {
    max_parameters: 1,
    max_nodes: 100,
    max_depth: 3,
    max_text_bytes: 10000,
  }
  let inventory = @parameters.declaration_header_construction_inventory(
    Some(root),
    0,
    limits,
  ).unwrap()
  assert_eq(
    (
      inventory.storage.record_headers,
      inventory.storage.reference_slots,
      inventory.storage.scalar_words,
    ),
    (161L, 530L, 459L),
  )
  assert_eq(inventory.sort_fields, 0)
  assert_eq(
    parameter_header_construction_bytes(Some(root), 0, limits),
    Some(10488L),
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  }).unwrap()
  let input = ["actual32fields"]
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
    limits,
  ).unwrap()
  prepare_parameter_declaration_preflight(owner).unwrap()
  let reader = parameter_declaration_preflight_outcome(owner).unwrap().0.unwrap()
  reconcile_parameter_declaration_preflight(owner).unwrap()
  prepare_parameter_declaration_header(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((15713L, 15731L)),
  )
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationComplete,
  )
  // This getter returns the Header's original typed refusal; it does not
  // run a second declaration preflight/type/default or infer acceptance.
  guard @parameters.finish_declaration_read(reader)
    is Err(@parameters.ParameterIssue(kind, path~, span~)) else {
    fail("original Parameter count refusal")
  }
  assert_eq(kind, @parameters.ParameterLimit)
  assert_eq(path, @decode.cursor_path(root))
  assert_eq(span, @decode.cursor_span(root))
  assert_true(
    reconcile_parameter_declaration_preflight(owner) is Err(WrongPhase),
  )
}

///|
test "Parameter Header preserves absent wrong-kind and NULL child boundaries without entering Type" {
  let limits : @parameters.DeclarationLimits = {
    max_parameters: 2,
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 10000,
  }
  for
    root in [
      None,
      Some(funded_parameter_cursor("0")),
      Some(funded_parameter_cursor("{\"bad-name\":null}")),
    ] {
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 100000L,
      execution_bytes: 100000L,
    }).unwrap()
    let input = ["original header branch"]
    let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      73L,
      91L,
      max_borrowers=1,
    ).unwrap()
    let owner = begin_parameter_declaration_preflight(
      capacity, input, root, limits,
    ).unwrap()
    prepare_parameter_declaration_preflight(owner).unwrap()
    let reader = parameter_declaration_preflight_outcome(owner).unwrap().0.unwrap()
    reconcile_parameter_declaration_preflight(owner).unwrap()
    prepare_parameter_declaration_header(owner).unwrap()
    match root {
      None => {
        assert_eq(
          @resources.preparation_capacity_working_extents(capacity, input),
          Ok((6329L, 6347L)),
        )
        assert_eq(
          @parameters.declaration_count(
            @parameters.finish_declaration_read(reader).unwrap(),
          ),
          0,
        )
      }
      Some(root) =>
        if @decode.object_length(root) is None {
          guard @parameters.finish_declaration_read(reader)
            is Err(@parameters.Decode(issue)) else {
            fail("original wrong-kind Header")
          }
          assert_eq(issue.kind, @decode.WrongType)
          assert_eq(issue.path, @decode.cursor_path(root))
          assert_eq(issue.span, @decode.cursor_span(root))
        } else {
          assert_eq(
            @parameters.declaration_read_phase(reader),
            @parameters.DeclarationType,
          )
          assert_true(
            @decode.is_null(
              @parameters.declaration_read_type_cursor(reader).unwrap(),
            ),
          )
          assert_true(
            @parameters.declaration_read_pending_syntax(reader) is None,
          )
          // Type/default are NOT funded here and must not be advanced by Header.
        }
    }
    let retained = @resources.preparation_capacity_working_extents(
      capacity, input,
    )
    clear_parameter_declaration_preflight(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      retained,
    )
  }
}

///|
fn parameter_header_construction_bytes(
  root : @decode.Cursor?,
  root_path_depth : Int,
  limits : @parameters.DeclarationLimits,
) -> Int64? {
  match parameter_header_construction_split(root, root_path_depth, limits) {
    None => None
    Some((_, total)) => Some(total)
  }
}
