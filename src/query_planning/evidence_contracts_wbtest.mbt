///|
fn query_evidence_test_limits() -> QueryEvidenceLimits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 100, }
}

///|
test "verifier pins full acquisition and process evidence bodies, not digest claims" {
  let (query, evidence) = query_evidence_test_bodies()
  let contracts = admit_query_evidence_contracts(
    query,
    evidence,
    query_evidence_test_limits(),
  ).unwrap()
  let (bytes, nodes) = query_evidence_contract_usage(contracts)
  // Independent sorted-key JSON UTF-8 measurement and recursive node count of
  // the shared bodies, not values obtained from the product verifier.
  assert_eq((bytes, nodes), (10369, 433))
  // Exact aggregate bounds, not a fresh allowance for each dependency body.
  assert_true(
    admit_query_evidence_contracts(query, evidence, {
      max_bytes: bytes,
      max_nodes: nodes,
      max_depth: 100,
    })
    is Ok(_),
  )
  assert_true(
    admit_query_evidence_contracts(query, evidence, {
      max_bytes: bytes - 1,
      max_nodes: nodes,
      max_depth: 100,
    })
    is Err(EvidenceBodyLimit),
  )
  assert_true(
    admit_query_evidence_contracts(query, evidence, {
      max_bytes: bytes,
      max_nodes: nodes - 1,
      max_depth: 100,
    })
    is Err(EvidenceBodyLimit),
  )
  assert_true(
    admit_query_evidence_contracts(query, evidence, {
      ..query_evidence_test_limits(),
      max_depth: 0,
    })
    is Err(AcquisitionBodyLimit),
  )
  assert_true(
    admit_query_evidence_contracts(query, evidence, {
      ..query_evidence_test_limits(),
      max_bytes: -1,
    })
    is Err(InvalidLimits),
  )
  let claim = @identity.from_json(
    @json.parse(
      "{\"version\":\"actql-query-process-evidence-contract/0.1\",\"cid\":\"sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89\"}",
    ),
    100,
    10,
    1000,
  )
  assert_true(
    admit_query_evidence_contracts(query, claim, query_evidence_test_limits())
    is Err(UnsupportedEvidence),
  )
  assert_true(
    admit_query_evidence_contracts(
      evidence,
      query,
      query_evidence_test_limits(),
    )
    is Err(UnsupportedAcquisition),
  )
}

///|
test "verifier rejects altered acquisition dependency and schema-only evidence" {
  let (query, evidence) = query_evidence_test_bodies()
  let original = @identity.stringify_value(evidence, 100000, 10000, 100)
  let changed = original.replace_all(
    old="sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1",
    new="sha256:0000000000000000000000000000000000000000000000000000000000000000",
  )
  let changed = @identity.from_json(@json.parse(changed), 10000, 100, 100000)
  assert_true(
    admit_query_evidence_contracts(query, changed, query_evidence_test_limits())
    is Err(UnsupportedEvidence),
  )
  guard evidence is @identity.Object(fields) else { fail("fixture object") }
  let mut schema : @identity.CanonicalValue = evidence
  for (name, value) in @identity.array_values(fields) {
    if name == "schemas" {
      guard value is @identity.Object(schemas) else { fail("fixture schemas") }
      schema = @identity.array_values(schemas)[0].1
    }
  }
  assert_eq(
    @identity.cid_value(schema, 100000, 10000, 100),
    "sha256:758c9c4f1942890e73462776f3230400e7076c146af8eb3f7e39602715c7427e",
  )
  assert_true(
    admit_query_evidence_contracts(query, schema, query_evidence_test_limits())
    is Err(UnsupportedEvidence),
  )
}
