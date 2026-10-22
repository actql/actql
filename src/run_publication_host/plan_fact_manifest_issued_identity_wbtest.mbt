///|
// Complete preceding constructor retained for bytes, errors and bounds.
fn preceding_plan_fact_manifest_identity(
  plan_facts_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PlanFactManifestIdentity, PlanFactManifestIdentityIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidBudget)
  }
  guard parse_plan_identity_value(
      plan_facts_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(plan_facts) else {
    return Err(InvalidPlanFacts)
  }
  guard plan_facts is @canonical.Array(_) else { return Err(InvalidPlanFacts) }
  let facts = @canonical.stringify_value(
    plan_facts, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidPlanFacts)
  }
  let preimage = "{\"plan_facts\":" +
    facts +
    ",\"version\":\"actql-plan-fact-manifest/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
  let wire = "{\"plan_fact_manifest_cid\":\"" +
    cid +
    "\",\"plan_facts\":" +
    facts +
    ",\"version\":\"actql-plan-fact-manifest/0.1\"}"
  match
    check_plan_fact_manifest_identity(
      wire, facts, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => Ok({ wire, cid, })
    Err(issue) => Err(issue)
  }
}

///|
fn manifest_identity_projection(
  value : Result[PlanFactManifestIdentity, PlanFactManifestIdentityIssue],
) -> Result[(String, String), PlanFactManifestIdentityIssue] {
  value.map(value => (value.wire, value.cid))
}

///|
test "issued Plan fact manifest retains independent identity 0 and external checks" {
  let facts =
    #|[]
  let expected =
    #|{"plan_fact_manifest_cid":"sha256:862893ef129ae9323466c2eae472e6085ef83419a14654a78d47deba84755e46","plan_facts":[],"version":"actql-plan-fact-manifest/0.1"}
  let actual = encode_plan_fact_manifest_identity(facts, 4096, 100, 10)
  assert_eq(
    manifest_identity_projection(actual),
    manifest_identity_projection(
      preceding_plan_fact_manifest_identity(facts, 4096, 100, 10),
    ),
  )
  let actual = actual.unwrap()
  assert_eq(actual.wire, expected)
  assert_eq(
    actual.cid,
    "sha256:862893ef129ae9323466c2eae472e6085ef83419a14654a78d47deba84755e46",
  )
  assert_eq(
    check_plan_fact_manifest_identity(actual.wire, facts, 4096, 100, 10),
    Ok(actual.cid),
  )
  assert_eq(
    check_plan_fact_manifest_identity(
      actual.wire.replace(old=actual.cid, new="sha256:" + "0".repeat(64)),
      facts,
      4096,
      100,
      10,
    ),
    Err(CidMismatch),
  )
  let bytes = 157
  let nodes = 4
  let depth = 2
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes, depth) is Ok(_),
  )
  for
    (b, n, d) in [
      (bytes, nodes, depth),
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_eq(
      manifest_identity_projection(
        encode_plan_fact_manifest_identity(facts, b, n, d),
      ),
      manifest_identity_projection(
        preceding_plan_fact_manifest_identity(facts, b, n, d),
      ),
    )
  }
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes - 1, nodes, depth)
    is Err(InvalidManifest),
  )
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes - 1, depth)
    is Err(InvalidManifest),
  )
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes, depth - 1)
    is Err(InvalidManifest),
  )
}

///|
test "issued Plan fact manifest retains independent identity 1 and external checks" {
  let facts =
    #|[{"kind":"contract_fact","contract_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","subject_ref":"unit:a"},{"subject_ref":"unit:b","kind":"contract_fact","contract_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}]
  let expected =
    #|{"plan_fact_manifest_cid":"sha256:8f4ee047516b093f0320728892dcaafcf831f3166b0f1c5d0bbca2f0909c6933","plan_facts":[{"contract_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","kind":"contract_fact","subject_ref":"unit:a"},{"contract_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","kind":"contract_fact","subject_ref":"unit:b"}],"version":"actql-plan-fact-manifest/0.1"}
  let actual = encode_plan_fact_manifest_identity(facts, 4096, 100, 10)
  assert_eq(
    manifest_identity_projection(actual),
    manifest_identity_projection(
      preceding_plan_fact_manifest_identity(facts, 4096, 100, 10),
    ),
  )
  let actual = actual.unwrap()
  assert_eq(actual.wire, expected)
  assert_eq(
    actual.cid,
    "sha256:8f4ee047516b093f0320728892dcaafcf831f3166b0f1c5d0bbca2f0909c6933",
  )
  assert_eq(
    check_plan_fact_manifest_identity(actual.wire, facts, 4096, 100, 10),
    Ok(actual.cid),
  )
  assert_eq(
    check_plan_fact_manifest_identity(
      actual.wire.replace(old=actual.cid, new="sha256:" + "0".repeat(64)),
      facts,
      4096,
      100,
      10,
    ),
    Err(CidMismatch),
  )
  let bytes = 430
  let nodes = 12
  let depth = 3
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes, depth) is Ok(_),
  )
  for
    (b, n, d) in [
      (bytes, nodes, depth),
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_eq(
      manifest_identity_projection(
        encode_plan_fact_manifest_identity(facts, b, n, d),
      ),
      manifest_identity_projection(
        preceding_plan_fact_manifest_identity(facts, b, n, d),
      ),
    )
  }
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes - 1, nodes, depth)
    is Err(InvalidManifest),
  )
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes - 1, depth)
    is Err(InvalidManifest),
  )
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes, depth - 1)
    is Err(InvalidManifest),
  )
}

///|
test "issued Plan fact manifest retains independent identity 2 and external checks" {
  let facts =
    #|[1e3,{"é":"𝄞\r\n","a":null}]
  let expected =
    #|{"plan_fact_manifest_cid":"sha256:63e83e7ce9c8bc423d0408fe2434bd6b28ee998de20b9aeab5bd3c5d5f14fc88","plan_facts":[1000,{"a":null,"é":"𝄞\r\n"}],"version":"actql-plan-fact-manifest/0.1"}
  let actual = encode_plan_fact_manifest_identity(facts, 4096, 100, 10)
  assert_eq(
    manifest_identity_projection(actual),
    manifest_identity_projection(
      preceding_plan_fact_manifest_identity(facts, 4096, 100, 10),
    ),
  )
  let actual = actual.unwrap()
  assert_eq(actual.wire, expected)
  assert_eq(
    actual.cid,
    "sha256:63e83e7ce9c8bc423d0408fe2434bd6b28ee998de20b9aeab5bd3c5d5f14fc88",
  )
  assert_eq(
    check_plan_fact_manifest_identity(actual.wire, facts, 4096, 100, 10),
    Ok(actual.cid),
  )
  assert_eq(
    check_plan_fact_manifest_identity(
      actual.wire.replace(old=actual.cid, new="sha256:" + "0".repeat(64)),
      facts,
      4096,
      100,
      10,
    ),
    Err(CidMismatch),
  )
  let bytes = 188
  let nodes = 8
  let depth = 3
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes, depth) is Ok(_),
  )
  for
    (b, n, d) in [
      (bytes, nodes, depth),
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_eq(
      manifest_identity_projection(
        encode_plan_fact_manifest_identity(facts, b, n, d),
      ),
      manifest_identity_projection(
        preceding_plan_fact_manifest_identity(facts, b, n, d),
      ),
    )
  }
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes - 1, nodes, depth)
    is Err(InvalidManifest),
  )
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes - 1, depth)
    is Err(InvalidManifest),
  )
  assert_true(
    encode_plan_fact_manifest_identity(facts, bytes, nodes, depth - 1)
    is Err(InvalidManifest),
  )
}

///|
test "issued Plan fact manifest preserves original input and limit error precedence" {
  for facts in ["{}", "null", "[", "[0,]", "[{\"a\":1,\"a\":2}]"] {
    assert_eq(
      manifest_identity_projection(
        encode_plan_fact_manifest_identity(facts, 4096, 100, 10),
      ),
      Err(InvalidPlanFacts),
    )
    assert_eq(
      manifest_identity_projection(
        encode_plan_fact_manifest_identity(facts, 4096, 100, 10),
      ),
      manifest_identity_projection(
        preceding_plan_fact_manifest_identity(facts, 4096, 100, 10),
      ),
    )
  }
  for (b, n, d) in [(0, 100, 10), (4096, 0, 10), (4096, 100, 0), (-1, 100, 10)] {
    assert_eq(
      manifest_identity_projection(
        encode_plan_fact_manifest_identity("[", b, n, d),
      ),
      Err(InvalidBudget),
    )
    assert_eq(
      manifest_identity_projection(
        encode_plan_fact_manifest_identity("[", b, n, d),
      ),
      manifest_identity_projection(
        preceding_plan_fact_manifest_identity("[", b, n, d),
      ),
    )
  }
  // The input fits five bytes; its canonical numeric spelling needs six.
  // This remains an input-fact error before complete-envelope measurement.
  assert_eq(
    manifest_identity_projection(
      encode_plan_fact_manifest_identity("[1e3]", 5, 100, 10),
    ),
    Err(InvalidPlanFacts),
  )
  assert_eq(
    manifest_identity_projection(
      encode_plan_fact_manifest_identity("[1e3]", 5, 100, 10),
    ),
    manifest_identity_projection(
      preceding_plan_fact_manifest_identity("[1e3]", 5, 100, 10),
    ),
  )
}

///|
test "same-owner Plan facts retain their encoded array without a detached input alias" {
  let facts =
    #|[{"a":1},{"text":"é"}]
  let value = parse_plan_identity_value(facts, 4096, 100, 10).unwrap()
  let values = match value {
    @canonical.Array(values) => @canonical.array_values(values)
    _ => abort("expected fact array")
  }
  let encoded = prepare_plan_fact_manifest_facts(values, 4096, 100, 10)
  values.clear()
  assert_eq(
    manifest_identity_projection(
      finish_plan_fact_manifest_identity(encoded, 4096, 100, 10),
    ),
    manifest_identity_projection(
      preceding_plan_fact_manifest_identity(facts, 4096, 100, 10),
    ),
  )
  // The same retained facts must still obey this caller's tighter full limits.
  assert_true(
    finish_plan_fact_manifest_identity(encoded, 10, 100, 10)
    is Err(InvalidManifest),
  )
  assert_true(
    finish_plan_fact_manifest_identity(encoded, 4096, 1, 10)
    is Err(InvalidManifest),
  )
  assert_true(
    finish_plan_fact_manifest_identity(encoded, 4096, 100, 1)
    is Err(InvalidManifest),
  )
}
