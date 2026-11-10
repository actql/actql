///|
extern "js" fn planner_fixture_requirement_input(
  loader : RequestDiagnosticTestLoader,
  filter : String,
) -> String =
  #|(loader,filter)=>loader('../../../../../scripts/fixtures/planner-selection-public-query.mjs').plannerSelectionProgram(filter)

///|
extern "js" fn planner_fixture_requirement_environment(
  loader : RequestDiagnosticTestLoader,
) -> String =
  #|loader=>{const f=loader('../../../../../adapters/host-node/fixtures/two-source/left.environment.json');return loader('../../../../../scripts/fixtures/two-source-public-query.mjs').canonical(f);}

///|
extern "js" fn planner_fixture_requirement_environment_cid(
  loader : RequestDiagnosticTestLoader,
) -> String =
  #|loader=>loader('../../../../../adapters/host-node/fixtures/two-source/left.environment.json').evidence_bundle_cid

///|
extern "js" fn planner_fixture_requirement_expected(
  loader : RequestDiagnosticTestLoader,
  filter : String,
  field : String,
) -> String =
  #|(loader,filter,field)=>{const v=Object.values(loader('../../../../../scripts/fixtures/planner-selection-requirement-preimages.json')).find(x=>x.filter===filter);if(!v)throw new Error('MissingIndependentPlannerVector');return field==='cid'?v.cid:loader('../../../../../scripts/fixtures/two-source-public-query.mjs').canonical(v[field]);}

///|
// Existing pure Request and requirement owners only. This does not create a
// Run, choose acquisition costs, grant a provider read or execute a query.
test "planner fixture requirements retain complete original preimages" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let environment = @publication_host.admit_client_check_environment(
    planner_fixture_requirement_environment(loader),
    planner_fixture_requirement_environment_cid(loader),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for filter in ["amount >= 20", "id + 1 > 2"] {
    let (parent, receipt) = request_diagnostic_test_parent()
    client_program_prepare_request_native_computation(
      parent,
      receipt,
      request_diagnostic_test_json(
        planner_fixture_requirement_input(loader, filter),
      ),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ).unwrap()
    assert_eq(
      client_program_finish_request_computation(
        parent, receipt, environment, publication,
      ).unwrap(),
      "effect_free",
    )
    let held = client_program_borrow_request_program_plan_input(parent, receipt).unwrap()
    let prepared = client_program_preparation_borrow_read(held).unwrap()
    let requirement = client_program_prepare_local_query_requirement(
      prepared,
      0,
      0,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    assert_eq(
      @encode.document_text(@planning.query_requirement_document(requirement)),
      planner_fixture_requirement_expected(loader, filter, "requirement"),
    )
    assert_eq(
      @planning.query_requirement_cid(requirement),
      planner_fixture_requirement_expected(loader, filter, "cid"),
    )
    assert_eq(
      client_program_definition_json(prepared).unwrap(),
      planner_fixture_requirement_expected(loader, filter, "programDefinition"),
    )
    assert_eq(
      client_program_semantics_json(prepared).unwrap(),
      planner_fixture_requirement_expected(loader, filter, "programSemantics"),
    )
    println("PlannerFixtureRequirementFilter " + filter)
    println(
      "PlannerFixtureProgramDefinition " +
      client_program_definition_json(prepared).unwrap(),
    )
    println(
      "PlannerFixtureProgramSemantics " +
      client_program_semantics_json(prepared).unwrap(),
    )
    for stage in [0, 1] {
      println(
        "PlannerFixtureStageSemantics " +
        stage.to_string() +
        " " +
        client_program_stage_semantics_json(prepared, stage).unwrap(),
      )
    }
    println(
      "PlannerFixtureRequirementPreimage " +
      @encode.document_text(@planning.query_requirement_document(requirement)),
    )
    println(
      "PlannerFixtureRequirementCid " +
      @planning.query_requirement_cid(requirement),
    )
    client_program_preparation_borrow_return(held).unwrap() |> ignore
    client_program_abort_request_preparation(parent).unwrap()
  }
}
