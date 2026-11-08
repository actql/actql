///|
// Read the SAME published-Catalog lowerer cause, with no replacement outcome.
fn request_dedupe_original_lowering_cause(
  issue : @client_local_host.ClientRequestQueryLoweringIssue,
) -> String {
  match issue {
    WithBinding(original, _)
    | BindingFailure(original, _)
    | BindingException(original, _) =>
      request_dedupe_original_lowering_cause(original)
    Publication(
      Frontend(
        QueryLowering(
          BindingPreparation(
            SourceProgram(
              Program(Pipeline(_, { kind: Event(Decode(MissingField)), .. }))
            )
          )
        )
      )
    )
    | Publication(
      Frontend(
        QueryLowering(
          BindingPreparationSource(
            SourceProgram(
              Program(Pipeline(_, { kind: Event(Decode(MissingField)), .. }))
            ),
            _
          )
        )
      )
    ) => "event_decode_missing_field"
    _ => "other_original_lowering"
  }
}

///|
extern "js" fn request_dedupe_original_fixture_captured(
  loader : RequestDiagnosticTestLoader,
  sibling : Bool,
) -> NativeJsonValue =
  #|(loader,sibling)=>{const {eventDedupeSourceRefusals,eventDedupeSourceSuccesses}=loader('../../../../../scripts/fixtures/event-dedupe-source-input.mjs');const fixture=sibling?eventDedupeSourceSuccesses.find(item=>item.name==='event-dedupe-text-global'):eventDedupeSourceRefusals.find(item=>item.name==='event-dedupe-missing-null-placement');if(!fixture)throw new Error('MissingOriginalDedupeFixture');let text=fixture.text;if(!sibling){if(!text.startsWith('WITH rows AS ('))throw new Error('ChangedOriginalDedupePrefix');text=text.replace('WITH rows AS (','WITH `rows` AS (');}return {kind:'aql',input:{format:fixture.format,text},parameters:null};}

///|
extern "js" fn request_dedupe_original_fixture_source(
  captured : NativeJsonValue,
) -> NativeJsonValue =
  #|(captured)=>captured.input

///|
// Preserve the SAME original Result across the existing exported ABI.
// The quoted diagnostic is distinct from the retained original CI input.
extern "js" fn request_dedupe_original_fixture_public_error(
  loader : RequestDiagnosticTestLoader,
  result : Result[String, @client_local_host.ClientRequestTerminalIssue],
  project : (Result[String, @client_local_host.ClientRequestTerminalIssue]) -> String?,
) -> Bool =
  #|(loader,result,project)=>{const {checkedRequestProgramPreparation}=loader('../../../../../adapters/host-node/client-program-preparation.mjs');const {runtimeField}=loader('../../../../../adapters/host-common/compiler-binding.generated.mjs');const {eventDedupeSourceRefusals}=loader('../../../../../scripts/fixtures/event-dedupe-source-input.mjs');const fixture=eventDedupeSourceRefusals.find(item=>item.name==='event-dedupe-missing-null-placement');let calls=0;try{checkedRequestProgramPreparation({clientProgramRequestPreparationIssueCode(value){calls++;if(value!==result)throw new Error('SubstitutedResult');return project(value);}},result);return false;}catch(error){return calls===1&&error.code===fixture.expectedCode&&error.cause===runtimeField(result,0);}}

///|
test "Request quoted Dedupe missing null placement retains its typed public refusal" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let captured = request_dedupe_original_fixture_captured(loader, false)
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let checked = client_program_prepare_request_source_computation(
    parent,
    receipt,
    request_dedupe_original_fixture_source(captured),
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
  let original_cause = match result {
    Err(QueryLowering(issue)) => request_dedupe_original_lowering_cause(issue)
    Err(QuerySyntax(Request(issue))) =>
      "query_syntax_request/" + issue.to_repr().to_string()
    Err(QuerySyntax(Work(issue))) =>
      "query_syntax_work/" + issue.to_repr().to_string()
    Err(QuerySyntax(Frontend(_))) => "query_syntax_frontend"
    Err(QuerySyntax(Overflow)) => "query_syntax_overflow"
    Err(Preparation(_)) => "preparation"
    Err(CheckOutcome(_)) => "check_outcome"
    Err(Publication(_)) => "publication"
    Ok(_) => "prepared"
  }
  let code = client_program_request_preparation_issue_code(result)
  let public_error = request_dedupe_original_fixture_public_error(
    loader, result, client_program_request_preparation_issue_code,
  )
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(original_cause, "event_decode_missing_field")
  assert_eq(code, Some("source_invalid_input"))
  assert_true(public_error)
}

///|
// ONE unchanged existing accepted sibling checks this diagnostic setup only.
test "Request original accepted Dedupe sibling validates the same input setup" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let captured = request_dedupe_original_fixture_captured(loader, true)
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let checked = client_program_prepare_request_source_computation(
    parent,
    receipt,
    request_dedupe_original_fixture_source(captured),
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
  client_program_abort_request_preparation(parent).unwrap()
  assert_true(result is Ok("effect_free"))
}
