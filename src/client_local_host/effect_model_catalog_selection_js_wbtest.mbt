///|
fn catalog_model_original(
  registry_count : Int,
  current? : () -> Bool = () => true,
  planning_work? : Int = 500000,
) -> (
  ClientInstalledManagedRun,
  ClientInstalledEffectManagedPlan,
  @publication_host.ClientRequestIdentity,
  @checked.CheckedProgram,
  @resources.Ledger,
  @publication_host.ClientModelReadScope,
) raise {
  let (parent, input, plan, request, construction) = request_effect_model_plan_fixture(
    current~,
    catalog_registry_count=registry_count,
    selected_planning_work=Some(planning_work),
  )
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
  let program = @checked.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(
      plan.prepared,
    ),
  )
  (run, plan, request, program, parent.ledger, scope)
}

///|
fn close_catalog_model_original(
  run : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  scope : @publication_host.ClientModelReadScope,
) -> Unit raise {
  let model = plan.model.unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
}

///|
// This component test exercises the actual private managed selector and same
// original numeric holder. It performs no Source IO and does not claim the
// outer combined-Source collection or ordinary runtime acceptance.
test "managed Model Catalog selects from admitted 4097 metadata and preserves legacy refusal" {
  let (run, plan, request, program, ledger, scope) = catalog_model_original(
    4097,
  )
  let environment = @checked.checked_environment(program)
  assert_eq(
    @environment.member_count(environment, @environment.ContractRegistry),
    4097,
  )
  let cid = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  let callbacks = Ref(0)
  assert_true(
    @checked.checked_local_catalog_dependency_body(
      program,
      0,
      "data_policy",
      cid,
      1000000,
      100000,
      100,
      before_body=Some((_, _, _) => {
        callbacks.val += 1
        true
      }),
    )
    is Err(BudgetExceeded),
  )
  assert_eq(callbacks.val, 0)
  let before = @resources.ledger_usage(ledger)
  let (body, bytes) = match
    prepare_effect_model_catalog_body(
      run, plan, request, program, 0, "data_policy", cid, 1000000, 100000, 100,
    ) {
    Ok(value) => value
    Err(Run(Preparation(issue))) =>
      fail("Catalog preparation " + @debug.to_string(issue))
    Err(Run(ForeignOriginal)) => fail("Catalog foreign original")
    Err(Run(Ledger(issue))) => fail("Catalog ledger " + @debug.to_string(issue))
    Err(Evidence(Dependency(issue))) =>
      fail("Catalog dependency " + @debug.to_string(issue))
    Err(_) => fail("Catalog other refusal")
  }
  assert_eq(@checked.checked_local_dependency_body_cid(body), cid)
  assert_true(bytes > 0)
  let after = @resources.ledger_usage(ledger)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(after.reserved_execution_bytes >= before.reserved_execution_bytes)
  // Member chunks plus actual borrowed field/key/CID visits consume the
  // same original finite policy; metadata lookup is not free work.
  assert_true(after.planning_work - before.planning_work > 4097)
  assert_eq(after.live_reservations, before.live_reservations)
  let mut index = None
  for candidate in 0..<4097 {
    let item = @environment.member_at(
      environment,
      @environment.ContractRegistry,
      candidate,
    ).unwrap()
    if @decode.open_object(@environment.member_body(item)) is Ok(fields) &&
      @decode.lookup(fields, "cid") is Some(value) &&
      @decode.text(value) is Ok(actual) &&
      actual == cid {
      index = Some(candidate)
    }
  }
  let legacy_body = @checked.checked_local_dependency_body(
    program,
    0,
    RegistryContract(index.unwrap()),
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(
    @checked.checked_local_dependency_body_json(body),
    @checked.checked_local_dependency_body_json(legacy_body),
  )
  close_catalog_model_original(run, plan, scope)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "managed Model Catalog refuses foreign original missing CID and lost current" {
  let live = Ref(true)
  let (run, plan, request, program, ledger, scope) = catalog_model_original(
    4097,
    current=() => live.val,
  )
  let (foreign_run, foreign_plan, _, foreign_program, _, foreign_scope) = catalog_model_original(
    0,
  )
  let cid = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  let before = @resources.ledger_usage(ledger)
  assert_true(
    prepare_effect_model_catalog_body(
      run, plan, request, foreign_program, 0, "data_policy", cid, 1000000, 100000,
      100,
    )
    is Err(Run(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    prepare_effect_model_catalog_body(
      run,
      plan,
      request,
      program,
      0,
      "data_policy",
      "sha256:" + "0".repeat(64),
      1000000,
      100000,
      100,
    )
    is Err(Evidence(Dependency(MissingDependency))),
  )
  live.val = false
  let held = @resources.ledger_usage(ledger)
  assert_true(
    prepare_effect_model_catalog_body(
      run, plan, request, program, 0, "data_policy", cid, 1000000, 100000, 100,
    )
    is Err(Run(Preparation(_))),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  live.val = true
  close_catalog_model_original(run, plan, scope)
  close_catalog_model_original(foreign_run, foreign_plan, foreign_scope)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "managed Model Catalog small original bytes and planning work refuse before emission" {
  let cid = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  let (small, plan, request, program, ledger, scope) = catalog_model_original(
    4097,
  )
  let holder = effect_unit_publication_body(small, plan, request).unwrap()
  let limits = @resources.ledger_limits(ledger)
  @resources.reserve_preparation_publication_phase(
    holder,
    plan,
    limits.retained_bytes,
    limits.execution_bytes,
  ).unwrap()
  |> ignore
  assert_true(
    prepare_effect_model_catalog_body(
      small, plan, request, program, 0, "data_policy", cid, 1000000, 100000, 100,
    )
    is Err(Run(Preparation(_))),
  )
  close_catalog_model_original(small, plan, scope)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  let (short, plan, request, program, ledger, scope) = catalog_model_original(
    4097,
  )
  let remaining = @resources.ledger_limits(ledger).planning_work -
    @resources.ledger_usage(ledger).planning_work
  let first_chunk = Int::min(
    256,
    @environment.member_count(
      @checked.checked_environment(program),
      @environment.ContractRegistry,
    ),
  )
  assert_true(remaining > first_chunk + 1)
  @resources.charge_planning(ledger, remaining - first_chunk - 1).unwrap()
  let before_work = @resources.ledger_usage(ledger).planning_work
  assert_true(
    prepare_effect_model_catalog_body(
      short, plan, request, program, 0, "data_policy", cid, 1000000, 100000, 100,
    )
    is Err(Run(Ledger(PlanningLimit))),
  )
  // The member chunk and first field visit were paid; key comparison refused
  // before emitting a body, while preserving its original typed refusal.
  assert_eq(
    @resources.ledger_usage(ledger).planning_work - before_work,
    first_chunk + 1,
  )
  close_catalog_model_original(short, plan, scope)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  // The ordinary100k policy remains a real refusal for this4097-member
  // scalar workload. The positive component explicitly selected500k first.
  let (ordinary, plan, request, program, ledger, scope) = catalog_model_original(
    4097,
    planning_work=100000,
  )
  assert_true(
    prepare_effect_model_catalog_body(
      ordinary, plan, request, program, 0, "data_policy", cid, 1000000, 100000, 100,
    )
    is Err(Run(Ledger(PlanningLimit))),
  )
  close_catalog_model_original(ordinary, plan, scope)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}
