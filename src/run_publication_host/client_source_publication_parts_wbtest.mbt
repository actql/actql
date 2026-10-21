///|
test "portable Source publication parts preserve public and legacy primary recipes" {
  let legacy = original_dispatch_source("SELECT 1 AS n")
  let current = prepare_client_source_computation(
    legacy.intent,
    legacy.environment,
    legacy.publication,
    public_primary=true,
  ).unwrap()
  guard legacy.preparation is Pure(old) else { fail("Expected Pure legacy") }
  guard current.preparation is Pure(prepared) else { fail("Expected Pure public") }
  assert_eq(prepared_client_result_name(old, 0), Some("answer"))
  assert_eq(prepared_client_result_name(prepared, 0), Some("main"))
  assert_eq(client_source_computation_originals(current), client_source_computation_originals(legacy))
  assert_eq(client_source_computation_source(current), ("SELECT 1 AS n", "sql", None))
  assert_true(client_source_computation_matches(current, legacy.intent, legacy.environment))
  let copied_intent = prepare_client_submitted_intent(
    client_submitted_intent_wire(legacy.intent),
    65536,
    8192,
    64,
  ).unwrap()
  assert_false(client_source_computation_matches(current, copied_intent, legacy.environment))
}

///|
test "portable Source publication parts retain unused and foreign metadata refusals" {
  let original = original_dispatch_source("SELECT 1 AS n")
  let malformed = original.publication.slice(
    start=0,
    end=original.publication.length() - 1,
  ) + ",\"storeTargets\":null}"
  assert_true(
    prepare_client_source_computation(original.intent, original.environment, malformed)
    is Err(Publication(_)),
  )
  let foreign = original.publication.replace(
    old=@checked.checking_environment_cid(original.environment),
    new="sha256:" + "0".repeat(64),
  )
  assert_true(
    prepare_client_source_computation(original.intent, original.environment, foreign)
    is Err(Publication(_)),
  )
}
