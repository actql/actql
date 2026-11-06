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
let request_program_module_manifest_original : @publication_host.ClientCompilationManifests = @publication_host.admit_client_compilation_manifests(
  @environment.compiler_grammar_manifest_wire(),
  @environment.compiler_barrier_contract_manifest_wire(),
  100000,
  10000,
  100,
).unwrap()

///|
fn request_program_module_manifests() -> @publication_host.ClientCompilationManifests {
  request_program_module_manifest_original
}

///|
fn request_program_module_contracts() -> ClientInstalledSequenceContracts {
  let assets = @publication_host.client_local_product_assets()
  prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
}

///|
test "generic Request module retains its funded compilation before body and same original Run adoption" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_program_body_fixture(current=() => {
    calls.val += 1
    true
  })
  let original_capacity = parent.program_capacity.unwrap()
  let factory_calls = Ref(0)
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      factory_calls.val += 1
      []
    },
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  assert_true(plan.compilation is Some(_))
  let compilation = plan.compilation.unwrap()
  assert_true(
    physical_equal(parent.program_capacity.unwrap(), original_capacity),
  )
  assert_eq(factory_calls.val, 1)
  let borrow = borrow_request_program_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(borrow).unwrap(),
      prepared,
    ),
  )
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "funded-original-artifact",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.source_free_preparation.unwrap(), plan))
  let before = calls.val
  let observed = installed_managed_run_compilation_original(run, prepared).unwrap()
  assert_true(physical_equal(observed, compilation))
  assert_eq(calls.val, before)
  assert_true(
    installed_managed_run_compilation_original(
      run,
      @publication_host.prepare_effect_free_client_program(
        request_check_wire,
        Json,
        catalog_domain_environment(),
        None,
        @publication_host.client_standard_program_preparation_limits(),
      ).unwrap(),
    )
    is None,
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.preparation_body_borrow_value(borrow) is Some(_))
  assert_true(@resources.return_preparation_body_borrow(borrow).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_true(installed_managed_run_compilation_original(run, prepared) is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "funded artifact grow retains original module and measurement across both one-byte-short boundaries" {
  for retention in [true, false] {
    let (parent, input, prepared) = request_program_body_fixture()
    reserve_request_program_plan(parent, input).unwrap()
    let capacity = parent.program_capacity.unwrap()
    let base = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let factory_calls = Ref(0)
    let factory = _ => {
      factory_calls.val += 1
      []
    }
    let contracts = request_program_module_contracts()
    let manifests = request_program_module_manifests()
    let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
    let storage = @execution.preparation_representation_cost(
      @publication_host.prepared_client_pure_measurement_storage(
        prepared, compilation_limits,
      ).unwrap(),
    ).unwrap()
    let measurement = (base.0 + storage, base.1 + storage)
    // Admit the newly priced prior measurement, then keep this existing case
    // scoped to the later artifact grow and its original cached measurement.
    let block = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - measurement.0
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - measurement.1
      },
    ).unwrap()
    assert_true(
      prepare_request_program_module_body(
        parent,
        input,
        contracts,
        manifests~,
        compilation_limits~,
        retained_output=true,
        provider_factory=factory,
      )
      is Err(Preparation(Capacity(_))),
    )
    assert_eq(factory_calls.val, 1)
    let installed = parent.program_source_free.unwrap()
    let geometry = parent.program_artifact_geometry.unwrap()
    let quote = parent.program_artifact_quote.unwrap()
    assert_true(quote.0 > measurement.0 && quote.1 > measurement.1)
    assert_true(installed.compilation is None)
    assert_true(borrow_request_program_preparation(parent) is Err(WrongPhase))
    assert_true(
      parent.phase == ProgramPlanReserved && !parent.program_body_attempted,
    )
    @resources.settle_capacity(parent.ledger, block).unwrap()
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
    let result = prepare_request_program_module_body(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    )
    assert_true(
      if retention {
        result is Err(Preparation(Capacity(Resource(RetentionLimit))))
      } else {
        result is Err(Preparation(Capacity(Resource(ExecutionLimit))))
      },
    )
    assert_eq(factory_calls.val, 1)
    assert_true(physical_equal(parent.program_source_free.unwrap(), installed))
    assert_true(
      physical_equal(parent.program_artifact_geometry.unwrap(), geometry),
    )
    assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
    assert_eq(parent.program_artifact_quote, Some(quote))
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(measurement),
    )
    assert_true(
      prepare_request_program_module_body(
        parent,
        input,
        request_program_module_contracts(),
        manifests~,
        compilation_limits~,
        retained_output=true,
        provider_factory=factory,
      )
      is Err(Preparation(ForeignOriginal)),
    )
    assert_eq(factory_calls.val, 1)
    @resources.settle_capacity(parent.ledger, short).unwrap()
    let exact = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - quote.0
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - quote.1
      },
    ).unwrap()
    prepare_request_program_module_body(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    ).unwrap()
    assert_eq(factory_calls.val, 1)
    assert_true(physical_equal(parent.program_source_free.unwrap(), installed))
    assert_true(installed.compilation is Some(_))
    assert_true(
      parent.program_artifact_geometry is None &&
      parent.program_artifact_quote is None &&
      parent.program_artifact_inputs is None,
    )
    let body = borrow_request_program_preparation(parent).unwrap()
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(body),
      Ok((quote.0 - quote.2, quote.1 - quote.2)),
    )
    // False reports that the ORIGINAL owner remains live; the borrow has
    // still returned. Retirement below proves its separate release boundary.
    assert_eq(@resources.return_preparation_body_borrow(body), Ok(false))
    @resources.settle_capacity(parent.ledger, exact).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "funded artifact current reentry cannot replace original module input or begin a second constructor" {
  let holder : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let observed = Ref(0)
  let (parent, input, _) = request_program_body_fixture(current=() => {
    if holder.val is Some(parent) &&
      parent.program_artifact_quote is Some(_) &&
      parent.phase == Selecting {
      guard abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) else {
        return false
      }
      guard parent.input is Some(input) &&
        parent.program_artifact_inputs
        is Some(
          (manifests, compilation_limits, contracts, retained_output, factory)
        ) else {
        return false
      }
      guard prepare_request_program_module_body(
          parent,
          input,
          contracts,
          manifests~,
          compilation_limits~,
          retained_output~,
          provider_factory=factory,
        )
        is Err(Preparation(WrongPhase)) else {
        return false
      }
      observed.val += 1
    }
    true
  })
  holder.val = Some(parent)
  let calls = Ref(0)
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      []
    },
  ).unwrap()
  assert_true(observed.val > 0)
  assert_eq(calls.val, 1)
  assert_true(parent.program_source_free.unwrap().compilation is Some(_))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "artifact reservation derives from original constructor bodies rather than configured codec headroom" {
  let (parent, _, prepared) = request_program_body_fixture()
  let manifests = request_program_module_manifests()
  let sequence = @publication_host.prepared_client_values_sequence_limits(
    prepared,
  )
  let tight = @publication_host.measure_prepared_client_pure_compilation_construction(
    prepared, manifests, sequence, 1000, 10000, 1000000, 100000, 100,
  ).unwrap()
  let roomy = @publication_host.measure_prepared_client_pure_compilation_construction(
    prepared, manifests, sequence, 2000, 20000, 2000000, 200000, 200,
  ).unwrap()
  assert_true(tight == { ..roomy, limits: tight.limits, })
  let actual = program_artifact_construction_extents(tight).unwrap()
  assert_true(actual.0 > 0L && actual.1 > 0L)
  assert_eq(program_artifact_construction_extents(roomy), Some(actual))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "actual Request compilation records original final Plan encoding node debits without a replay" {
  let (parent, input, prepared) = request_program_body_fixture()
  let counter = parent.program_artifact_plan_encoding_nodes
  let factory_calls = Ref(0)
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      factory_calls.val += 1
      []
    },
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  let wire = match plan.compilation.unwrap() {
    @publication_host.Values(original) =>
      @publication_host.client_values_executable_plan_wire(
        @publication_host.client_values_compilation_plan(original),
      )
    @publication_host.Tasks(original) =>
      @publication_host.client_task_executable_plan_wire(
        @publication_host.client_task_compilation_plan(original),
      )
    _ => abort("original pure compiler required")
  }
  // Independent Source parser oracle: the final wire has one self-CID value
  // absent from its hash preimage. Both original writer traversals visit all
  // other values. This test-side read never runs in the product constructor.
  let actual = @source.parse_json_bytes_measured(@utf8.encode(wire), {
    max_input_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  let expected = 2L * actual.usage.nodes.to_int64() - 1L
  assert_eq(counter.val, expected)
  assert_eq(parent.program_artifact_work_spent, expected)
  assert_true(parent.program_artifact_work is None)
  assert_true(parent.program_artifact_work_issue is None)
  assert_eq(factory_calls.val, 1)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-plan-work",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  installed_managed_run_compilation_original(run, prepared).unwrap() |> ignore
  assert_eq(counter.val, expected)
  retire_installed_managed_run(run).unwrap()
  assert_eq(counter.val, expected)
  assert_eq(parent.program_artifact_work_spent, expected)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request final Plan encoding refusal preserves its original spent phase without a refill" {
  // A separate completed component determines the exact unchanged codec
  // closing-byte boundary. It retires before the fresh refused Request below.
  let (baseline, baseline_input, _) = request_program_body_fixture()
  prepare_request_program_module_body(
    baseline,
    baseline_input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let wire = match baseline.program_source_free.unwrap().compilation.unwrap() {
    @publication_host.Values(original) =>
      @publication_host.client_values_executable_plan_wire(
        @publication_host.client_values_compilation_plan(original),
      )
    @publication_host.Tasks(original) =>
      @publication_host.client_task_executable_plan_wire(
        @publication_host.client_task_compilation_plan(original),
      )
    _ => abort("original pure compilation required")
  }
  let expected = baseline.program_artifact_work_spent
  assert_true(expected > 0L)
  abort_request_preparation_after_cleanup(baseline).unwrap()
  assert_eq(@resources.ledger_usage(baseline.ledger).live_reservations, 0)
  let (parent, input, _) = request_program_body_fixture()
  let limits = {
    ..@publication_host.client_standard_pure_compilation_limits(),
    max_wire_bytes: @utf8.encode(wire).length() - 1,
  }
  let calls = Ref(0)
  let failed = prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=limits,
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      []
    },
  )
  assert_true(failed is Err(TaskCompilation(Plan(Encoding))))
  assert_eq(calls.val, 1)
  assert_true(parent.phase == ProgramBodyFailed)
  assert_true(parent.program_source_free.unwrap().compilation is None)
  assert_true(borrow_request_program_preparation(parent) is Err(WrongPhase))
  assert_eq(parent.program_artifact_plan_encoding_nodes.val, expected)
  assert_eq(parent.program_artifact_work_spent, expected)
  assert_true(parent.program_artifact_work is None)
  assert_true(parent.program_artifact_work_issue is None)
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.program_capacity.unwrap(),
      input,
      @resources.ExecutionPlan,
      1L,
    )
    is Err(AlreadyClaimed),
  )
  finish_request_program_artifact_work(parent).unwrap()
  assert_eq(parent.program_artifact_work_spent, expected)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(parent.program_artifact_plan_encoding_nodes.val, expected)
  assert_eq(parent.program_artifact_work_spent, expected)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request module constructor retains same checked output and actual Plan before the first body borrow" {
  let (parent, input, prepared) = request_program_body_fixture()
  let original = parent.program_capacity.unwrap()
  let calls = Ref(0)
  let reentry = Ref(0)
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      if parent.phase == Selecting &&
        parent.program_plan_quote is Some(_) &&
        parent.compiled_program is Some(body) &&
        physical_equal(body, prepared) {
        reentry.val += 1
      }
      if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
        reentry.val += 1
      }
      if borrow_request_program_preparation(parent) is Err(WrongPhase) {
        reentry.val += 1
      }
      []
    },
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(reentry.val, 3)
  assert_true(physical_equal(parent.program_capacity.unwrap(), original))
  let plan = parent.program_source_free.unwrap()
  assert_true(plan.configuration is Some(_))
  assert_true(plan.owner is Pure(body) && physical_equal(body, prepared))
  let manager = borrow_request_program_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(manager).unwrap(),
      prepared,
    ),
  )
  assert_true(
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=_ => {
        calls.val += 1
        []
      },
    )
    is Err(Preparation(WrongPhase)),
  )
  assert_eq(calls.val, 1)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "request-module-original",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.source_free_preparation.unwrap(), plan))
  assert_true(
    parent.program_source_free is None && parent.compiled_program is None,
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(manager).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request module callback exception unwinds its original constructor before cleanup" {
  let (parent, input, prepared) = request_program_body_fixture()
  let caught = closed_module_test_catch(() => {
    ignore(
      prepare_request_program_module_body(
        parent,
        input,
        request_program_module_contracts(),
        manifests=request_program_module_manifests(),
        compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
        retained_output=true,
        provider_factory=_ => closed_module_test_throw(),
      ),
    )
  })
  assert_true(caught)
  assert_true(parent.phase == ProgramBodyFailed)
  assert_true(physical_equal(parent.compiled_program.unwrap(), prepared))
  assert_true(parent.program_source_free is None)
  assert_true(borrow_request_program_preparation(parent) is Err(WrongPhase))
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    before.live_reservations > 0 && before.reserved_retention_bytes > 0L,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  let after = @resources.ledger_usage(parent.ledger)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.attempts, before.attempts)
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

///|
test "Request installed module keeps Unicode Text outside the old numeric construction profile" {
  let text = request_check_wire
    .replace(old="\"type\":\"number\"", new="\"type\":\"string\"")
    .replace(old="\"rows\":[]", new="\"rows\":[{\"id\":\"é😀\"}]")
  let (parent, child, _, input) = registration_parent_fixture(text~)
  finish_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  continue_request_program_preparation(parent, input).unwrap() |> ignore
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "request-module-text",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  let output = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(output.rows().unwrap(), ["{\"id\":\"é😀\"}"])
  assert_true(output.close())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  // The authored Values stage and Result-consuming Take stage each started.
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 2)
}

///|
test "Request installed module preserves exact one-byte-short refusal before its original factory" {
  for retention in [true, false] {
    let (parent, input, _) = request_program_body_fixture()
    let contracts = request_program_module_contracts()
    let calls = Ref(0)
    let factory = _ => {
      calls.val += 1
      []
    }
    assert_true(
      prepare_request_program_module_body(
        parent,
        [1],
        contracts,
        manifests=request_program_module_manifests(),
        compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
        retained_output=true,
        provider_factory=factory,
      )
      is Err(Preparation(ForeignOriginal)),
    )
    let capacity = parent.program_capacity.unwrap()
    let base = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - base.0
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - base.1
      },
    ).unwrap()
    assert_true(
      prepare_request_program_module_body(
        parent,
        input,
        contracts,
        manifests=request_program_module_manifests(),
        compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
        retained_output=true,
        provider_factory=factory,
      )
      is Err(Preparation(Capacity(_))),
    )
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
    let declined = prepare_request_program_module_body(
      parent,
      input,
      contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=factory,
    )
    assert_true(
      if retention {
        declined is Err(Preparation(Capacity(Resource(RetentionLimit))))
      } else {
        declined is Err(Preparation(Capacity(Resource(ExecutionLimit))))
      },
    )
    assert_eq(calls.val, 0)
    assert_true(
      parent.phase == ProgramPlanQuoted && !parent.program_body_attempted,
    )
    assert_eq(parent.program_plan_quote.unwrap(), quote)
    @resources.settle_capacity(parent.ledger, short).unwrap()
    prepare_request_program_module_body(
      parent,
      input,
      contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=factory,
    ).unwrap()
    assert_eq(calls.val, 1)
    assert_eq(parent.program_plan_quote.unwrap(), quote)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "actual Request refuses one-short measurement storage before its original geometry allocation" {
  for retention in [true, false] {
    let (parent, input, prepared) = request_program_body_fixture()
    let capacity = parent.program_capacity.unwrap()
    let storage = @execution.preparation_representation_cost(
      @publication_host.prepared_client_pure_measurement_storage(
        prepared,
        @publication_host.client_standard_pure_compilation_limits(),
      ).unwrap(),
    ).unwrap()
    assert_true(storage > 1L)
    let blocker : Ref[@resources.CapacityReservation?] = Ref(None)
    let calls = Ref(0)
    let contracts = request_program_module_contracts()
    let factory = _ => {
      calls.val += 1
      let usage = @resources.ledger_usage(parent.ledger)
      let limits = @resources.ledger_limits(parent.ledger)
      let r = limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      let e = limits.execution_bytes - usage.reserved_execution_bytes
      blocker.val = Some(
        @resources.reserve_capacity(
          parent.ledger,
          if retention {
            r - storage + 1L
          } else {
            0L
          },
          if retention {
            0L
          } else {
            e - storage + 1L
          },
        ).unwrap(),
      )
      []
    }
    let refused = prepare_request_program_module_body(
      parent,
      input,
      contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=factory,
    )
    assert_true(
      if retention {
        refused is Err(Preparation(Capacity(Resource(RetentionLimit))))
      } else {
        refused is Err(Preparation(Capacity(Resource(ExecutionLimit))))
      },
    )
    assert_true(parent.program_artifact_geometry is None)
    assert_true(parent.program_artifact_quote is None)
    assert_true(parent.program_source_free is Some(_))
    assert_true(physical_equal(capacity, parent.program_capacity.unwrap()))
    assert_true(parent.phase == ProgramPlanReserved)
    assert_eq(calls.val, 1)
    @resources.settle_capacity(parent.ledger, blocker.val.unwrap()).unwrap()
    prepare_request_program_module_body(
      parent,
      input,
      contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=factory,
    ).unwrap()
    assert_eq(calls.val, 1)
    assert_true(parent.program_source_free.unwrap().compilation is Some(_))
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "measurement storage preserves each original invalid compiler bound before its allocation" {
  let standard = @publication_host.client_standard_pure_compilation_limits()
  for
    limits in [
      { ..standard, max_facts: 0, },
      { ..standard, max_witnesses: 0, },
      { ..standard, max_wire_bytes: 0, },
      { ..standard, max_nodes: 0, },
      { ..standard, max_depth: 0, },
    ] {
    let (parent, input, _) = request_program_body_fixture()
    assert_true(
      prepare_request_program_module_body(
        parent,
        input,
        request_program_module_contracts(),
        manifests=request_program_module_manifests(),
        compilation_limits=limits,
        retained_output=true,
        provider_factory=_ => [],
      )
      is Err(Construction(InvalidLimits)),
    )
    assert_true(parent.program_artifact_geometry is None)
    assert_true(parent.program_measurement_quote is None)
    assert_true(parent.program_artifact_work is None)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
fn request_ordered_contract_document(uses_parameter : Bool) -> String {
  let original = native_driver_program
    .replace(
      old="\"derive\":{\"value\":\"id + $n\"}",
      new="\"derive\":[{\"old\":{\"field\":\"id\"}},{\"id\":{\"add\":[{\"field\":\"old\"},{\"literal\":1}]}},{\"value\":{\"add\":[{\"field\":\"old\"},{\"field\":\"id\"}]}}]",
    )
    .replace(
      old="\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}",
      new="\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}},\"other\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}",
    )
  if uses_parameter {
    original.replace(
      old="\"value\":{\"add\":[{\"field\":\"old\"},{\"field\":\"id\"}]}",
      new="\"value\":\"old + $n\"",
    )
  } else {
    original
  }
}

///|
test "original ordered contract fixture retains its exact unused Parameter refusal" {
  let document = request_ordered_contract_document(false)
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(document)
  match
    prepare_request_native_computation(
      parent,
      input,
      request_native_test_value(document),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
    ) {
    Err(CheckOutcome(@checked.Rejected(diagnostic))) => {
      guard @checked.diagnostic_cause(diagnostic)
        is @checked.Source(
          @checked.Identity(References(Usage(UnusedParameter(declaration))))
        ) else {
        fail(
          "the original source must retain its typed unused Parameter refusal",
        )
      }
      assert_eq(declaration.name, "n")
    }
    _ => fail("the original invalid source must not reach compilation")
  }
  assert_true(parent.program_source_free is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "actual Request compiler retains its original installed ordered contract before emission" {
  let document = request_ordered_contract_document(true)
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(document)
  let _ = prepare_request_native_computation(
    parent,
    input,
    request_native_test_value(document),
    native_json_reader,
    environment,
    publication,
    [],
    @publication_host.client_standard_program_preparation_limits(),
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let prepared = parent.compiled_program.unwrap()
  assert_true(
    @publication_host.prepared_client_requires_task_compilation(prepared),
  )
  let contracts = request_program_module_contracts()
  assert_true(contracts.original.value.ordered_contract is Some(_))
  let calls = Ref(0)
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      []
    },
  ).unwrap()
  // The exact normal caller must have bound this original before any Task
  // pipeline cache/emission. A late retrofit of unbound material refuses.
  assert_true(
    @publication_host.bind_prepared_client_compiler_contracts(
      prepared,
      contracts.original.value.ordered_contract,
    )
    is Ok(_),
  )
  let foreign = request_program_module_contracts()
  assert_true(
    @publication_host.bind_prepared_client_compiler_contracts(
      prepared,
      foreign.original.value.ordered_contract,
    )
    is Err(_),
  )
  assert_eq(calls.val, 1)
  assert_true(parent.program_source_free.unwrap().compilation is Some(_))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
// The normal Pure caller selects its Source inventory from this same borrowed
// compiler result. Source-free module completion must keep that original
// holder, rather than returning it and issuing another body token.
test "one Pure constructor input holder survives source-free module completion and Run adoption" {
  let (parent, input, prepared) = request_program_body_fixture()
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  let factory_calls = Ref(0)
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      factory_calls.val += 1
      []
    },
  ).unwrap()
  assert_eq(factory_calls.val, 1)
  assert_true(parent.program_source_free.unwrap().compilation is Some(_))
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-pure-constructor-holder",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
fn request_timed_invocation_backing_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @publication_host.ClientRunCompilation,
) raise {
  let (parent, input, _) = request_program_body_fixture(current~)
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  (parent, input, holder, artifact)
}

///|
test "timed invocation backing retains its original compiler and absolute holding until original cleanup" {
  let (parent, input, holder, artifact) = request_timed_invocation_backing_fixture()
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let spent = parent.program_artifact_work_spent
  reserve_request_query_time_invocation(parent, input, artifact).unwrap()
  let target = parent.program_invocation_quote.unwrap()
  assert_true(target.0 > before.0 && target.1 > before.1)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(target),
  )
  assert_true(
    parent.program_compilation is Some(original) &&
    physical_equal(original, artifact),
  )
  let usage = @resources.ledger_usage(parent.ledger)
  reserve_request_query_time_invocation(parent, input, artifact).unwrap()
  assert_eq(parent.program_invocation_quote, Some(target))
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_true(parent.program_invocation_quote is None)
}

///|
test "timed invocation backing preserves one-short original targets and retries without another compiler" {
  for retention in [true, false] {
    let (parent, input, holder, artifact) = request_timed_invocation_backing_fixture()
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let extent = request_query_time_invocation_extent(
      parent.program_artifact_geometry.unwrap(),
    ).unwrap()
    let target = (before.0 + extent.0, before.1 + extent.1)
    let limits = @resources.ledger_limits(parent.ledger)
    let block = @resources.reserve_attempt(
      parent.ledger,
      0L,
      if retention {
        limits.retained_bytes - target.0 + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - target.1 + 1L
      },
    ).unwrap()
    let result = reserve_request_query_time_invocation(parent, input, artifact)
    assert_true(
      if retention {
        result is Err(Preparation(Capacity(Resource(RetentionLimit))))
      } else {
        result is Err(Preparation(Capacity(Resource(ExecutionLimit))))
      },
    )
    assert_eq(parent.program_invocation_quote, Some(target))
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(before),
    )
    assert_true(parent.phase == ProgramPlanReserved)
    @resources.settle_reservation(parent.ledger, block).unwrap()
    reserve_request_query_time_invocation(parent, input, artifact).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(target),
    )
    assert_true(
      parent.program_compilation is Some(original) &&
      physical_equal(original, artifact),
    )
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "timed invocation backing fences current reentry and foreign input before the original constructor" {
  let during : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let reentry = Ref(false)
  let allow = Ref(true)
  let (parent, input, holder, artifact) = request_timed_invocation_backing_fixture(current=() => {
      if during.val is Some(parent) {
        reentry.val = abort_request_preparation_after_cleanup(parent)
          is Err(WrongPhase)
      }
      allow.val
    },
  )
  let before = request_preparation_accounting(parent)
  assert_true(
    reserve_request_query_time_invocation(parent, [1], artifact)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_preparation_accounting(parent), before)
  during.val = Some(parent)
  allow.val = false
  assert_true(
    reserve_request_query_time_invocation(parent, input, artifact) is Err(_),
  )
  assert_true(reentry.val)
  assert_true(parent.phase == ProgramPlanReserved)
  assert_true(parent.program_invocation_quote is Some(_))
  allow.val = true
  // The original Host has latched retirement. Restoring callback DATA cannot
  // revive it; only the SAME owner's original cleanup may still continue.
  assert_true(
    reserve_request_query_time_invocation(parent, input, artifact)
    is Err(Preparation(Capacity(Resource(ClosedReservation)))),
  )
  during.val = None
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "timed invocation backing survives original Module adoption and pending payload retirement" {
  let (parent, input, holder, artifact) = request_timed_invocation_backing_fixture()
  let prepared = @resources.preparation_body_borrow_value(holder).unwrap()
  reserve_request_query_time_invocation(parent, input, artifact).unwrap()
  let target = parent.program_invocation_quote.unwrap()
  let (manifests, compilation_limits, contracts, retained_output, factory) = parent.program_artifact_inputs.unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output~,
    provider_factory=factory,
  ).unwrap()
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes >= target.0,
  )
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-timed-invocation-holding",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes >= target.0,
  )
  assert_true(parent.program_invocation_quote is None)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes >= target.0,
  )
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "source-free adoption preserves loose Plan DATA and rejects foreign input before original custody transfer" {
  let (parent, input, prepared) = request_program_body_fixture()
  reserve_request_program_plan(parent, input).unwrap()
  let original = request_program_installed_plan(prepared)
  let available = preparation_initial_limits(parent.initial, input).unwrap()
  // White-box boundary: alter only the quoted DATA, not the operational grant.
  // No execution/normal-installation acceptance is claimed by this fixture.
  let oversized = {
    ..original,
    limits: {
      ..original.limits,
      execution_bytes: available.execution_bytes + 1L,
    },
  }
  complete_request_program_preparation(parent, input, oversized).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "capacity-before-adoption",
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    begin_preparation_owned_installed_managed_run_original(
      parent.initial,
      [1],
      parent.program_capacity.unwrap(),
      prepared,
      request,
      oversized,
    )
    is Err(Resource(_)),
  )
  let (foreign_parent, foreign_input, foreign_prepared) = request_program_body_fixture()
  let foreign = request_program_installed_plan(foreign_prepared)
  assert_true(
    begin_preparation_owned_installed_managed_run_original(
      parent.initial,
      input,
      parent.program_capacity.unwrap(),
      prepared,
      request,
      foreign,
    )
    is Err(ForeignOriginal),
  )
  abort_request_preparation_after_cleanup(foreign_parent).unwrap()
  ignore(foreign_input)
  let after_refusal = @resources.ledger_usage(parent.ledger)
  assert_eq(after_refusal, before)
  assert_true(parent.phase == ProgramBodyReady)
  assert_true(physical_equal(parent.program_source_free.unwrap(), oversized))
  // Enlarged quote DATA does not enlarge the finite original Ledger or make
  // future tasks prepaid. The actual retained body already fits that parent.
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.source_free_preparation.unwrap(), oversized))
  assert_eq(@resources.ledger_limits(parent.ledger), available)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, before.attempts)
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request Plan quote backs original checked node proof frames before factory" {
  let (parent, input, _) = request_program_body_fixture()
  let original = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(original, input).unwrap()
  let data = program_check_data_extent_cost(parent.program_data.unwrap()).unwrap()
  let retained = client_local_value_node_proof_retained_bytes().unwrap()
  let scratch = client_local_value_node_proof_scratch_bytes().unwrap()
  assert_true(scratch > 100L * 200L)
  let quote = request_program_plan_quote(parent, input).unwrap()
  let original_tail_field = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  // No Direct capture is selected, but its borrowed Plan field still lives
  // alongside the checked proof. This is one reference, never another graph.
  let direct_selector_field = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 1L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(
    quote,
    (
      before.0 + data + retained + direct_selector_field,
      before.1 +
      data +
      retained +
      scratch +
      original_tail_field +
      direct_selector_field,
    ),
  )
  // The old data-only allowance is deliberately insufficient. The original
  // parent capacity must grow before ANY selected module/provider callback.
  let limits = @resources.ledger_limits(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    0L,
    limits.execution_bytes - (quote.1 - scratch),
  ).unwrap()
  let calls = Ref(0)
  let result = prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      []
    },
  )
  assert_true(result is Err(Preparation(Capacity(Resource(ExecutionLimit)))))
  assert_eq(calls.val, 0)
  assert_true(!parent.program_body_attempted)
  assert_eq(parent.program_plan_quote, Some(quote))
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      []
    },
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(parent.program_plan_quote, Some(quote))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
// Exact authored Program from the public fixture, including its unused arrays.
let public_array_nearest_array_document : String =
  #|{"version":"actql/0.1","id":"public-nearest-input","stages":[{"id":"candidates","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"zz_unused":{"type":"array","nullable":false,"max_items":129,"items":{"type":"number","nullable":false}}},"rows":[{"id":"xb","embedding":[1,2],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},{"id":"xa","embedding":[1,2],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","embedding","zz_unused"]}}},{"id":"queries","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"zz_unused":{"type":"array","nullable":false,"max_items":129,"items":{"type":"number","nullable":false}}},"rows":[{"id":"xb","embedding":[1,2],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},{"id":"xa","embedding":[1,2],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","embedding","zz_unused"]}}},{"id":"nearest","inputs":{"queries":{"result":{"stage":"queries","result":"r"}},"candidates":{"result":{"stage":"candidates","result":"r"}}},"steps":[{"from":"candidates","nearest":{"queries":"queries","metric":"dot","k":2,"candidate_id":"id","candidate_vector":"embedding","query_id":"id","query_vector":"embedding"},"as":"out"}],"results":{"r":{"from":"out","fields":["candidate_id","query_id","rank","score"]}}},{"id":"consumer_a","inputs":{"rows":{"result":{"stage":"nearest","result":"r"}}},"steps":[{"select":["candidate_id","query_id","rank","score"],"as":"out"}],"results":{"r":{"from":"out","fields":["candidate_id","query_id","rank","score"]}}},{"id":"consumer_b","inputs":{"rows":{"result":{"stage":"nearest","result":"r"}}},"steps":[{"select":["candidate_id","query_id","rank","score"],"as":"out"}],"results":{"r":{"from":"out","fields":["candidate_id","query_id","rank","score"]}}}],"results":{"published":{"from":{"stage":"nearest","result":"r"}},"consumed_a":{"from":{"stage":"consumer_a","result":"r"}},"consumed_b":{"from":{"stage":"consumer_b","result":"r"}}}}

///|
// Exact authored Program from the public fixture, including its unused arrays.
let public_array_nearest_names_document : String =
  #|{"version":"actql/0.1","id":"public-nearest-names","stages":[{"id":"candidates","inputs":{},"steps":[{"values":{"schema":{"aa_unused":{"type":"array","nullable":false,"max_items":115,"items":{"type":"number","nullable":false}},"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀":{"type":"number","nullable":false},"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀":{"type":"vector","dimensions":2,"nullable":false},"zz_unused":{"type":"array","nullable":false,"max_items":129,"items":{"type":"number","nullable":false}}},"rows":[{"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀":2,"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀":[1,2],"aa_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},{"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀":1,"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀":[1,2],"aa_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]},"as":"out"}],"results":{"r":{"from":"out","fields":["aa_unused","mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀","zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀","zz_unused"]}}},{"id":"queries","inputs":{},"steps":[{"values":{"schema":{"aa_unused":{"type":"array","nullable":false,"max_items":115,"items":{"type":"number","nullable":false}},"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀":{"type":"number","nullable":false},"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀":{"type":"vector","dimensions":2,"nullable":false},"zz_unused":{"type":"array","nullable":false,"max_items":129,"items":{"type":"number","nullable":false}}},"rows":[{"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀":2,"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀":[1,2],"aa_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},{"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀":1,"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀":[1,2],"aa_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]},"as":"out"}],"results":{"r":{"from":"out","fields":["aa_unused","mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀","zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀","zz_unused"]}}},{"id":"nearest","inputs":{"queries":{"result":{"stage":"queries","result":"r"}},"candidates":{"result":{"stage":"candidates","result":"r"}}},"steps":[{"from":"candidates","nearest":{"queries":"queries","metric":"dot","k":2,"candidate_id":"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀","candidate_vector":"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀","query_id":"mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm😀","query_vector":"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz😀"},"as":"out"}],"results":{"r":{"from":"out","fields":["candidate_id","query_id","rank","score"]}}},{"id":"consumer_a","inputs":{"rows":{"result":{"stage":"nearest","result":"r"}}},"steps":[{"select":["candidate_id","query_id","rank","score"],"as":"out"}],"results":{"r":{"from":"out","fields":["candidate_id","query_id","rank","score"]}}},{"id":"consumer_b","inputs":{"rows":{"result":{"stage":"nearest","result":"r"}}},"steps":[{"select":["candidate_id","query_id","rank","score"],"as":"out"}],"results":{"r":{"from":"out","fields":["candidate_id","query_id","rank","score"]}}}],"results":{"published":{"from":{"stage":"nearest","result":"r"}},"consumed_a":{"from":{"stage":"consumer_a","result":"r"}},"consumed_b":{"from":{"stage":"consumer_b","result":"r"}}}}

///|
// Exact authored Program from the public fixture, including its unused arrays.
let public_array_ranking_array_document : String =
  #|{"version":"actql/0.1","id":"public-ranking-input","stages":[{"id":"left","inputs":{},"steps":[{"values":{"schema":{"q":{"type":"number","nullable":true},"segment":{"type":"string","nullable":true},"id":{"type":"number","nullable":false},"rank":{"type":"number","nullable":false},"zz_unused":{"type":"array","nullable":false,"items":{"type":"number","nullable":false},"max_items":129}},"rows":[{"q":null,"segment":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxs","id":2,"rank":2,"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},{"q":null,"segment":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxs","id":1,"rank":1,"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]},"as":"out"}],"results":{"r":{"from":"out","fields":["q","segment","id","rank","zz_unused"]}}},{"id":"right","inputs":{},"steps":[{"values":{"schema":{"q":{"type":"number","nullable":true},"segment":{"type":"string","nullable":true},"id":{"type":"number","nullable":false},"rank":{"type":"number","nullable":false},"zz_unused":{"type":"array","nullable":false,"items":{"type":"number","nullable":false},"max_items":129}},"rows":[{"q":null,"segment":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxs","id":2,"rank":2,"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},{"q":null,"segment":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxs","id":1,"rank":1,"zz_unused":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]}]},"as":"out"}],"results":{"r":{"from":"out","fields":["q","segment","id","rank","zz_unused"]}}},{"id":"ranking","inputs":{"left":{"result":{"stage":"left","result":"r"}},"right":{"result":{"stage":"right","result":"r"}}},"steps":[{"from":"left","merge_rankings":{"with":["right"],"by":["q","segment"],"candidate":"id","rank":"rank","k":3,"score_policy":{"rrf":{"rank_constant":1,"weights":[1,1],"rank_window":2}}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","q","rank","score","segment"]}}},{"id":"consumer_a","inputs":{"rows":{"result":{"stage":"ranking","result":"r"}}},"steps":[{"select":["id","q","rank","score","segment"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","q","rank","score","segment"]}}},{"id":"consumer_b","inputs":{"rows":{"result":{"stage":"ranking","result":"r"}}},"steps":[{"select":["id","q","rank","score","segment"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","q","rank","score","segment"]}}}],"results":{"published":{"from":{"stage":"ranking","result":"r"}},"consumed_a":{"from":{"stage":"consumer_a","result":"r"}},"consumed_b":{"from":{"stage":"consumer_b","result":"r"}}}}

///|
// Actual checker/compiler/module/VecA/task/cleanup on one original parent.
// The provider is the installed VecA component, not full Host acceptance.
fn public_array_preparation_host(
  source : String,
) -> (
  ClientInstalledManagedRun,
  @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  @resources.Ledger,
) raise {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: false, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
    graph=true,
  ).unwrap()

  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = native_driver_parent(source)
  let ledger = parent.ledger
  let limits = @resources.ledger_limits(ledger)
  assert_eq(limits.retained_bytes, 536870912L)
  assert_eq(limits.execution_bytes, 536870912L)
  assert_eq(
    prepare_request_native_computation(
      parent,
      input,
      request_native_test_value(source),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap(),
    Pure,
  )
  let prepared = parent.compiled_program.unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=capacity => {
      [
        @nearest_provider.provider(
          {
            max_input_records: 100,
            max_records: 100,
            max_fields_per_record: 100,
            max_value_bytes: 10000,
            max_total_value_bytes: 100000,
            max_retained_value_bytes: 100000,
            max_value_nodes: 10000,
            max_value_depth: 100,
            max_contract_work: 10000,
            max_work: 100000,
            max_workspace_slots: 10000,
          },
          100000L,
          capacity,
        ),
      ]
    },
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  assert_false(installed_effect_limits_fit(plan.limits, limits))
  assert_eq(@resources.ledger_limits(ledger), limits)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "public-array-original",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(
    physical_equal(require_installed_managed_run(run).unwrap(), ledger),
  )
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  let dag = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
  // Match the ordinary Node Named Result identity owner, whose actual row
  // indices grow before construction on this SAME task reservation.
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      dag, true, false, false, false,
    ),
  )
  (run, setup, ledger)
}

///|
test "public nearest-array module starts actual tasks below whole Plan maxima on the original parent" {
  let (run, setup, ledger) = public_array_preparation_host(
    public_array_nearest_array_document,
  )
  let limits = @resources.ledger_limits(ledger)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  let rows = execution.rows().unwrap()
  let expected = [
    "{\"candidate_id\":\"xa\",\"query_id\":\"xa\",\"rank\":1,\"score\":5}", "{\"candidate_id\":\"xb\",\"query_id\":\"xa\",\"rank\":2,\"score\":5}",
    "{\"candidate_id\":\"xa\",\"query_id\":\"xb\",\"rank\":1,\"score\":5}", "{\"candidate_id\":\"xb\",\"query_id\":\"xb\",\"rank\":2,\"score\":5}",
  ]
  assert_eq(rows.length(), expected.length())
  for index in 0..<rows.length() {
    assert_eq(@json.parse(rows[index]), @json.parse(expected[index]))
  }
  let attempts = @resources.ledger_usage(ledger).attempts
  assert_true(attempts > 0)
  assert_true(execution.close())
  retire_installed_managed_run(run).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, attempts)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.held_bytes, 0L)
  assert_eq(@resources.ledger_limits(ledger), limits)
}

///|
test "public nearest-names module starts actual tasks below whole Plan maxima on the original parent" {
  let (run, setup, ledger) = public_array_preparation_host(
    public_array_nearest_names_document,
  )
  let limits = @resources.ledger_limits(ledger)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  let rows = execution.rows().unwrap()
  let expected = [
    "{\"candidate_id\":1,\"query_id\":1,\"rank\":1,\"score\":5}", "{\"candidate_id\":2,\"query_id\":1,\"rank\":2,\"score\":5}",
    "{\"candidate_id\":1,\"query_id\":2,\"rank\":1,\"score\":5}", "{\"candidate_id\":2,\"query_id\":2,\"rank\":2,\"score\":5}",
  ]
  assert_eq(rows.length(), expected.length())
  for index in 0..<rows.length() {
    assert_eq(@json.parse(rows[index]), @json.parse(expected[index]))
  }
  let attempts = @resources.ledger_usage(ledger).attempts
  assert_true(attempts > 0)
  assert_true(execution.close())
  retire_installed_managed_run(run).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, attempts)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.held_bytes, 0L)
  assert_eq(@resources.ledger_limits(ledger), limits)
}

///|
test "public ranking-array module starts actual tasks below whole Plan maxima on the original parent" {
  let (run, setup, ledger) = public_array_preparation_host(
    public_array_ranking_array_document,
  )
  let limits = @resources.ledger_limits(ledger)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  let rows = execution.rows().unwrap()
  let expected = [
    "{\"id\":1,\"q\":null,\"rank\":1,\"score\":1,\"segment\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxs\"}",
    "{\"id\":2,\"q\":null,\"rank\":2,\"score\":0.6666666666666666,\"segment\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxs\"}",
  ]
  assert_eq(rows.length(), expected.length())
  for index in 0..<rows.length() {
    assert_eq(@json.parse(rows[index]), @json.parse(expected[index]))
  }
  let attempts = @resources.ledger_usage(ledger).attempts
  assert_true(attempts > 0)
  assert_true(execution.close())
  retire_installed_managed_run(run).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, attempts)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.held_bytes, 0L)
  assert_eq(@resources.ledger_limits(ledger), limits)
}

///|
test "public array actual task metadata exhaustion retains the same parent attempts and physical cleanup" {
  let (run, setup, ledger) = public_array_preparation_host(
    public_array_nearest_array_document,
  )
  let limits = @resources.ledger_limits(ledger)
  let dag = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let task = @strategy.graph_result_task(@strategy.captured_dag_graph(dag), 0).unwrap()
  let block : Ref[@resources.CapacityReservation?] = Ref(None)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    let usage = @resources.ledger_usage(ledger)
    if block.val is None && usage.attempts == task + 1 {
      block.val = Some(
        @resources.reserve_capacity(
          ledger,
          0L,
          limits.execution_bytes - usage.reserved_execution_bytes,
        ).unwrap(),
      )
    }
    true
  })
  assert_true(block.val is Some(_))
  guard execution is Err(failure) else {
    fail("Actual exhausted metadata must refuse before row-index allocation")
  }
  assert_true(failure.issue is Driver(Execution(Physical(ExecutionLimit))))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  @resources.settle_capacity(ledger, block.val.unwrap()).unwrap()
  let attempts = @resources.ledger_usage(ledger).attempts
  retire_installed_managed_run(run).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, attempts)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.held_bytes, 0L)
  assert_eq(@resources.ledger_limits(ledger), limits)
}

///|
test "successful Request artifact retires returned compiler scratch before runtime adoption" {
  let (parent, input, prepared) = request_program_body_fixture()
  let original_capacity = parent.program_capacity.unwrap()
  let factory : (@execution.ExecutionCapacity) -> Array[@local.ManagedProvider] = _ => {
    []
  }
  let contracts = request_program_module_contracts()
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let constructor_peak = parent.program_artifact_quote.unwrap()
  let after = @resources.preparation_capacity_working_extents(
    original_capacity, input,
  ).unwrap()
  assert_true(constructor_peak.2 > 0L)
  assert_eq(
    after,
    (
      constructor_peak.0 - constructor_peak.2,
      constructor_peak.1 - constructor_peak.2,
    ),
  )
  assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
  assert_true(physical_equal(parent.compiled_program.unwrap(), prepared))
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  assert_true(
    physical_equal(
      parent.program_source_free.unwrap().compilation.unwrap(),
      artifact,
    ),
  )
  assert_true(
    physical_equal(parent.program_capacity.unwrap(), original_capacity),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request module codec retains the selected checked profile without another current observation" {
  let standard = @publication_host.client_standard_program_preparation_limits()
  let limits : @publication_host.ClientProgramPreparationLimits = {
    ..standard,
    checking: {
      ..standard.checking,
      compilation: {
        ..standard.checking.compilation,
        artifacts: { bytes: 54321, nodes: 8765, depth: 23, },
      },
    },
  }
  let calls = Ref(0)
  let (parent, _, _, input) = registration_parent_fixture(
    current=() => {
      calls.val += 1
      true
    },
    computation_limits=Some(
      (limits, @publication_host.client_standard_effect_computation_limits()),
    ),
  )
  assert_true(
    request_program_compilation_limits(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  finish_request_computation_preparation(parent, input).unwrap()
  let before = calls.val
  let usage = @resources.ledger_usage(parent.ledger)
  let selected = request_program_compilation_limits(parent, input).unwrap()
  assert_eq(selected.max_wire_bytes, 54321)
  assert_eq(selected.max_nodes, 8765)
  assert_eq(selected.max_depth, 23)
  let defaults = @publication_host.client_standard_pure_compilation_limits()
  assert_eq(selected.max_facts, defaults.max_facts)
  assert_eq(selected.max_witnesses, defaults.max_witnesses)
  assert_true(physical_equal(parent.computation_limits.unwrap(), limits))
  assert_true(
    request_program_compilation_limits(parent, [1])
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(calls.val, before)
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  reserve_request_program_plan(parent, input).unwrap()
  assert_eq(
    request_program_compilation_limits(parent, input).unwrap(),
    selected,
  )
  // An explicit stricter typed constructor is not upgraded to the default
  // selected profile. The existing constructor retains its original factory
  // ordering and its original codec refusal.
  let factory_calls = Ref(0)
  assert_true(
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits={ ..selected, max_wire_bytes: 1, },
      retained_output=true,
      provider_factory=_ => {
        factory_calls.val += 1
        []
      },
    )
    is Err(Construction(_)),
  )
  assert_eq(factory_calls.val, 1)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.computation_limits is None)
  assert_true(
    request_program_compilation_limits(parent, input)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
