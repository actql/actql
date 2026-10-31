///|
// Existing actual standard Resource parent fixture, with its declared capture
// envelope. This local typed recurrence does not retag installed b3 or recover
// an original public Host's error object.
test "normal actual intent finish retains the original SQL compiler continuation" {
  let environment = keyed_source_environment()
  let publication = client_program_prepare_public_source_environment(
    environment,
    "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let source = request_diagnostic_test_json(
    "{\"text\":\"SELECT 7 AS id\",\"format\":\"sql\"}",
  )
  let captured = request_diagnostic_test_json(
    "{\"kind\":\"aql\",\"input\":{\"text\":\"SELECT 7 AS id\",\"format\":\"sql\"},\"parameters\":null}",
  )
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let checked = client_program_prepare_request_source_computation(
    parent,
    receipt,
    source,
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
  match result {
    Err(@client_local_host.QuerySyntax(@client_local_host.Request(issue))) =>
      println(
        "Actual original typed query Request refusal: " +
        issue.to_repr().to_string(),
      )
    Err(@client_local_host.QuerySyntax(@client_local_host.Work(issue))) =>
      println(
        "Actual original typed query Work refusal: " +
        issue.to_repr().to_string(),
      )
    Err(issue) => {
      let original : Error = issue
      println(
        "Actual original typed intent/compiler refusal: " +
        Repr(original).to_string(),
      )
    }
    Ok(_) => ()
  }
  client_program_abort_request_preparation(parent).unwrap()
  assert_true(result is Ok("effect_free"))
}

///|
// The distinct native Program path consumes its own captured values after the
// original intent. No SQL success is promoted to a native or public outcome.
test "normal native Program after original intent keeps typed preparation and original identity" {
  let environment = keyed_source_environment()
  let publication = client_program_prepare_public_source_environment(
    environment,
    "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"root.normal_source_free","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":2,"label":"東京"},{"id":1,"label":"é"}]},"as":"rows"},{"from":"rows","sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["id","label"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let captured = request_diagnostic_test_json(
    "{\"kind\":\"program\",\"input\":" + document + " ,\"parameters\":null}",
  )
  let (parent, receipt) = request_diagnostic_test_parent()
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let intent = client_program_request_submitted_intent_original(parent, receipt).unwrap()
  let checked = client_program_prepare_request_native_computation(
    parent,
    receipt,
    request_diagnostic_test_json(document),
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
  let same_intent = client_program_request_submitted_intent_original(
    parent, receipt,
  )
  client_program_abort_request_preparation(parent).unwrap()
  assert_true(result is Ok("effect_free"))
  assert_true(same_intent is Some(value) && physical_equal(value, intent))
  assert_true(
    client_program_request_submitted_intent_original(parent, receipt) is None,
  )
}
