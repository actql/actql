///|
test "response policy emission binds selected contracts and respects sink limits" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = remote_construction_fixture(budget)
  let value = units[0].source_execution[0].subject.response_policy
  let authority = @environment.source_view_data_policy(value.authoritative)
  let policy_cid = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  assert_eq(
    @environment.contract_identity(@environment.data_policy_envelope(authority)).2,
    policy_cid,
  )
  assert_true(
    @environment.member_cid(
      @environment.contract_member(@environment.data_policy_envelope(authority)),
    ) !=
    policy_cid,
  )
  let source_cid = @sourceviews.selected_cid(value.source)
  let expected = "{\"classification\":\"unknown\",\"minimum_classification\":null,\"source_data_policy_cid\":\"" +
    policy_cid +
    "\",\"source_ref\":\"connector://crm/main/r#v\",\"source_view_contract_cid\":\"" +
    source_cid +
    "\",\"version\":\"actql-source-response-policy/0.1\"}"
  let writer = @encode.writer(10000, 7, 1)
  emit_source_response_policy(value, writer)
  assert_eq(@encode.finish(writer), expected)
  let bytes = @utf8.encode(expected)
  let hash = @encode.hashing_writer(bytes.length(), 7, 1)
  emit_source_response_policy(value, hash)
  assert_eq(@encode.finish_hash(hash), @sha.hex(bytes))
  for
    (cap, nodes, depth) in [
      (bytes.length() - 1, 7, 1),
      (bytes.length(), 6, 1),
      (bytes.length(), 7, 0),
    ] {
    let short = @encode.hashing_writer(cap, nodes, depth)
    try emit_source_response_policy(value, short) catch {
      _ => ()
    } noraise {
      _ => fail("response policy escaped output budget")
    }
    try @encode.finish_hash(short) catch {
      _ => ()
    } noraise {
      _ => fail("partial policy hash escaped")
    }
  }
}
