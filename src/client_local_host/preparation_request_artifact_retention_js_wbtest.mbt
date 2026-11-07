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

///|
test "default JSON100k retains its original intent before the same artifact constructor" {
  let document = request_native_numeric_public_program(100000)
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  // Native reserves transport/intent construction before reading the file.
  // This finite Source-only fixture has no actual path/FD or physical supply.
  reserve_request_native_intake_wire(
    parent,
    input,
    document.length() * 6 + 4096,
  ).unwrap()
  let environment_wire = request_numeric_local_environment(
    @publication_host.client_local_product_assets().environment,
    100000,
  )
  let environment = @publication_host.admit_client_check_environment(
    environment_wire,
    request_numeric_environment_cid(environment_wire),
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let writer = @encode.writer(document.length() * 6 + 1024, 4, 2)
  @encode.string_value(writer, document)
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"text\":" +
    @encode.finish(writer) +
    ",\"format\":\"json\"},\"parameters\":null}",
    document.length() * 6 + 1024,
    8192,
    64,
  ).unwrap()
  finish_request_native_intake_wire(parent, input, intent).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  reserve_request_retained_intent_source(parent, input).unwrap() |> ignore
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  finish_request_checked_computation(parent, input, environment, publication).unwrap()
  |> ignore
  let capacity = parent.program_capacity.unwrap()
  let base = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let limits = request_program_compilation_limits(parent, input).unwrap()
  let artifact = match
    prepare_request_program_compilation(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=limits,
      retained_output=false,
      provider_factory=_ => [],
    ) {
    Ok(value) => value
    Err(Preparation(Capacity(issue))) =>
      fail(
        "JSON100k artifact capacity=" +
        @debug.to_string(issue) +
        "; base=" +
        @debug.to_string(base) +
        "; measurement=" +
        @debug.to_string(parent.program_measurement_quote) +
        "; artifact=" +
        @debug.to_string(parent.program_artifact_quote),
      )
    Err(_) => fail("JSON100k changed typed constructor family")
  }
  assert_true(
    artifact is @publication_host.Values(_) ||
    artifact is @publication_host.Tasks(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
