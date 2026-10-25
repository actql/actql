///|
/// Actual issuers preserve a valid full chain while the attempt's wire extent
/// exceeds the captured Run. No forged usage or placeholder contract.
fn asymmetric_commit_originals() -> Array[PublicationContract] {
  let originals=commit_read_fixture().originals.copy()
  let attempt=issue_publication_attempt(
    originals[5], originals[0], "a".repeat(20000), ordering_test_cid("6"),
    None, "2026-09-18T00:00:01.000Z", 65536,4096,32,
  ).unwrap()
  let index=issue_public_index_entry(
    originals[0],originals[1],originals[2],originals[3],originals[4],
    [originals[13]],originals[5],attempt,"2026-09-18T00:00:02.000Z",
    65536,4096,32,
  ).unwrap()
  originals[6]=attempt
  originals[7]=index
  originals
}

///|
test "real attempt wire independently exceeds captured Run envelope" {
  let originals=asymmetric_commit_originals()
  // All fixture text is ASCII; String length is exact UTF8 byte length here.
  let bytes=publication_contract_json(originals[6]).length()
  assert_true(bytes>publication_contract_json(originals[4]).length())
  assert_true(publication_contract_check_limits(originals[6],bytes,4096,32) is Ok(_))
  assert_true(publication_contract_check_limits(originals[6],bytes-1,4096,32) is Err(_))
}

///|
test "owned commit validation derives all original dimensions and survives caller inventory mutation" {
  let o=asymmetric_commit_originals()
  let definitions=[o[8]]; let artifacts=[o[9]]; let derivations=[o[10]]
  let orderings=[o[11]]; let retentions=[o[12]]; let bindings=[o[13]]
  let plan=prepare_original_effect_free_commit_validation(o[0],o[1],definitions,artifacts,
    derivations,orderings,retentions,bindings,o[2],o[3],o[4],o[5],o[6],o[7]).unwrap()
  let cancelled=prepare_original_effect_free_commit_validation(o[0],o[1],definitions,artifacts,
    derivations,orderings,retentions,bindings,o[2],o[3],o[4],o[5],o[6],o[7]).unwrap()
  cancel_publication_validation_plan(cancelled)
  cancel_publication_validation_plan(cancelled)
  assert_true(publication_validation_plan_limits(cancelled) is None)
  assert_true(start_planned_commit_validation(cancelled) is None)
  let limits=publication_validation_plan_limits(plan).unwrap()
  assert_true(limits.0 >= publication_contract_json(o[6]).length())
  for contract in o {
    assert_true(publication_contract_check_limits(contract,limits.0,limits.1,limits.2) is Ok(_))
  }
  definitions.clear(); artifacts.clear(); derivations.clear()
  orderings.clear(); retentions.clear(); bindings.clear()
  assert_true(start_planned_chain_validation(plan) is None)
  let check=start_planned_commit_validation(plan).unwrap()
  assert_true(start_planned_commit_validation(plan) is None)
  assert_true(publication_validation_plan_limits(plan) is None)
  let mut done=false
  for _ in 0..<100000 {
    if check.advance(256).unwrap().0 {done=true;break}
  }
  assert_true(done)
  check.finish().unwrap()
}
