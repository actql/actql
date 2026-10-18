///|
fn source_computation_intent(
  text : String,
  format? : String = "sql",
) -> @host.ClientSubmittedIntent {
  @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"text\":\"" +
    text +
    "\",\"format\":\"" +
    format +
    "\"},\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
}

///|
fn source_computation_publication(env : @checked.CheckEnvironment) -> String {
  "{\"environmentCid\":\"" +
  @checked.checking_environment_cid(env) +
  "\",\"aliases\":[]}"
}

///|
fn source_computation_failure(value : Result[LocalSourceComputation, LocalSourceComputationIssue]) -> String {
  match value {
    Ok(_) => "ready"
    Err(Input) => "input"
    Err(Publication(_)) => "publication"
    Err(Frontend(_)) => "frontend"
    Err(Syntax(_)) => "syntax"
    Err(Pure(_)) => "pure"
    Err(Effect(_)) => "effect"
    Err(ArrayProfile(_)) => "array"
    Err(TargetOriginalsUnavailable) => "target-originals"
    Err(ReadOnly) => "read-only"
    Err(Materials(_)) => "materials"
  }
}

///|
test "public SQL and AQL keep the original intent and one parsed preparation" {
  let env = environment()
  for
    (text, format) in [("SELECT 1 AS n", "sql"), ("SELECT 1 AS n", "aql-text")] {
    let intent = source_computation_intent(text, format~)
    let publication = source_computation_publication(env)
    let outcome = prepare_local_source_computation(intent, env, publication)
    guard outcome is Ok(original) else { fail(source_computation_failure(outcome)) }
    guard local_source_computation_preparation(original) is Pure(prepared) else {
      fail("Expected Pure")
    }
    assert_eq(@host.prepared_client_result_count(prepared), 1)
    assert_true(local_source_computation_matches(original, intent, env))
    assert_false(
      local_source_computation_matches(
        original,
        source_computation_intent(text, format~),
        env,
      ),
    )
    assert_false(
      local_source_computation_matches(original, intent, environment()),
    )
    let facts = local_source_computation_originals(original)
    assert_eq(facts.0, @host.client_submitted_intent_wire(intent))
    assert_eq(facts.1, @host.client_submitted_intent_cid(intent))
    assert_eq(facts.3, publication)
    let request = local_source_computation_request(
      original, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "source",
    ).unwrap()
    assert_eq(@host.client_request_input_cid(request), facts.1)
  }
}

///|
test "source preparation refuses mismatched publication and format without fallback" {
  let env = environment()
  let intent = source_computation_intent("SELECT 1 AS n")
  let mismatch = prepare_local_source_computation(
      intent, env, "{\"environmentCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"aliases\":[]}",
    )
  assert_true(mismatch is Err(Publication(_)), msg=source_computation_failure(mismatch))
  for format in ["json", "yaml", "unknown"] {
    assert_true(
      prepare_local_source_computation(
        source_computation_intent("SELECT 1 AS n", format~),
        env,
        source_computation_publication(env),
      )
      is Err(Input),
    )
  }
}

///|
test "source declarations and parameters come from the same admitted envelope" {
  let env = environment()
  let wire = "{\"kind\":\"aql\",\"input\":{\"text\":\"SELECT @n AS n\",\"format\":\"sql\",\"parameterDeclarations\":{\"n\":{\"type\":\"number\"}}},\"parameters\":{\"n\":3}}"
  let intent = @host.prepare_client_submitted_intent(wire, 65536, 8192, 64).unwrap()
  let original = prepare_local_source_computation(
    intent,
    env,
    source_computation_publication(env),
  ).unwrap()
  assert_eq(local_source_computation_material(original).1, Some("{\"n\":3}"))
  assert_eq(
    local_source_computation_originals(original).0,
    @host.client_submitted_intent_wire(intent),
  )
}
