///|
// Match the SAME retained production Request cause, not a reconstructed result.
fn request_subgraph_original_cause(
  issue : @client_local_host.ClientRequestQueryLoweringIssue,
) -> String {
  match issue {
    WithBinding(original, _)
    | BindingFailure(original, _)
    | BindingException(original, _) => request_subgraph_original_cause(original)
    Publication(
      Frontend(
        QueryLowering(
          BindingPreparation(
            SourceProgram(
              Program(
                Pipeline(
                  _,
                  { kind: GraphMatch(Structure(UnsupportedGraphOperation)), .. }
                )
              )
            )
          )
          | BindingPreparationSource(
            SourceProgram(
              Program(
                Pipeline(
                  _,
                  { kind: GraphMatch(Structure(UnsupportedGraphOperation)), .. }
                )
              )
            ),
            _
          )
        )
      )
    ) => "checked_subgraph_support_gap"
    Publication(
      Frontend(
        QueryLowering(
          BindingPreparation(SourceProgram(Program(Pipeline(_, _))))
          | BindingPreparationSource(SourceProgram(Program(Pipeline(_, _))), _)
        )
      )
    ) => "other_original_pipeline_refusal"
    _ => "other_original_request_cause"
  }
}

///|
extern "js" fn request_subgraph_original_fixture_captured(
  loader : RequestDiagnosticTestLoader,
  name : String,
) -> NativeJsonValue =
  #|(loader,name)=>{const {subgraphSourceRefusals}=loader('../../../../../scripts/fixtures/subgraph-source-input.mjs');const fixture=subgraphSourceRefusals.find(item=>item.name===name);if(!fixture)throw new Error('MissingOriginalSubgraphFixture');return {kind:'aql',input:{format:fixture.format,text:fixture.text},parameters:null};}

///|
extern "js" fn request_subgraph_original_fixture_source(
  captured : NativeJsonValue,
) -> NativeJsonValue =
  #|(captured)=>captured.input

///|
// Existing adapter projection receives the SAME original Result and cause.
extern "js" fn request_subgraph_original_public_error(
  loader : RequestDiagnosticTestLoader,
  result : Result[String, @client_local_host.ClientRequestTerminalIssue],
  project : (Result[String, @client_local_host.ClientRequestTerminalIssue]) -> String?,
) -> Bool =
  #|(loader,result,project)=>{const {checkedRequestProgramPreparation}=loader('../../../../../adapters/host-node/client-program-preparation.mjs');const {runtimeField}=loader('../../../../../adapters/host-common/compiler-binding.generated.mjs');const {subgraphSourceRefusals}=loader('../../../../../scripts/fixtures/subgraph-source-input.mjs');const fixture=subgraphSourceRefusals.find(item=>item.name==='subgraph-common-where-selector-gap');let calls=0;try{checkedRequestProgramPreparation({clientProgramRequestPreparationIssueCode(value){calls++;if(value!==result)throw new Error('SubstitutedResult');return project(value);}},result);return false;}catch(error){return calls===1&&error.code===fixture.expectedCode&&error.cause===runtimeField(result,0);}}

///|
test "Request published Subgraph support gap retains original typed cause and public refusal" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    graph=true,
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let captured = request_subgraph_original_fixture_captured(
    loader, "subgraph-common-where-selector-gap",
  )
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let checked = client_program_prepare_request_source_computation(
    parent,
    receipt,
    request_subgraph_original_fixture_source(captured),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  let result = match checked {
    Ok(_) =>
      client_program_finish_request_computation(
        parent, receipt, environment, publication,
      )
    Err(issue) => Err(issue)
  }
  let cause = match result {
    Err(QueryLowering(issue)) => request_subgraph_original_cause(issue)
    _ => "other_original_request_terminal"
  }
  let code = client_program_request_preparation_issue_code(result)
  let public_error = request_subgraph_original_public_error(
    loader, result, client_program_request_preparation_issue_code,
  )
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(cause, "checked_subgraph_support_gap")
  assert_eq(code, Some("source_implementation_limit"))
  assert_true(public_error)
}

///|
test "Request published malformed Subgraph stays protected and authority remains separate" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    graph=true,
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  for
    name in [
      "subgraph-empty-explicit-ids", "subgraph-wrong-key-type", "subgraph-nonboolean-edge-predicate",
    ] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let captured = request_subgraph_original_fixture_captured(loader, name)
    client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
    |> ignore
    client_program_finish_request_submitted_intent(parent, receipt).unwrap()
    let checked = client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_subgraph_original_fixture_source(captured),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
    let result = match checked {
      Ok(_) =>
        client_program_finish_request_computation(
          parent, receipt, environment, publication,
        )
      Err(issue) => Err(issue)
    }
    let cause = match result {
      Err(QueryLowering(issue)) => request_subgraph_original_cause(issue)
      _ => "other_original_request_terminal"
    }
    let code = client_program_request_preparation_issue_code(result)
    @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(cause, "other_original_pipeline_refusal")
    assert_eq(code, Some("source_rejected"))
  }
  let (parent, receipt) = request_diagnostic_test_parent()
  let captured = request_subgraph_original_fixture_captured(
    loader, "subgraph-common-where-selector-gap",
  )
  let foreign = client_program_prepare_request_source_computation(
    parent,
    request_diagnostic_test_receipt(),
    request_subgraph_original_fixture_source(captured),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  assert_true(foreign is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(foreign), None)
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  let retired = client_program_prepare_request_source_computation(
    parent,
    receipt,
    request_subgraph_original_fixture_source(captured),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  assert_true(retired is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(retired), None)
}
