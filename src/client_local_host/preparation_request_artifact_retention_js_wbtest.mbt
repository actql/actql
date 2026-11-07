///|
// Real Request/measurement/compilation with independent Ledger pressure.
// The provider is an explicit component port; no Native/ordinary IO is claimed.
test "artifact constructor fits exact output retention with wide execution and spends its factory once" {
  let (parent, input, prepared) = request_program_body_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    calls.val += 1
    []
  }
  let compile = () => {
    prepare_request_program_compilation(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    )
  }
  reserve_request_program_plan(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let base = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let storage = @execution.preparation_representation_cost(
    @publication_host.prepared_client_pure_measurement_storage(
      prepared, compilation_limits,
    ).unwrap(),
  ).unwrap()
  let limits = @resources.ledger_limits(parent.ledger)
  // Admit measurement, then refuse the artifact. No second measurement is
  // used to choose the boundary: keep its actual geometry and absolute target.
  let pressure = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - base.0 - storage,
    0L,
  ).unwrap()
  assert_true(compile() is Err(Preparation(Capacity(Resource(RetentionLimit)))))
  let geometry = parent.program_artifact_geometry.unwrap()
  let (retained, scratch) = program_artifact_construction_extents(geometry).unwrap()
  let measured = parent.program_measurement_quote.unwrap()
  let target = parent.program_artifact_quote.unwrap()
  assert_true(scratch > 0L)
  assert_eq(target.0, measured.0 + retained)
  assert_eq(target.1, measured.1 + retained + scratch)
  assert_eq(calls.val, 0)
  assert_eq(parent.program_artifact_plan_encoding_nodes.val, 0L)
  @resources.settle_capacity(parent.ledger, pressure).unwrap()
  let tight = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - target.0,
    0L,
  ).unwrap()
  let artifact = compile().unwrap()
  assert_true(
    physical_equal(parent.program_artifact_geometry.unwrap(), geometry),
  )
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_eq(after.0, target.0)
  assert_eq(after.1, target.1 - scratch)
  assert_eq(calls.val, 0)
  let spent = parent.program_artifact_work_spent
  assert_true(spent > 0L)
  @resources.settle_capacity(parent.ledger, tight).unwrap()
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
  assert_eq(calls.val, 1)
  assert_eq(parent.program_artifact_work_spent, spent)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "artifact one-byte-short execution preserves same quote and refuses before any encoding" {
  let (parent, input, prepared) = request_program_body_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    calls.val += 1
    []
  }
  let compile = () => {
    prepare_request_program_compilation(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    )
  }
  reserve_request_program_plan(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let base = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let storage = @execution.preparation_representation_cost(
    @publication_host.prepared_client_pure_measurement_storage(
      prepared, compilation_limits,
    ).unwrap(),
  ).unwrap()
  let limits = @resources.ledger_limits(parent.ledger)
  let pressure = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - base.0 - storage,
    0L,
  ).unwrap()
  assert_true(compile() is Err(Preparation(Capacity(Resource(RetentionLimit)))))
  let geometry = parent.program_artifact_geometry.unwrap()
  let target = parent.program_artifact_quote.unwrap()
  @resources.settle_capacity(parent.ledger, pressure).unwrap()
  let short = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - target.0,
    limits.execution_bytes - target.1 + 1L,
  ).unwrap()
  assert_true(compile() is Err(Preparation(Capacity(Resource(ExecutionLimit)))))
  assert_eq(parent.program_artifact_quote, Some(target))
  assert_true(
    physical_equal(parent.program_artifact_geometry.unwrap(), geometry),
  )
  assert_true(parent.program_compilation is None)
  assert_true(parent.program_artifact_work is None)
  assert_eq(parent.program_artifact_work_spent, 0L)
  assert_eq(parent.program_artifact_plan_encoding_nodes.val, 0L)
  assert_eq(calls.val, 0)
  @resources.settle_capacity(parent.ledger, short).unwrap()
  let exact = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - target.0,
    limits.execution_bytes - target.1,
  ).unwrap()
  compile().unwrap() |> ignore
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_eq(after.0, target.0)
  assert_eq(after.1, target.1 - target.2)
  assert_eq(calls.val, 0)
  @resources.settle_capacity(parent.ledger, exact).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
