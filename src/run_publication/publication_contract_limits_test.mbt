///|
test "retained complete Run limits keep the independent identity and exact geometry" {
  let contract = seal_publication_contract(
    "run_definition",
    scope_projection_body("\"scope\""),
    8192,
    64,
    4,
  ).unwrap()
  // Independently fixed complete canonical vector: ten scalar fields + root.
  assert_eq(
    publication_contract_identity(contract),
    "sha256:4a288ff6406340fbcf51438ee9f493b1cb32c8d804be16cab0774cdbdfe3484f",
  )
  assert_eq(publication_contract_check_limits(contract, 643, 11, 1), Ok(()))
  assert_eq(
    publication_contract_check_limits(contract, 642, 11, 1),
    Err(Encoding),
  )
  assert_eq(
    publication_contract_check_limits(contract, 643, 10, 1),
    Err(Encoding),
  )
  for (bytes, nodes, depth) in [(0, 11, 1), (643, 0, 1), (643, 11, 0)] {
    assert_eq(
      publication_contract_check_limits(contract, bytes, nodes, depth),
      Err(InvalidLimits),
    )
  }
}

///|
test "restored contract limits count canonical UTF8 bytes instead of String units" {
  let contract = seal_publication_contract(
    "run_definition",
    scope_projection_body("\"é😀\""),
    8192,
    64,
    4,
  ).unwrap()
  let wire = publication_contract_json(contract)
  // Replace five ASCII scope bytes by six UTF-8 bytes (three UTF-16 units).
  let restored = admit_publication_contract("run_definition", wire, 8192, 64, 4).unwrap()
  for value in [contract, restored] {
    assert_eq(publication_contract_check_limits(value, 644, 11, 1), Ok(()))
    assert_eq(
      publication_contract_check_limits(value, 643, 11, 1),
      Err(Encoding),
    )
    assert_eq(publication_contract_json(value), wire)
  }
}

///|
test "a retained larger admission cannot borrow a smaller child wire bound" {
  let body = scope_projection_body("\"scope\"").replace(
    old="\"run_id\":\"run\"",
    new="\"run_id\":\"" + "x".repeat(71680) + "\"",
  )
  let large = seal_publication_contract(
    "run_definition", body, 131072, 4096, 64,
  ).unwrap()
  assert_eq(
    publication_contract_check_limits(large, 65536, 4096, 64),
    Err(Encoding),
  )
  assert_eq(publication_contract_check_limits(large, 131072, 4096, 64), Ok(()))
}

///|
test "retained container depth matches the existing external reader" {
  let template = ordering_test_cid("1")
  let manifest = issue_result_manifest(
    manifest_test_run(template),
    manifest_test_invocation(template),
    [],
    [],
    8192,
    64,
    5,
  ).unwrap()
  let wire = publication_contract_json(manifest)
  // The accepted independent empty-Manifest vector has a root and results object.
  assert_eq(
    publication_contract_identity(manifest),
    "sha256:316b1059d931be7a41fd71f622fdd314d402f41051a195dcfe4f43b306941523",
  )
  assert_eq(publication_contract_check_limits(manifest, 8192, 6, 2), Ok(()))
  assert_eq(
    publication_contract_check_limits(manifest, 8192, 6, 1),
    Err(Encoding),
  )
  assert_true(
    admit_publication_contract("result_manifest", wire, 8192, 6, 1)
    is Err(InvalidWire),
  )
  let restored = admit_publication_contract("result_manifest", wire, 8192, 6, 2).unwrap()
  assert_eq(publication_contract_check_limits(restored, 8192, 6, 2), Ok(()))
  assert_eq(
    publication_contract_check_limits(restored, 8192, 6, 1),
    Err(Encoding),
  )
}
