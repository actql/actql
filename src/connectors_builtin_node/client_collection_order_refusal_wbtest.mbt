///|
fn original_collection_order_sql(tail : String) -> String {
  "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) " +
  tail
}

///|
fn original_collection_order_issue(sql : String) -> String? {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let result = client_program_prepare_request_source_computation(
    parent,
    receipt,
    request_diagnostic_test_json(
      "{\"format\":\"sql\",\"text\":\"" + sql + "\"}",
    ),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  let code = request_diagnostic_checked_issue_code(result)
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  code
}

///|
test "original unordered collection Request causes require local aggregate ORDER BY" {
  for
    tail in [
      "SELECT STRING_AGG(s, ',') AS x FROM t", "SELECT n, STRING_AGG(s, ',') AS x FROM t GROUP BY n",
      "SELECT ARRAY_AGG(n) AS x FROM t",
    ] {
    assert_eq(
      original_collection_order_issue(original_collection_order_sql(tail)),
      Some("ClientProgramAggregateOrderRequired"),
    )
  }
}

///|
test "original ordered unkeyed ARRAY Request retains the general unresolved order cause" {
  assert_eq(
    original_collection_order_issue(
      original_collection_order_sql(
        "SELECT ARRAY_AGG(n ORDER BY n) AS x FROM t",
      ),
    ),
    Some("ClientProgramOrderUnresolved"),
  )
}

///|
test "authored diagnostic text cannot manufacture a typed aggregate order cause" {
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(
        QuerySyntax({
          issue: Syntax("ARRAY_AGG requires aggregate ORDER BY"),
          span: None,
        }),
      ),
    ),
    "source_invalid_input",
  )
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(
        QuerySyntax({
          issue: Syntax("STRING_AGG requires aggregate ORDER BY"),
          span: None,
        }),
      ),
    ),
    "source_invalid_input",
  )
}

///|
extern "js" fn original_collection_order_public_refusal(
  loader : RequestDiagnosticTestLoader,
  result : Result[Unit, @client_local_host.ClientRequestTerminalIssue],
  project : (Result[Unit, @client_local_host.ClientRequestTerminalIssue]) -> String?,
  expected : String,
  outer : String,
) -> Bool =
  #|(loader,result,project,expected,outer)=>{const {checkedRequestProgramPreparation,requestProgramPreparationProblemCode,requestProgramPreparationRefusalCode}=loader('../../../../../adapters/host-node/client-program-preparation.mjs');const {runtimeField}=loader('../../../../../adapters/host-common/compiler-binding.generated.mjs');let calls=0;try{checkedRequestProgramPreparation({clientProgramRequestPreparationIssueCode(actual){if(actual!==result)throw Error('SubstitutedResult');calls++;return project(actual);}},result);return false;}catch(error){return calls===1&&error.code===outer&&error.cause===runtimeField(result,0)&&requestProgramPreparationProblemCode(error)===expected&&requestProgramPreparationRefusalCode(error)===outer&&requestProgramPreparationProblemCode({...error})===undefined;}}

///|
test "original collection Core causes enter the same Node association with unchanged classifications" {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  for
    (tail, expected, outer) in [
      (
        "SELECT STRING_AGG(s, ',') AS x FROM t", "ClientProgramAggregateOrderRequired",
        "ClientProgramInvalidInput",
      ),
      (
        "SELECT ARRAY_AGG(n ORDER BY n) AS x FROM t", "ClientProgramOrderUnresolved",
        "ClientProgramRejected",
      ),
    ] {
    let sql = original_collection_order_sql(tail)
    let (parent, receipt) = request_diagnostic_test_parent()
    let result = client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_diagnostic_test_json(
        "{\"format\":\"sql\",\"text\":\"" + sql + "\"}",
      ),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
    assert_true(result is Err(_))
    assert_true(
      original_collection_order_public_refusal(
        request_diagnostic_test_loader(request_diagnostic_test_url()),
        result,
        original => request_diagnostic_checked_issue_code(original),
        expected,
        outer,
      ),
    )
    @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  }
}
