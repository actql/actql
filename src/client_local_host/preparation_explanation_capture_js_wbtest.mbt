///|
// Actual original Node Resource and Request compiler/Plan adoption. The
// component setup supplies its own physical input/module backing; it is not a
// packed ordinary Host or Journal/Store ACK acceptance fixture.
fn original_explanation_capture_fixture(
  current? : () -> Bool = () => true,
  text? : String = request_check_wire,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientInstalledManagedRun,
  @publication_host.PreparedClientProgram,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
) raise {
  let (parent, input, prepared) = request_program_body_fixture(current~, text~)
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "first-original-explanation",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let artifact = installed_managed_run_compilation_original(run, prepared).unwrap()
  let compiled = match artifact {
    Values(value) =>
      @publication_host.issue_client_values_compiled_run(
        prepared,
        value,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Tasks(value) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        value,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Effects(_) => fail("original pure fixture unexpectedly became Effectful")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "explanation-component", "same-original-run", "2026-11-18T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (parent, run, prepared, compiled, definition)
}

///|
test "first Facts capture borrows SAME adopted preparation and retains original Plan through disposal" {
  let calls = Ref(0)
  let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture(current=() => {
      calls.val += 1
      true
    },
  )
  let before = @resources.ledger_usage(parent.ledger)
  let observations = calls.val
  let capture = capture_installed_managed_run_explanation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  assert_true(calls.val > observations)
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, before.live_reservations)
  assert_true(usage.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(usage.reserved_execution_bytes > before.reserved_execution_bytes)
  let (plan, facts) = installed_original_explanation_capture_wires(capture).unwrap()
  assert_eq(
    plan,
    @publication_host.client_compiled_run_static_plan_view(
      compiled, prepared, 65536, 8192, 64,
    ).unwrap(),
  )
  assert_true(
    @publication.parse_interactive_run_control_shape(
      "explanation_facts", facts, 65536, 8192, 64,
    )
    is Ok(_),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    installed_original_explanation_capture_wires(capture)
    is Err(ForeignOriginal),
  )
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  // End this component's borrowed-output lifetime. This is not a fake Store
  // ACK: the test never opened a Journal or claimed durable publication.
  return_installed_original_explanation_capture(capture).unwrap() |> ignore
  assert_true(
    capture.original is None &&
    capture.plan_view is None &&
    capture.facts is None,
  )
  assert_eq(return_installed_original_explanation_capture(capture), Ok(false))
  retire_installed_managed_run(run).unwrap()
  let closed = @resources.ledger_usage(parent.ledger)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_eq(closed.live_reservations, 0)
}

///|
test "first Facts preconstructor exact control quote refuses each one-byte-short original budget" {
  for retention in [true, false] {
    let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture()
    let holder = managed_run_publication_body(run, prepared).unwrap()
    let (r, e) = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
    let controls = explanation_capture_entry_control_bytes
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - r - controls + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - e - controls + 1L
      },
    ).unwrap()
    let result = capture_installed_managed_run_explanation(
      run, prepared, compiled, definition, 65536, 8192, 64,
    )
    if retention {
      assert_true(result is Err(Capacity(Resource(RetentionLimit))))
    } else {
      assert_true(result is Err(Capacity(Resource(ExecutionLimit))))
    }
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(holder),
      Ok((r, e)),
    )
    assert_true(
      installed_managed_run_compilation_original(run, prepared) is Some(_),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap() |> ignore
    retire_installed_managed_run(run).unwrap()
    let closed = @resources.ledger_usage(parent.ledger)
    assert_eq(closed.live_reservations, 0)
    assert_eq(closed.reserved_retention_bytes, 0L)
    assert_eq(closed.reserved_execution_bytes, 0L)
  }
}

///|
test "first Facts capture fences SAME Run reentry during the original sibling current callback" {
  let selected : Ref[
    (
      ClientInstalledManagedRun,
      @publication_host.PreparedClientProgram,
      @publication_host.ClientCompiledRun,
      @publication.PublicationContract,
    )?,
  ] = Ref(None)
  let armed = Ref(false)
  let attempts = Ref(0)
  let nested_failure : Ref[ClientOriginalExplanationCaptureIssue?] = Ref(None)
  let nested_capture : Ref[ClientOriginalExplanationCapture?] = Ref(None)
  let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture(current=() => {
      // The original body's extents are unavailable inside the lower resize
      // transition, but available during sibling acquisition's current call.
      // Select that semantic window, not a callback ordinal. This DATA read
      // supplies neither a new capacity grant nor a product-only test port.
      if armed.val &&
        selected.val is Some((run, prepared, compiled, definition)) &&
        managed_run_publication_body(run, prepared) is Ok(holder) &&
        @resources.preparation_body_borrow_reserved_extents(holder) is Ok(_) {
        armed.val = false
        attempts.val += 1
        match
          capture_installed_managed_run_explanation(
            run, prepared, compiled, definition, 65536, 8192, 64,
          ) {
          Err(issue) => nested_failure.val = Some(issue)
          Ok(value) => nested_capture.val = Some(value)
        }
      }
      true
    },
  )
  selected.val = Some((run, prepared, compiled, definition))
  armed.val = true
  let outcome = capture_installed_managed_run_explanation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  )
  armed.val = false
  // Dispose both possible outputs even on the original red product. Neither
  // an assertion nor a duplicate constructor is allowed to orphan a loan.
  if nested_capture.val is Some(value) {
    return_installed_original_explanation_capture(value).unwrap() |> ignore
  }
  if outcome is Ok(value) {
    return_installed_original_explanation_capture(value).unwrap() |> ignore
  }
  retire_installed_managed_run(run).unwrap()
  let closed = @resources.ledger_usage(parent.ledger)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_eq(attempts.val, 1)
  assert_eq(nested_failure.val, Some(Capacity(WorkActive)))
  assert_true(nested_capture.val is None)
  assert_true(outcome is Ok(_))
}

///|
test "captured Facts delivery reobserves SAME current before exposing borrowed wires" {
  let live = Ref(true)
  let calls = Ref(0)
  let (_, run, prepared, compiled, definition) = original_explanation_capture_fixture(current=() => {
      calls.val += 1
      live.val
    },
  )
  let capture = capture_installed_managed_run_explanation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  let before = calls.val
  live.val = false
  let refused = match installed_original_explanation_capture_wires(capture) {
    Err(Capacity(Resource(ClosedReservation))) => true
    _ => false
  }
  let observations = calls.val - before
  return_installed_original_explanation_capture(capture).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(observations, 1)
  assert_true(refused)
}

///|
test "optional Facts late quote refusal restores working debit and preserves the original module" {
  let (parent, input, prepared) = request_program_body_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let provider_calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    provider_calls.val += 1
    []
  }
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let spent = parent.program_artifact_work_spent
  let limits = @resources.ledger_limits(parent.ledger)
  let entry = explanation_capture_entry_control_bytes +
    request_original_explanation_control_bytes
  // The complete fixed entry fits; the subsequent measurement quotation
  // does not. This exercises disposal/reconciliation of an admitted prefix,
  // rather than only a first-grow refusal that never changed the reservation.
  let pressure = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - before.0 - entry,
    0L,
  ).unwrap()
  assert_true(
    prepare_request_original_explanation(parent, input, 65536, 8192, 64).unwrap()
    is None,
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_eq(provider_calls.val, 0)
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  assert_true(
    physical_equal(
      parent.program_source_free.unwrap().compilation.unwrap(),
      artifact,
    ),
  )
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_eq(provider_calls.val, 1)
  // The pressure selects the optional constructor's boundary, not the later
  // original Run-adoption metadata budget. The old module has already fitted
  // under that pressure with its unchanged working debit and compiler.
  @resources.settle_capacity(parent.ledger, pressure).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "optional-original-no-facts",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "working original Facts loan survives body completion and keeps same Request retirement pending" {
  let (parent, input, prepared) = request_program_body_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let factory = (_ : @execution.ExecutionCapacity) => []
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let loan = prepare_request_original_explanation(
      parent, input, 65536, 8192, 64,
    )
    .unwrap()
    .unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(loan.holder.unwrap()).unwrap(),
      prepared,
    ),
  )
  assert_true(physical_equal(loan.original.unwrap().3, artifact))
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  assert_true(abort_request_preparation_after_cleanup(parent) is Err(_))
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  assert_true(return_request_original_explanation(loan).unwrap())
  assert_false(return_request_original_explanation(loan).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "pre-admitted Facts move once through SAME owner Run adoption without growing its reservation" {
  let (parent, input, prepared) = request_program_body_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let factory = (_ : @execution.ExecutionCapacity) => []
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let loan = prepare_request_original_explanation(
      parent, input, 65536, 8192, 64,
    )
    .unwrap()
    .unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "pre-admitted-original-facts",
  ).unwrap()
  let (foreign_parent, foreign_input, foreign_prepared) = request_program_body_fixture()
  prepare_request_program_module_body(
    foreign_parent,
    foreign_input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let foreign_request = @publication_host.prepare_source_free_client_request_identity(
    foreign_prepared,
    "sha256:" + "a".repeat(64),
    "foreign-original-facts-owner",
  ).unwrap()
  assert_true(
    begin_request_program_managed_run_with_explanation(
      foreign_parent, foreign_request, loan,
    )
    is Err(ForeignOriginal),
  )
  abort_request_preparation_after_cleanup(foreign_parent).unwrap()
  let run = begin_request_program_managed_run_with_explanation(
    parent, request, loan,
  ).unwrap()
  assert_true(
    begin_request_program_managed_run_with_explanation(parent, request, loan)
    is Err(ForeignOriginal),
  )
  let compiled = match artifact {
    Values(value) =>
      @publication_host.issue_client_values_compiled_run(
        prepared,
        value,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Tasks(value) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        value,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Effects(_) => fail("expected original pure compiler")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "explanation-component", "same-original-run", "2026-11-18T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let capture = capture_request_original_explanation(loan, compiled, definition).unwrap()
  let after = @resources.ledger_usage(parent.ledger)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_false(return_request_original_explanation(loan).unwrap())
  assert_true(
    capture_request_original_explanation(loan, compiled, definition)
    is Err(ForeignOriginal),
  )
  let (plan, facts) = installed_original_explanation_capture_wires(capture).unwrap()
  assert_eq(
    plan,
    @publication_host.client_compiled_run_static_plan_view(
      compiled, prepared, 65536, 8192, 64,
    ).unwrap(),
  )
  assert_true(
    @publication.parse_interactive_run_control_shape(
      "explanation_facts", facts, 65536, 8192, 64,
    )
    is Ok(_),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  return_installed_original_explanation_capture(capture).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "optional Facts current loss remains a typed admission failure rather than missing metadata" {
  let armed = Ref(false)
  let (parent, input, _) = request_program_body_fixture(current=() => !armed.val)
  prepare_request_program_compilation(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  |> ignore
  armed.val = true
  assert_true(
    prepare_request_original_explanation(parent, input, 65536, 8192, 64)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  assert_true(parent.program_source_free is None)
  armed.val = false
  abort_request_preparation_after_cleanup(parent).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "optional Node wrapper entry is backed before any admitted measuring prefix" {
  let observed : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let watching = Ref(false)
  let peak = Ref(0L)
  let (parent, input, _) = request_program_body_fixture(current=() => {
    if watching.val && observed.val is Some(parent) {
      peak.val = Int64::max(
        peak.val,
        @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      )
    }
    true
  })
  observed.val = Some(parent)
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let limits = @resources.ledger_limits(parent.ledger)
  // Independent shared H16/R8/W8 tariff: Core token400 plus the explicitly
  // counted Node wrappers992. Leave one byte short of this whole fixed entry.
  let entry = explanation_capture_entry_control_bytes + 1392L
  let pressure = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - before.reserved_retention_bytes - entry + 1L,
    0L,
  ).unwrap()
  let pressured = @resources.ledger_usage(parent.ledger)
  peak.val = pressured.reserved_retention_bytes
  watching.val = true
  assert_true(
    prepare_request_original_explanation(parent, input, 65536, 8192, 64).unwrap()
    is None,
  )
  watching.val = false
  assert_eq(
    peak.val,
    pressured.reserved_retention_bytes,
    msg="no measuring prefix may obtain backing before the entire Node/Core entry fits",
  )
  assert_eq(@resources.ledger_usage(parent.ledger), pressured)
  assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
  @resources.settle_capacity(parent.ledger, pressure).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "static Request Plan read uses its admitted original without module provider or Run" {
  let (parent, input, prepared) = request_program_body_fixture()
  let provider_calls = Ref(0)
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      provider_calls.val += 1
      []
    },
  ).unwrap()
  let spent = parent.program_artifact_work_spent
  let loan = prepare_request_original_explanation(
      parent, input, 65536, 8192, 64,
    )
    .unwrap()
    .unwrap()
  let held = @resources.ledger_usage(parent.ledger)
  let wire = request_original_static_plan_wire(loan).unwrap()
  assert_true(wire.contains("\"version\":\"actql-plan-view/0.1\""), msg=wire)
  assert_true(wire.contains("\"observation\":\"static\""), msg=wire)
  assert_true(wire.contains("\"provider_io\":0"), msg=wire)
  assert_true(physical_equal(parent.compiled_program.unwrap(), prepared))
  assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_true(parent.phase == ProgramPlanReserved)
  assert_true(parent.program_source_free is None)
  assert_eq(provider_calls.val, 0)
  assert_eq(@resources.ledger_usage(parent.ledger), held)
  return_request_original_explanation(loan).unwrap() |> ignore
  assert_true(request_original_static_plan_wire(loan) is Err(ForeignOriginal))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static Request Plan read refuses retired original before projection" {
  let live = Ref(true)
  let provider_calls = Ref(0)
  let (parent, input, _) = request_program_body_fixture(current=() => live.val)
  prepare_request_program_compilation(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      provider_calls.val += 1
      []
    },
  ).unwrap()
  |> ignore
  let loan = prepare_request_original_explanation(
      parent, input, 65536, 8192, 64,
    )
    .unwrap()
    .unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  live.val = false
  match request_original_static_plan_wire(loan) {
    Err(Capacity(Resource(@resources.ClosedReservation))) => ()
    Err(issue) => fail(@debug.to_string(issue))
    Ok(_) => fail("Retired original unexpectedly produced a static Plan")
  }
  assert_true(parent.phase == ProgramPlanReserved)
  assert_true(parent.program_source_free is None)
  assert_eq(provider_calls.val, 0)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  live.val = true
  return_request_original_explanation(loan).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
