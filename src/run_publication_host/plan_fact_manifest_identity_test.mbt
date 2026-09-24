///|
test "saved Plan fact manifest binds its canonical facts and self CID" {
  let cid = "sha256:8f4ee047516b093f0320728892dcaafcf831f3166b0f1c5d0bbca2f0909c6933"
  let first = "{\"contract_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"kind\":\"contract_fact\",\"subject_ref\":\"unit:a\"}"
  let second = "{\"contract_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"kind\":\"contract_fact\",\"subject_ref\":\"unit:b\"}"
  let facts = "[" + first + "," + second + "]"
  let manifest = "{\"plan_facts\":" +
    facts +
    ",\"plan_fact_manifest_cid\":\"" +
    cid +
    "\",\"version\":\"actql-plan-fact-manifest/0.1\"}"
  let encoded = match encode_plan_fact_manifest_identity(facts, 4096, 100, 10) {
    Ok(value) => value
    Err(_) => fail("expected manifest identity")
  }
  assert_eq(plan_fact_manifest_identity_cid(encoded), cid)
  assert_eq(
    check_plan_fact_manifest_identity(
      plan_fact_manifest_identity_wire(encoded),
      facts,
      4096,
      100,
      10,
    ),
    Ok(cid),
  )
  assert_eq(
    check_plan_fact_manifest_identity(manifest, facts, 4096, 100, 10),
    Ok(cid),
  )
  let reordered_fact = "{\"subject_ref\":\"unit:a\",\"kind\":\"contract_fact\",\"contract_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"}"
  assert_eq(
    check_plan_fact_manifest_identity(
      manifest,
      "[" + reordered_fact + "," + second + "]",
      4096,
      100,
      10,
    ),
    Ok(cid),
  )
  assert_eq(
    check_plan_fact_manifest_identity(manifest, "[]", 4096, 100, 10),
    Err(FactMismatch),
  )
  assert_eq(
    check_plan_fact_manifest_identity(
      manifest,
      "[" + second + "," + first + "]",
      4096,
      100,
      10,
    ),
    Err(FactMismatch),
  )
  assert_eq(
    check_plan_fact_manifest_identity(
      manifest.replace(old=cid, new="sha256:" + "0".repeat(64)),
      facts,
      4096,
      100,
      10,
    ),
    Err(CidMismatch),
  )
  assert_eq(
    check_plan_fact_manifest_identity(
      manifest.replace(old="\"version\":", new="\"foreign\":true,\"version\":"),
      facts,
      4096,
      100,
      10,
    ),
    Err(InvalidManifest),
  )
  assert_eq(
    check_plan_fact_manifest_identity(manifest, "{}", 4096, 100, 10),
    Err(InvalidPlanFacts),
  )
  assert_eq(
    check_plan_fact_manifest_identity(manifest, facts, 10, 100, 10),
    Err(InvalidManifest),
  )
  assert_true(
    encode_plan_fact_manifest_identity("{}", 4096, 100, 10)
    is Err(InvalidPlanFacts),
  )
  assert_true(
    encode_plan_fact_manifest_identity(facts, 10, 100, 10)
    is Err(InvalidPlanFacts),
  )
}
