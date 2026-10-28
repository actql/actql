///|
fn request_program_body_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
) raise {
  let (parent, child, _, input) = registration_parent_fixture(current~)
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("original Request must finish its supported check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  (parent, input, prepared)
}

///|
fn request_program_installed_plan(
  prepared : @publication_host.PreparedClientProgram,
) -> ClientInstalledManagedSourceFreePreparation {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  // Existing actual installed sequence/Plan/configuration constructors. Empty
  // providers are an explicit component port, not physical backend acceptance.
  prepare_installed_managed_source_free_with_contracts(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
}

///|
test "actual Request continues original compiler to the same typed reservation and preserves work history" {
  let calls = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let flags = Ref(0)
  let (parent, child, _, input) = registration_parent_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    true
  })
  finish_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let old = parent.capacity
  let ledger_before = @resources.ledger_usage(parent.ledger)
  action.val = Some(() => {
    if continue_request_program_preparation(parent, input) is Err(WrongPhase) {
      flags.val += 1
    }
    if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_compilation_preparation(child) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let before = calls.val
  let taken = continue_request_program_preparation(parent, input).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  assert_true(physical_equal(taken, prepared))
  assert_eq(@resources.ledger_usage(parent.ledger), ledger_before)
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(old, input)
    is Err(ForeignOriginal),
  )
  let next = parent.program_capacity.unwrap()
  assert_true(
    @resources.begin_preparation_phase_work64(
      next,
      input,
      @resources.LowerAndGraph,
      0L,
    )
    is Err(AlreadyClaimed),
  )
  assert_true(parent.program_json is None && parent.program_check is None)
  assert_true(
    child.compiled_program is None &&
    child.input is None &&
    child.phase == Transferred,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.phase == Closed && parent.program_capacity is None)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "actual Request Plan grow caches its original quote and preserves both one-byte-short boundaries" {
  for retention in [true, false] {
    let (parent, input, _) = request_program_body_fixture()
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1
      },
    ).unwrap()
    assert_true(reserve_request_program_plan(parent, input) is Err(Capacity(_)))
    let quote = parent.program_plan_quote.unwrap()
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - quote.0 + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - quote.1 + 1L
      },
    ).unwrap()
    let result = reserve_request_program_plan(parent, input)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_eq(parent.program_plan_quote, Some(quote))
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(before),
    )
    @resources.settle_capacity(parent.ledger, short).unwrap()
    reserve_request_program_plan(parent, input).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(quote),
    )
    assert_true(reserve_request_program_plan(parent, input) is Err(WrongPhase))
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "actual Request keeps the original body and reservation while a manager borrow delays cleanup" {
  let (parent, input, prepared) = request_program_body_fixture()
  reserve_request_program_plan(parent, input).unwrap()
  let plan = request_program_installed_plan(prepared)
  let (other, other_input, foreign) = request_program_body_fixture()
  reserve_request_program_plan(other, other_input).unwrap()
  let foreign_plan = request_program_installed_plan(foreign)
  assert_true(
    complete_request_program_preparation(parent, input, foreign_plan)
    is Err(WrongPhase),
  )
  assert_true(
    parent.program_source_free is None && !parent.program_body_attempted,
  )
  abort_request_preparation_after_cleanup(other).unwrap()
  complete_request_program_preparation(parent, input, plan).unwrap()
  let holder = borrow_request_program_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(
    parent.phase == Retiring &&
    parent.compiled_program is None &&
    parent.program_source_free is None,
  )
  assert_true(@resources.preparation_body_retirement_started(holder))
  assert_true(borrow_request_program_preparation(parent) is Err(WrongPhase))
  assert_eq(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "actual Request adopts its same prepared body Plan and initial admission into the existing managed Run" {
  let (parent, input, prepared) = request_program_body_fixture()
  reserve_request_program_plan(parent, input).unwrap()
  let plan = request_program_installed_plan(prepared)
  complete_request_program_preparation(parent, input, plan).unwrap()
  let holder = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-request-owned-run",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(
    parent.phase == Selected &&
    parent.input is None &&
    parent.compiled_program is None &&
    parent.program_capacity is None &&
    parent.held_program is None,
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(
    begin_request_program_managed_run(parent, request) is Err(ForeignOriginal),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.preparation_body_retirement_started(holder))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "one actual Request Run adoption observes original external current once for its synchronous handoff" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_program_body_fixture(current=() => {
    calls.val += 1
    true
  })
  reserve_request_program_plan(parent, input).unwrap()
  let plan = request_program_installed_plan(prepared)
  complete_request_program_preparation(parent, input, plan).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "b".repeat(64),
    "same-request-current-count",
  ).unwrap()
  let before = calls.val
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let observed = calls.val - before
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(observed, 1)
}

///|
test "retained original dimensions keep a large scalar literal and long projection Pipe independent of row width" {
  let steps : Array[String] = []
  for i in 0..<128 {
    steps.push("{\"select\":[\"id\"],\"as\":\"p" + i.to_string() + "\"}")
  }
  let text = request_check_wire
    .replace(old="\"type\":\"number\"", new="\"type\":\"string\"")
    .replace(
      old="\"rows\":[]",
      new="\"rows\":[{\"id\":\"" + "x".repeat(60000) + "\"}]",
    )
    .replace(old="{\"take\":1,\"as\":\"t\"}", new=steps.join(","))
    .replace(old="\"from\":\"t\"", new="\"from\":\"p127\"")
  let (parent, child, _, input) = registration_parent_fixture(text~)
  let program = parent.held_program.unwrap()
  let retained = @syntax.program_preparation_data(program)
  assert_eq(retained.operations, 129)
  assert_eq(retained.initial_fields, 1)
  assert_eq(retained.projected_fields, 1)
  assert_eq(retained.possible_growth, 0)
  assert_eq(retained.external_inputs, 0)
  assert_true(
    physical_equal(retained, @syntax.program_preparation_data(program)),
  )
  assert_true(
    finish_program_check_preparation(child).unwrap() is @checked.Checked(_),
  )
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  reserve_request_program_plan(parent, input).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_true(usage.reserved_retention_bytes < 512L * 1024L * 1024L)
  assert_true(usage.reserved_execution_bytes < 512L * 1024L * 1024L)
  abort_request_preparation_after_cleanup(parent).unwrap()
}
