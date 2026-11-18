///|
fn original_node_normalization_parent() -> (
  @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  ClientLocalPreparationInputOriginal,
) raise {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = request_diagnostic_test_parent()
  client_program_prepare_request_source_computation(
    parent,
    input,
    request_diagnostic_test_json(
      "{\"format\":\"sql\",\"text\":\"SELECT 7 AS n\"}",
    ),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  ).unwrap()
  assert_eq(
    client_program_finish_request_computation(
      parent, input, environment, publication,
    ).unwrap(),
    "effect_free",
  )
  (parent, input)
}

///|
test "Node normalization bridge retains the same Request original before Plan and reads it afterward" {
  let (parent, input) = original_node_normalization_parent()
  let original = client_program_prepare_request_program_normalization(
    parent, input,
  ).unwrap()
  let repeated = client_program_prepare_request_program_normalization(
    parent, input,
  ).unwrap()
  assert_true(physical_equal(original, repeated))
  let holder = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let expected = @publication_host.prepared_client_local_normalization_evidence(
    prepared, original,
  ).unwrap()
  let actual = client_program_prepared_local_normalization_evidence(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  assert_true(physical_equal(actual, expected))
  assert_eq(
    @publication.run_evidence_value_json(actual),
    @publication.run_evidence_value_json(expected),
  )
  assert_eq(
    @publication.run_evidence_value_identity(actual),
    @publication.run_evidence_value_identity(expected),
  )
  // Plan reservation does not permit another normalization constructor.
  assert_true(
    client_program_prepare_request_program_normalization(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  ignore(client_program_abort_request_preparation(parent))
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  ignore(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}

///|
test "Node cached normalization read preserves exact wire bound and refuses unissued originals" {
  let (parent, input) = original_node_normalization_parent()
  client_program_prepare_request_program_normalization(parent, input).unwrap()
  |> ignore
  let holder = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let original = client_program_prepared_local_normalization_evidence(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  let wire = @publication.run_evidence_value_json(original)
  // This independently selected literal input has only ASCII journal fields.
  for i in 0..<wire.length() {
    assert_true(wire.unsafe_get(i).to_int() < 128)
  }
  let exact = client_program_prepared_local_normalization_evidence(
    prepared,
    wire.length(),
    100000,
    64,
  ).unwrap()
  assert_true(physical_equal(original, exact))
  assert_true(
    client_program_prepared_local_normalization_evidence(
      prepared,
      wire.length() - 1,
      100000,
      64,
    )
    is Err(Evidence(RunEvidenceInvalidWire)),
  )
  assert_true(
    physical_equal(
      original,
      client_program_prepared_local_normalization_evidence(
        prepared,
        wire.length(),
        100000,
        64,
      ).unwrap(),
    ),
  )
  let (foreign, foreign_input) = original_node_normalization_parent()
  let foreign_holder = client_program_borrow_request_program_plan_input(
    foreign, foreign_input,
  ).unwrap()
  let foreign_prepared = client_program_preparation_borrow_read(foreign_holder).unwrap()
  assert_true(
    client_program_prepared_local_normalization_evidence(
      foreign_prepared, 1000000, 100000, 64,
    )
    is Err(ForeignPreparation),
  )
  ignore(client_program_abort_request_preparation(foreign))
  assert_true(
    client_program_preparation_borrow_retirement_started(foreign_holder),
  )
  ignore(client_program_preparation_borrow_return(foreign_holder).unwrap())
  client_program_abort_request_preparation(foreign).unwrap()
  ignore(client_program_abort_request_preparation(parent))
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  ignore(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}

///|
// Real Core callbacks isolate the imported Runtime evidence wrapper without a
// new Common build, fake evidence representation or private function extraction.
extern "js" fn original_node_normalization_runtime_view(
  loader : RequestDiagnosticTestLoader,
  prepared : @publication_host.PreparedClientProgram,
  expected : @publication.RunEvidenceValue,
  project : (@publication_host.PreparedClientProgram, Int, Int, Int) -> Result[
    @publication.RunEvidenceValue,
    @publication_host.ClientLocalNormalizationIssue,
  ],
  name : (@publication.RunEvidenceValue) -> String,
  identity : (@publication.RunEvidenceValue) -> String,
  wire : (@publication.RunEvidenceValue) -> String,
  remote_kind : () -> String,
) -> Bool =
  #|(loader,prepared,expected,project,name,identity,wire,remoteKind)=>{const {runtimeCore}=loader('../../../../../adapters/host-common/runtime-core.mjs');let calls=0;const moon={strategyRemoteManagedOutputEvidenceKind:remoteKind,clientProgramPreparedLocalNormalizationEvidence(actual,...bounds){if(this!==moon||actual!==prepared)throw Error('ForeignNormalizationOriginal');calls++;return project(actual,...bounds);},strategyRunEvidenceName:name,strategyRunEvidenceIdentity:identity,strategyRunEvidenceJson:wire};const control=runtimeCore(moon).publicationControl;const view=control.preparedClientNormalizationEvidence(prepared,{maxWireBytes:1000000,maxNodes:100000,maxDepth:64});return calls===1&&Object.isFrozen(view)&&view.name===name(expected)&&view.identity===identity(expected)&&view.wire===wire(expected);}

///|
test "actual original normalization enters the imported Runtime evidence wrapper once" {
  let (parent, input) = original_node_normalization_parent()
  client_program_prepare_request_program_normalization(parent, input).unwrap()
  |> ignore
  let holder = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let expected = client_program_prepared_local_normalization_evidence(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  assert_true(
    original_node_normalization_runtime_view(
      request_diagnostic_test_loader(request_diagnostic_test_url()),
      prepared,
      expected,
      (original, bytes, nodes, depth) => {
        client_program_prepared_local_normalization_evidence(
          original, bytes, nodes, depth,
        )
      },
      value => @publication.run_evidence_value_name(value),
      value => @publication.run_evidence_value_identity(value),
      value => @publication.run_evidence_value_json(value),
      () => strategy_remote_managed_output_evidence_kind(),
    ),
  )
  ignore(client_program_abort_request_preparation(parent))
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  ignore(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}

///|
test "original normalization survives the actual Module constructor on the same Request" {
  let (parent, input) = original_node_normalization_parent()
  client_program_prepare_request_program_normalization(parent, input).unwrap()
  |> ignore
  let holder = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let before = client_program_prepared_local_normalization_evidence(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  client_program_prepare_request_program_module_body(
    parent,
    input,
    contracts,
    false,
    None,
    None,
  ).unwrap()
  assert_true(
    physical_equal(
      prepared,
      client_program_preparation_borrow_read(holder).unwrap(),
    ),
  )
  let after = client_program_prepared_local_normalization_evidence(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  assert_true(physical_equal(before, after))
  ignore(client_program_abort_request_preparation(parent))
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  ignore(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}

///|
test "adopted ordinary Run preserves the same original normalization evidence" {
  let (parent, input) = original_node_normalization_parent()
  client_program_prepare_request_program_normalization(parent, input).unwrap()
  |> ignore
  let holder = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let before = client_program_prepared_local_normalization_evidence(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  client_program_prepare_request_program_module_body(
    parent,
    input,
    contracts,
    false,
    None,
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "node-normalization-original",
  ).unwrap()
  let run = client_program_adopt_request_program_preparation(parent, request).unwrap()
  assert_true(client_program_preparation_borrow_return(holder) is Ok(false))
  let after = client_program_prepared_local_normalization_evidence(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  assert_true(physical_equal(before, after))
  @client_local_host.retire_installed_managed_run(run).unwrap()
}
