///|
// Pure fixture DATA: only the fourteen remaining Common Graph callers.
extern "js" fn request_graph_tail_captured(
  loader : RequestDiagnosticTestLoader,
  name : String,
) -> NativeJsonValue =
  #|(loader,name)=>{const e=loader('../../../../../scripts/fixtures/graph-equality-source-input.mjs');const s=loader('../../../../../scripts/fixtures/graph-subtraction-source-input.mjs');const item=[...e.graphEqualitySourceSuccesses,...e.graphEqualitySourceRefusals,...s.graphSubtractionSourceRefusals].find(x=>x.name===name);if(!item||item.parameters!==undefined||item.parameterDeclarations!==undefined)throw new Error('ChangedRemainingGraphFixture');return {kind:'aql',input:{format:item.format,text:item.text},parameters:null};}

///|
test "remaining Common Graph callers retain actual published Request preparation verdicts" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let environment = @publication_host.admit_client_check_environment(
    node_closed_carrier_demand_environment,
    "sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261",
    { text_time: true, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
    graph=true,
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let prepared : Array[String] = []
  let rejected : Array[String] = []
  for
    name in [
      "graph-equality-common-unresolved-order", "graph-subtraction-string-peer",
      "graph-subtraction-list-peer", "graph-subtraction-empty-peer-list", "graph-subtraction-missing-peer",
      "graph-subtraction-unknown-peer", "graph-subtraction-relation-peer", "graph-subtraction-extra-argument",
      "graph-subtraction-lost-graph-scope", "graph-subtraction-forward-peer", "graph-subtraction-unknown-policy",
      "graph-subtraction-duplicate-node-policy", "graph-subtraction-duplicate-edge-policy",
      "graph-subtraction-strategy-value-is-not-vocabulary",
    ] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let captured = request_graph_tail_captured(loader, name)
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
    let code = client_program_request_preparation_issue_code(result)
    match result {
      Ok(kind) => {
        assert_eq(kind, "effect_free")
        prepared.push(name)
        println("GraphTailPreparation " + name + " prepared; no Run issued")
      }
      Err(_) => {
        rejected.push(name)
        println(
          "GraphTailPreparation " + name + " " + code.unwrap_or("undetermined"),
        )
      }
    }
    client_program_abort_request_preparation(parent).unwrap()
    if result is Err(_) {
      // A real semantic refusal, not foreign/current/Resource uncertainty.
      assert_true(code is Some(_))
    }
  }
  assert_eq(prepared, ["graph-equality-common-unresolved-order"])
  assert_eq(rejected.length(), 13)
}

///|
fn request_graph_tail_original_kind(
  issue : @client_local_host.ClientRequestQueryLoweringIssue,
) -> String {
  match issue {
    WithBinding(original, _)
    | BindingFailure(original, _)
    | BindingException(original, _) =>
      request_graph_tail_original_kind(original)
    Publication(
      Frontend(
        QueryLowering(
          BindingPreparation(SourceProgram(Program(Pipeline(_, detail))))
          | BindingPreparationSource(
            SourceProgram(Program(Pipeline(_, detail))),
            _
          )
        )
      )
    ) => detail.kind.to_repr().to_string()
    _ => "other_original_lowering"
  }
}

///|
extern "js" fn request_graph_tail_public_code(
  loader : RequestDiagnosticTestLoader,
  result : Result[String, @client_local_host.ClientRequestTerminalIssue],
  project : (Result[String, @client_local_host.ClientRequestTerminalIssue]) -> String?,
) -> String =
  #|(loader,result,project)=>{const {checkedRequestProgramPreparation}=loader('../../../../../adapters/host-node/client-program-preparation.mjs');const {runtimeField}=loader('../../../../../adapters/host-common/compiler-binding.generated.mjs');let calls=0;try{checkedRequestProgramPreparation({clientProgramRequestPreparationIssueCode(value){calls++;if(value!==result)throw new Error('SubstitutedResult');return project(value);}},result);return 'prepared';}catch(error){if(calls!==1||error.cause!==runtimeField(result,0))throw error;return error.code;}}

///|
test "remaining Graph strategy values retain typed original public input refusal" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let environment = @publication_host.admit_client_check_environment(
    node_closed_carrier_demand_environment,
    "sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261",
    { text_time: true, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
    graph=true,
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let codes : Array[String] = []
  for
    name in [
      "graph-subtraction-unknown-policy", "graph-subtraction-strategy-value-is-not-vocabulary",
    ] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let captured = request_graph_tail_captured(loader, name)
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
    let original = match result {
      Err(QueryLowering(issue)) => request_graph_tail_original_kind(issue)
      _ => "other_original_terminal"
    }
    let code = request_graph_tail_public_code(
      loader, result, client_program_request_preparation_issue_code,
    )
    client_program_abort_request_preparation(parent).unwrap()
    println("GraphTailPublicCause " + name + " " + original + " -> " + code)
    codes.push(code)
  }
  assert_eq(codes, ["ClientProgramInvalidInput", "ClientProgramInvalidInput"])
}
