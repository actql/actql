///|
// Actual original Node Resource admission and original Source/Check controllers.
// The fixture supplies no SDK snapshot, Account, provider or physical backing.
let request_check_wire : String =
  #|{"version":"actql/0.1","id":"request-check","stages":[{"id":"a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"v"}],"results":{"r":{"from":"v","fields":["id"]}}},{"id":"b","inputs":{"rows":{"result":{"stage":"a","result":"r"}}},"steps":[{"take":1,"as":"t"}],"results":{"r":{"from":"t","fields":["id"]}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}

///|
fn request_check_source(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  text? : String = request_check_wire,
) -> ClientProgramJsonPreparation[Array[Int], Unit] raise {
  let source = prepare_request_program_json_preparation(
    parent,
    input,
    text,
    @publication_host.client_standard_program_preparation_limits().checking.input,
  ).unwrap()
  for _ in 0..<(text.length() + 1) {
    match advance_program_json_preparation(source, 64).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(_, ..) => break
      @source.JsonSourceFailed(_, ..) => fail("original Source refused")
    }
  }
  finish_program_json_preparation(source).unwrap()
  construct_program_json_preparation(source).unwrap()
  reconcile_program_json_preparation_structure(source).unwrap()
  source
}

///|
fn request_check_fixture() -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramJsonPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let source = request_check_source(parent, input)
  // Explicit already-backed Source isolates the Check holder's fixed debit.
  // The distinct normal-entry cases exercise the combined Parameter phase.
  let checking = @publication_host.client_standard_program_preparation_limits().checking.compilation
  parent.parameter_source = Some(
    @stages.prepare(source.program.unwrap(), {
      max_parameters: checking.structure.parameters,
      max_nodes: checking.traversal.nodes,
      max_depth: checking.traversal.depth,
      max_text_bytes: checking.traversal.text_bytes,
    }).unwrap(),
  )
  parent.phase = ProgramJson
  (parent, source, input)
}

///|
test "request Check parent keeps the exact Source Program and later child on one original capacity" {
  let (parent, source, input) = request_check_fixture()
  let program = source.program.unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    catalog_domain_environment(),
    None,
    [],
    @publication_host.client_standard_program_preparation_limits().checking,
  ).unwrap()
  assert_true(physical_equal(child.capacity, parent.capacity))
  assert_true(physical_equal(child.input.unwrap(), input))
  assert_true(physical_equal(child.arguments.unwrap().program, program))
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  assert_true(source.phase == Transferred && parent.phase == ProgramCheck)
  assert_eq(child.base_retained, before.reserved_retention_bytes)
  assert_eq(child.base_execution, before.reserved_execution_bytes)
  let after = @resources.ledger_usage(parent.ledger)
  // Independent quote controls1288H637R2577W plus driver36H60R57W.
  // The driver includes the one original Source target-tuple reference.
  assert_eq(16L * 1328L + 8L * 699L + 8L * 2640L, 47960L)
  assert_eq(
    after.reserved_retention_bytes,
    before.reserved_retention_bytes + 47960L,
  )
  assert_eq(
    after.reserved_execution_bytes,
    before.reserved_execution_bytes + 47960L,
  )
  assert_true(
    prepare_request_program_check_preparation(
      parent,
      input,
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    )
    is Err(WrongPhase),
  )
  // Exercise the original binder and Catalog constructor, not only a link.
  prepare_program_check_input(child).unwrap()
  assert_true(physical_equal(child.check_input.unwrap().program, program))
  prepare_program_check_prelude(child).unwrap() |> ignore
  prepare_program_check_registry(child).unwrap() |> ignore
  let spent = @resources.ledger_usage(parent.ledger)
  // No downstream output was taken; all fixture borrows end at this boundary.
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(child.phase == Retired && parent.phase == Closed)
  assert_true(parent.held_program is None && parent.program_check is None)
  assert_true(parent.program_json is None && child.arguments is None)
  let closed = @resources.ledger_usage(parent.ledger)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_eq(closed.planning_work, spent.planning_work)
  assert_eq(closed.live_reservations, 0)
}

///|
test "request Check parent failed grow retains its exact taken Program and original cleanup" {
  for retention in [true, false] {
    let (parent, source, input) = request_check_fixture()
    let program = source.program.unwrap()
    let before = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.reserved_retention_bytes - 47960L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.reserved_execution_bytes - 47960L + 1L
      },
    ).unwrap()
    let held = @resources.ledger_usage(parent.ledger)
    let result = prepare_request_program_check_preparation(
      parent,
      input,
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    )
    assert_true(
      if retention {
        result is Err(ProgramCheck(Capacity(Resource(RetentionLimit))))
      } else {
        result is Err(ProgramCheck(Capacity(Resource(ExecutionLimit))))
      },
    )
    assert_true(
      parent.phase == ProgramCheckFailed && parent.program_check is None,
    )
    assert_true(source.phase == Transferred)
    assert_true(physical_equal(parent.held_program.unwrap(), program))
    assert_eq(@resources.ledger_usage(parent.ledger), held)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_true(parent.phase == Closed && parent.held_program is None)
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "request Check parent refuses foreign input busy Source and unregistered transfer" {
  let (parent, source, input) = request_check_fixture()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_program_check_preparation(
      parent,
      [1],
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    )
    is Err(ForeignOriginal),
  )
  source.busy = true
  assert_true(
    prepare_request_program_check_preparation(
      parent,
      input,
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    )
    is Err(ProgramJson(WrongPhase)),
  )
  assert_true(parent.phase == ProgramJson && parent.held_program is None)
  source.busy = false
  {
    let program = take_program_json_preparation_program(source).unwrap()
    clear_program_json_preparation(source).unwrap()
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    assert_true(parent.held_program is None)
    assert_eq(program.id, "request-check")
    assert_eq(@resources.ledger_usage(parent.ledger), before)
  }
  // Explicit component teardown after the unregistered lexical borrow ends;
  // this is not a production next-consumer ACK or a new cleanup port.
  request_handoff_fixture_cleanup(parent, input)
}

///|
test "request Check parent fences reentry and retains Program before the later current callback" {
  let input = [1]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let calls = Ref(0)
  let seen = Ref(false)
  let fenced = Ref(0)
  let initial = request_parent_fixture(input, current=() => {
    if armed.val {
      calls.val = calls.val + 1
      let parent = selected.val.unwrap()
      if parent.phase == Selecting &&
        abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) &&
        prepare_request_program_check_preparation(
          parent,
          input,
          catalog_domain_environment(),
          None,
          [],
          @publication_host.client_standard_program_preparation_limits().checking,
        )
        is Err(WrongPhase) {
        fenced.val += 1
      }
      if calls.val == 2 {
        seen.val = parent.held_program is Some(_) &&
          parent.program_json.unwrap().phase == Transferred &&
          parent.program_check is None
      }
    }
    true
  })
  let parent = begin_request_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(parent)
  let source = request_check_source(parent, input)
  let checking = @publication_host.client_standard_program_preparation_limits().checking.compilation
  parent.parameter_source = Some(
    @stages.prepare(source.program.unwrap(), {
      max_parameters: checking.structure.parameters,
      max_nodes: checking.traversal.nodes,
      max_depth: checking.traversal.depth,
      max_text_bytes: checking.traversal.text_bytes,
    }).unwrap(),
  )
  parent.phase = ProgramJson
  armed.val = true
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    catalog_domain_environment(),
    None,
    [],
    @publication_host.client_standard_program_preparation_limits().checking,
  ).unwrap()
  armed.val = false
  // Source take and later grow each keep their own original current boundary.
  assert_eq(calls.val, 2)
  assert_eq(fenced.val, 2)
  assert_true(seen.val && physical_equal(parent.program_check.unwrap(), child))
  child.busy = true
  let held = @resources.ledger_usage(parent.ledger)
  assert_true(
    abort_request_preparation_after_cleanup(parent)
    is Err(ProgramCheck(WrongPhase)),
  )
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  assert_true(parent.held_program is Some(_))
  assert_eq(@resources.ledger_usage(parent.ledger), held)
  child.busy = false
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "request Check parent transferred output stays fenced after controller DATA clear" {
  let (parent, _, input) = request_check_fixture()
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    catalog_domain_environment(),
    None,
    [],
    @publication_host.client_standard_program_preparation_limits().checking,
  ).unwrap()
  prepare_program_check_input(child).unwrap()
  {
    let output = take_program_check_input(child).unwrap()
    let held = @resources.ledger_usage(parent.ledger)
    clear_program_check_preparation(child).unwrap()
    clear_program_check_preparation(child).unwrap()
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    assert_true(physical_equal(parent.program_check.unwrap(), child))
    assert_eq(@resources.ledger_usage(parent.ledger), held)
    assert_true(physical_equal(output.program, parent.held_program.unwrap()))
  }
  request_handoff_fixture_cleanup(parent, input)
}
