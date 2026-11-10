///|
test "continuation-issued contracts retain complete writer usage and no absent usage is accepted" {
  for issued in [false, true] {
    let preparation = if issued {
      issued_seal_test_start(seal_preparation_test_body(), 4096, 32, 4, 1000).unwrap()
    } else {
      start_publication_seal_preparation(
        "result_delivery_receipt",
        seal_preparation_test_body(),
        4096,
        32,
        4,
        1000,
      ).unwrap()
    }
    let (contract, _) = seal_preparation_test_finish(preparation, 7).unwrap()
    // The original independent receipt vector has thirteen nodes and depth one.
    let bytes = seal_preparation_test_complete().length()
    assert_eq(contract.wire, seal_preparation_test_complete())
    assert_eq(publication_contract_wire_usage(contract), Some((bytes, 13, 1)))
    assert_eq(publication_contract_check_limits(contract, bytes, 13, 1), Ok(()))
    assert_eq(
      publication_contract_check_limits(contract, bytes - 1, 13, 1),
      Err(Encoding),
    )
    assert_eq(
      publication_contract_check_limits(contract, bytes, 12, 1),
      Err(Encoding),
    )
    let unmeasured = { ..contract, wire_usage: None, }
    assert_eq(publication_contract_wire_usage(unmeasured), None)
    assert_eq(
      publication_contract_check_limits(unmeasured, 4096, 32, 4),
      Err(Encoding),
    )
  }
}
