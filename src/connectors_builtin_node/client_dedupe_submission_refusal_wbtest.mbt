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
    "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
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
    "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
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
  let reason = match result {
    Err(QueryLowering(Request(issue))) =>
      "query_lowering_request/" + issue.to_repr().to_string()
    Err(QueryLowering(Overflow)) => "query_lowering_overflow"
    Err(QueryLowering(issue)) => request_dedupe_original_lowering_cause(issue)
    Err(QuerySyntax(Request(issue))) =>
      "query_syntax_request/" + issue.to_repr().to_string()
    Err(Preparation(issue)) => "preparation/" + issue.to_repr().to_string()
    Err(_) => "other preparation refusal"
    Ok(kind) => kind
  }
  assert_true(result is Ok("effect_free"), msg=reason)
}

///|
extern "js" fn request_positional_analytic_original_fixture(
  loader : RequestDiagnosticTestLoader,
) -> NativeJsonValue =
  #|(loader)=>{const {setCorrespondingSuccesses}=loader('../../../../../scripts/fixtures/set-corresponding-source-input.mjs');const fixture=setCorrespondingSuccesses.find(item=>item.name==='set-corresponding-positional-anonymous-analytic-scoped-pipe');if(!fixture||fixture.sourceRows.length!==0)throw new Error('ChangedOriginalPositionalAnalyticFixture');return {kind:'aql',input:{format:fixture.format,text:fixture.text},parameters:null};}

///|
test "Request original scoped positional analytic prepares with ordinary limits" {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
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
  let captured = request_positional_analytic_original_fixture(loader)
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let result = match
    client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_dedupe_original_fixture_source(captured),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ) {
    Ok(_) =>
      client_program_finish_request_computation(
        parent, receipt, environment, publication,
      )
    Err(issue) => Err(issue)
  }
  client_program_abort_request_preparation(parent).unwrap()
  let reason = match result {
    Err(QueryLowering(Request(issue))) =>
      "query_lowering_request/" + issue.to_repr().to_string()
    Err(QueryLowering(Publication(_))) => "query_lowering_publication"
    Err(Preparation(issue)) => @debug.to_string(issue)
    Err(QuerySyntax(Request(issue))) =>
      "query_syntax_request/" + issue.to_repr().to_string()
    Err(_) => "other preparation refusal"
    Ok(kind) => kind
  }
  assert_true(result is Ok("effect_free"), msg=reason)
}

///|
extern "js" fn request_original_corresponding_fixture(
  loader : RequestDiagnosticTestLoader,
  name : String,
) -> NativeJsonValue =
  #|(loader,name)=>{const {setCorrespondingRefusals,setCorrespondingSuccesses}=loader('../../../../../scripts/fixtures/set-corresponding-source-input.mjs');const fixture=setCorrespondingRefusals.find(item=>item.name===name)??setCorrespondingSuccesses.find(item=>item.name===name);if(!fixture||(fixture.sourceRows?.length??0)!==0)throw new Error('ChangedOriginalCorrespondingFixture');return {kind:'aql',input:{format:fixture.format,text:fixture.text},parameters:null};}

///|
extern "js" fn request_corresponding_publication_fixture(
  loader : RequestDiagnosticTestLoader,
  field : String,
) -> String =
  #|(loader, field) => {
  #|  const {readFileSync} = loader('node:fs');
  #|  const {createHash} = loader('node:crypto');
  #|  const {canonicalJson} = loader('../../../../../adapters/host-node/local-account-config.mjs');
  #|  const {configurePublicQueryEvidenceContracts} = loader('../../../../../scripts/fixtures/public-query-cases.mjs');
  #|  const read = path => JSON.parse(readFileSync(loader.resolve('../../../../../' + path), 'utf8'));
  #|  if (field === 'numeric_cid') {
  #|    const profile = read('spec/contracts/actql-numeric-reduction.json');
  #|    return 'sha256:' + createHash('sha256').update(canonicalJson(profile)).digest('hex');
  #|  }
  #|  const environment = read('adapters/host-node/fixtures/query-amount-environment.json');
  #|  environment.host_policy_profile = read('spec/local-check-environment.json').host_policy_profile;
  #|  configurePublicQueryEvidenceContracts(environment);
  #|  delete environment.evidence_bundle_cid;
  #|  const cid = 'sha256:' + createHash('sha256').update(canonicalJson(environment)).digest('hex');
  #|  environment.evidence_bundle_cid = cid;
  #|  const view = environment.source_views[0];
  #|  if (field === 'environment') return canonicalJson(environment);
  #|  if (field === 'cid') return cid;
  #|  return canonicalJson({environmentCid: cid, aliases: [{name: 'records',
  #|    sourceRef: 'connector://crm/main/r#v', sourceViewContractCid: view.contract_cid,
  #|    schemaContractCid: view.output.schema.cid}]});
  #|}

///|
extern "js" fn request_corresponding_refusal_keeps_cause(
  loader : RequestDiagnosticTestLoader,
  result : Result[String, @client_local_host.ClientRequestTerminalIssue],
  project : (Result[String, @client_local_host.ClientRequestTerminalIssue]) -> String?,
) -> Bool =
  #|(loader, result, project) => {
  #|  const {checkedRequestProgramPreparation} = loader('../../../../../adapters/host-node/client-program-preparation.mjs');
  #|  const {runtimeField} = loader('../../../../../adapters/host-common/compiler-binding.generated.mjs');
  #|  try { checkedRequestProgramPreparation({clientProgramRequestPreparationIssueCode: project}, result); }
  #|  catch (error) {
  #|    return error.code === 'ClientProgramImplementationLimit' && error.cause === runtimeField(result, 0);
  #|  }
  #|  return false;
  #|}

///|
fn check_request_original_corresponding_fixture(
  name : String,
  refusal : Bool,
  numeric? : Bool = false,
) -> Unit raise {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  let environment = @publication_host.admit_client_check_environment(
    request_corresponding_publication_fixture(loader, "environment"),
    request_corresponding_publication_fixture(loader, "cid"),
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: true, calendar: false, text_rank: false, },
    numeric_profile_cid=if numeric {
      Some(request_corresponding_publication_fixture(loader, "numeric_cid"))
    } else {
      None
    },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    request_corresponding_publication_fixture(loader, "publication"),
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let captured = request_original_corresponding_fixture(loader, name)
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let result = match
    client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_dedupe_original_fixture_source(captured),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ) {
    Ok(_) =>
      client_program_finish_request_computation(
        parent, receipt, environment, publication,
      )
    Err(issue) => Err(issue)
  }
  client_program_abort_request_preparation(parent).unwrap()
  let reason = match result {
    Err(QueryLowering(Request(issue))) =>
      "query_lowering_request/" + issue.to_repr().to_string()
    Err(QueryLowering(Publication(_))) => "query_lowering_publication"
    Err(Preparation(issue)) => @debug.to_string(issue)
    Err(QuerySyntax(Request(issue))) =>
      "query_syntax_request/" + issue.to_repr().to_string()
    Err(CheckOutcome(Rejected(issue))) =>
      "check_rejected/" +
      @debug.to_string(@program_check.diagnostic_category(issue))
    Err(CheckOutcome(NeedsInputs(_))) => "check_needs_inputs"
    Err(QueryLowering(_)) => "query_lowering_wrapped"
    Err(_) => "other preparation refusal"
    Ok(kind) => kind
  }
  if refusal {
    assert_true(
      result
      is Err(
        QueryLowering(
          Publication(Frontend(QueryLowering(UnsupportedProjection)))
        )
      ),
      msg=reason,
    )
    assert_eq(
      client_program_request_preparation_issue_code(result),
      Some("source_implementation_limit"),
    )
    assert_true(
      request_corresponding_refusal_keeps_cause(
        loader, result, client_program_request_preparation_issue_code,
      ),
    )
  } else {
    assert_true(result is Ok("effect_free"), msg=reason)
  }
}

///|
test "Request original parenthesized BY NAME refusal retains its typed cause" {
  check_request_original_corresponding_fixture(
    "set-corresponding-refuse-parenthesized-by-name", true,
  )
}

///|
test "Request original parenthesized nested set prepares with ordinary limits" {
  check_request_original_corresponding_fixture(
    "set-corresponding-positional-parenthesized-nested-set", false,
  )
}

///|
test "Request double-parenthesized anonymous aggregate prepares with ordinary limits" {
  check_request_original_corresponding_fixture(
    "set-corresponding-positional-parenthesized-anonymous-aggregate",
    false,
    numeric=true,
  )
}
