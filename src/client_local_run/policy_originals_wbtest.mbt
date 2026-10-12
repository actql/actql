///|
// Independent Native custody format and normative policy preimage. Expected
// bytes are fixed from the contract, not copied from the codec under test.
let policy_original_packet : String = "{\"bodies\":[{\"body\":\"{\\\"classification\\\":\\\"unknown\\\",\\\"source_data_policy_cids\\\":[],\\\"source_response_policy_cids\\\":[],\\\"unknown_provenance\\\":true,\\\"version\\\":\\\"actql-effective-data-policy/0.1\\\"}\",\"cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\",\"kind\":\"data_policy\"}],\"root_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"}"

///|
test "original policy packet has exact bounded Native custody bytes" {
  for
    input in [
      prepared(@input.Aql("SELECT 1 AS n")),
      prepared(@input.Program(program)),
    ] {
    let plan = source_free_policy_plan(input).unwrap()
    let wire = @host.issue_client_run_policy_originals(
      plan.prepared,
      compiled=local_run_compiled(plan),
    ).unwrap()
    assert_eq(wire, policy_original_packet)
    let bodies = @host.read_client_run_policy_originals(wire).unwrap()
    assert_eq(bodies.length(), 1)
    assert_eq(
      @publication.captured_effect_dependency_body_kind(bodies[0]),
      "data_policy",
    )
    assert_eq(
      @publication.captured_effect_dependency_body_cid(bodies[0]),
      source_free_original_policy_cid,
    )
    assert_eq(
      @publication.captured_effect_dependency_body_json(bodies[0]),
      source_free_original_policy,
    )
    assert_true(
      physical_equal(
        @host.client_compiled_run_admission(local_run_compiled(plan)),
        plan.admission,
      ),
    )
  }
}

///|
test "policy packet cannot manufacture missing or foreign compiled originals" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let original = source_free_policy_plan(input).unwrap()
  assert_true(
    @host.issue_client_run_policy_originals(original.prepared)
    is Err(PublicationPolicy(_)),
  )
  let foreign = source_free_policy_plan(prepared(@input.Aql("SELECT 2 AS n"))).unwrap()
  assert_true(
    @host.issue_client_run_policy_originals(
      original.prepared,
      compiled=local_run_compiled(foreign),
    )
    is Err(ForeignRun),
  )
  let missing = plan(input, "missing-original")
  assert_true(
    @host.issue_client_run_policy_originals(
      missing.prepared,
      compiled=local_run_compiled(missing),
    )
    is Err(PublicationPolicy(_)),
  )
}

///|
test "policy packet refuses substituted root and altered body CID" {
  let wrong = "sha256:" + "f".repeat(64)
  // Replace only the last root reference, preserving a valid original body.
  let end = policy_original_packet.length() -
    source_free_original_policy_cid.length() -
    2
  let altered_root = policy_original_packet[0:end].to_owned() + wrong + "\"}"
  assert_true(
    @host.read_client_run_policy_originals(altered_root) is Err(CustodyLost),
  )
  let altered_body = policy_original_packet.replace(
    old=source_free_original_policy_cid,
    new=wrong,
  )
  assert_true(
    @host.read_client_run_policy_originals(altered_body) is Err(CustodyLost),
  )
}

///|
test "policy packet rejects unknown fields duplicate keys and missing body" {
  for
    wire in [
      "{\"bodies\":[],\"root_policy_cid\":\"x\"}",
      "{\"bodies\":[],\"bodies\":[],\"root_policy_cid\":\"x\"}",
      "{\"bodies\":[],\"root_policy_cid\":\"x\",\"accepted\":true}",
      "null",
      " ".repeat(65537),
    ] {
    assert_true(
      @host.read_client_run_policy_originals(wire) is Err(CustodyLost),
    )
  }
}
