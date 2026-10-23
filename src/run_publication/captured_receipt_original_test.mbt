///|
fn receipt_original_capture(
  chain : CapturedRunTestChain,
) -> PublicationContract {
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [],
    chain.authoring,
    chain.models,
    65536,
    4096,
    32,
  ).unwrap()
}

///|
fn receipt_original_check_work(
  chain : CapturedRunTestChain,
  captured : PublicationContract,
  quantum : Int,
) -> Int raise {
  let check = captured_validation_test_start(chain, captured)
  let mut work = 0
  for _ in 0..<100000 {
    let (done, used) = check.advance(quantum).unwrap()
    assert_true(used > 0 && used <= quantum)
    work += used
    if done {
      check.finish().unwrap()
      assert_true(check.finish() is Err(EvidenceEncoding))
      return work
    }
  }
  abort("Finite complete captured evidence validation did not finish")
}

///|
test "Captured Receipt original reduces full validation work with cold controls" {
  let differences : Array[Int] = []
  for with_model in [false, true] {
    let chain = captured_run_test_chain(with_model~)
    let captured = receipt_original_capture(chain)
    let wire = publication_contract_json(captured)
    let restored = admit_publication_contract(
      "captured_run", wire, 65536, 4096, 32,
    ).unwrap()
    assert_eq(publication_contract_json(restored), wire)
    assert_eq(
      publication_contract_identity(restored),
      publication_contract_identity(captured),
    )
    let copied_receipt = admit_publication_contract(
      "run_receipt",
      publication_contract_json(chain.receipt),
      65536,
      4096,
      32,
    ).unwrap()
    let original_work = receipt_original_check_work(chain, captured, 1)
    let restored_work = receipt_original_check_work(chain, restored, 1)
    let copied_work = receipt_original_check_work(
      { ..chain, receipt: copied_receipt, },
      captured,
      1,
    )
    println(
      "receipt model=\{with_model} full_work=\{original_work}/\{restored_work}/\{copied_work}",
    )
    assert_eq(restored_work, copied_work)
    differences.push(restored_work - original_work)
  }
  for difference in differences {
    assert_true(difference > 0)
  }
}
