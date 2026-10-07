///|
fn seal_preparation_test_body() -> String {
  "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"8888888888888888888888888888888888888888888888888888888888888888\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"answer\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}"
}

///|
fn seal_preparation_test_complete() -> String {
  // The independently fixed public delivery-receipt vector, not issuer output.
  "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"8888888888888888888888888888888888888888888888888888888888888888\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"answer\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}"
}

///|
fn seal_preparation_test_finish(
  preparation : PublicationSealPreparation,
  quantum : Int,
) -> Result[(PublicationContract, Int), PublicationContractIssue] raise {
  let mut work = 0
  for _ in 0..<10000 {
    match preparation.advance(quantum) {
      Err(issue) => return Err(issue)
      Ok((done, used)) => {
        assert_true(used <= quantum)
        work += used
        if done {
          return preparation.finish().map(value => (value, work))
        }
        assert_true(used > 0)
      }
    }
  }
  fail("seal preparation did not terminate")
}

///|
test "publication seal cursor preserves the independently fixed identity" {
  let mut work = None
  for quantum in [1, 7, 64] {
    let preparation = start_publication_seal_preparation(
      "result_delivery_receipt",
      seal_preparation_test_body(),
      4096,
      32,
      4,
      1000,
    ).unwrap()
    assert_true(preparation.finish() is Err(Encoding))
    let (contract, used) = seal_preparation_test_finish(preparation, quantum).unwrap()
    assert_eq(contract.wire, seal_preparation_test_complete())
    assert_eq(
      contract.identity,
      "sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea",
    )
    if work is Some(previous) {
      assert_eq(used, previous)
    }
    work = Some(used)
    assert_eq(preparation.live, 0)
    assert_true(preparation.value is None && preparation.writer is None)
    assert_true(preparation.finish() is Err(Encoding))
    assert_true(
      admit_publication_contract(
        "result_delivery_receipt",
        contract.wire,
        4096,
        32,
        4,
      )
      is Ok(_),
    )
  }
}

///|
test "publication seal cursor enforces independent writer and control limits" {
  let bytes = seal_preparation_test_complete().length()
  // Complete root + twelve scalars = thirteen nodes. The fixed eight control slots
  // overlap a maximum of two schema continuations plus two growth reserves.
  let exact = start_publication_seal_preparation(
    "result_delivery_receipt",
    seal_preparation_test_body(),
    bytes,
    13,
    1,
    12,
  ).unwrap()
  ignore(seal_preparation_test_finish(exact, 1).unwrap())
  assert_eq(exact.peak, 12)
  for
    (max_bytes, max_nodes, workspace, expected) in [
      (bytes - 1, 13, 12, PublicationContractIssue::Encoding),
      (bytes, 12, 12, InvalidWire),
      (bytes, 13, 11, PublicationContractIssue::Encoding),
    ] {
    let preparation = start_publication_seal_preparation(
      "result_delivery_receipt",
      seal_preparation_test_body(),
      max_bytes,
      max_nodes,
      1,
      workspace,
    ).unwrap()
    assert_true(
      seal_preparation_test_finish(preparation, 1) is Err(issue) &&
      issue == expected,
    )
    assert_eq(preparation.live, 0)
    assert_true(preparation.writer is None && preparation.contract is None)
  }
}

///|
test "publication seal cancellation retires every child without transferring a contract" {
  for wanted in 0..<7 {
    let preparation = start_publication_seal_preparation(
      "result_delivery_receipt",
      seal_preparation_test_body(),
      4096,
      32,
      4,
      1000,
    ).unwrap()
    let mut reached = false
    for _ in 0..<10000 {
      ignore(preparation.advance(1).unwrap())
      let matches = match (wanted, preparation.phase) {
        (0, Parse(_)) => true
        (1, Decode(_)) => true
        (2, Canonical(_)) => true
        (3, Shape(_, false)) => true
        (4, Hash(_)) => true
        (5, Shape(_, true)) => true
        (6, Encode(_)) => true
        _ => false
      }
      if matches {
        reached = true
        break
      }
    }
    assert_true(reached)
    preparation.cancel()
    preparation.cancel()
    assert_eq(preparation.live, 0)
    assert_true(preparation.writer is None && preparation.value is None)
    assert_true(preparation.contract is None && preparation.identity is None)
    assert_true(preparation.advance(1) is Err(Encoding))
    assert_true(preparation.finish() is Err(Encoding))
  }
}

///|
test "publication seal cursor retains structural refusal causes" {
  for
    (body, expected) in [
      ("{}", MissingField("version")),
      ("{\"version\":\"wrong\"}", InvalidField("version")),
      (seal_preparation_test_complete(), IdentityAlreadyPresent),
      (
        seal_preparation_test_body().replace(
          old="actql-result-delivery-receipt/0.1",
          new="actql-result-delivery-receipt/0.1\",\"unknown\":true,\"extra\":\"x",
        ),
        InvalidField("protocol_schema"),
      ),
    ] {
    let preparation = start_publication_seal_preparation(
      "result_delivery_receipt", body, 4096, 32, 4, 1000,
    ).unwrap()
    assert_true(
      seal_preparation_test_finish(preparation, 1) is Err(issue) &&
      issue == expected,
    )
    assert_eq(preparation.live, 0)
  }
}
