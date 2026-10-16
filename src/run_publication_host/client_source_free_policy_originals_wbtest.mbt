///|
// Independently authored normative policy and Python hashlib/JSON packet.
// Neither expected bytes nor digest are obtained from the product encoder.
let source_free_policy_originals_wire : String =
  #|{"bodies":[{"body":"{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}","cid":"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563","kind":"data_policy"}],"root_policy_cid":"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"}

///|
fn source_free_policy_originals_fixture() -> @publication.CapturedEffectDependencyBody {
  admit_source_free_result_policy_body(
    local_values_original_policy_cid, local_values_original_policy_wire, 8192, 512,
    8,
  ).unwrap()
}

///|
test "source-free policy metadata uses the existing exact packet and independent digest" {
  let original = source_free_policy_originals_fixture()
  let wire = encode_client_source_free_policy_originals(original).unwrap()
  assert_eq(wire, source_free_policy_originals_wire)
  assert_eq(
    @sha.hex(@utf8.encode(wire)),
    "d27232aad076f927c3d5e852c2b98e3b02940d867d79b33c3d39965ee83db960",
  )
  let decoded = read_client_run_policy_originals(wire).unwrap()
  assert_eq(decoded.length(), 1)
  assert_eq(
    @publication.captured_effect_dependency_body_json(decoded[0]),
    local_values_original_policy_wire,
  )
  assert_eq(
    @publication.captured_effect_dependency_body_cid(decoded[0]),
    local_values_original_policy_cid,
  )
}

///|
test "source-free policy metadata refuses contributing source closure and other roles" {
  let closure = prepared_client_publication_policy_bodies(
    multi_source_prepared(multi_source_program),
    65536,
    8192,
    64,
  ).unwrap()
  assert_eq(closure.length(), 7)
  let mut other_role = false
  for (kind, cid, wire) in closure {
    let body = @publication.admit_captured_effect_dependency_body(
      kind,
      Some(cid),
      wire,
      65536,
      8192,
      64,
    ).unwrap()
    if kind != "data_policy" {
      other_role = true
    }
    assert_true(
      encode_client_source_free_policy_originals(body)
      is Err(PublicationPolicy(@checked.ForeignBody)),
    )
  }
  assert_true(other_role)
}

///|
test "source-free packet stays identical to both existing Values compilation alternatives" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let compiled = with_client_source_free_result_policy(
      compiled, local_values_original_policy_cid, local_values_original_policy_wire,
      65536, 8192, 64,
    ).unwrap()
    assert_eq(
      issue_client_run_policy_originals(prepared, compiled~).unwrap(),
      source_free_policy_originals_wire,
    )
  }
}

///|
test "existing packet reader rejects missing dependencies wrong CID and duplicate root" {
  let original = source_free_policy_originals_wire
  assert_true(
    read_client_run_policy_originals(
      original.replace(
        old="\"root_policy_cid\":\"sha256:470e",
        new="\"root_policy_cid\":\"sha256:570e",
      ),
    )
    is Err(CustodyLost),
  )
  assert_true(
    read_client_run_policy_originals(
      original.replace(
        old="\"bodies\":[",
        new="\"root_policy_cid\":\"" +
          local_values_original_policy_cid +
          "\",\"bodies\":[",
      ),
    )
    is Err(CustodyLost),
  )
  let bodies = prepared_client_publication_policy_bodies(
    multi_source_prepared(multi_source_program),
    65536,
    8192,
    64,
  ).unwrap()
  let incomplete = encode_client_run_policy_originals([bodies[0]]).unwrap()
  assert_true(read_client_run_policy_originals(incomplete) is Err(CustodyLost))
}
