///|
fn issued_seal_test_value(wire : String) -> @json.CanonicalValue {
  let source = @source.parse_json(wire, {
    max_input_bytes: 4096,
    max_nodes: 32,
    max_depth: 4,
  }).unwrap()
  @json.from_source(source, 32, 4, 4096) catch {
    _ => abort("Invalid issued seal fixture")
  }
}

///|
fn issued_seal_test_start(
  wire : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
  workspace : Int,
) -> Result[PublicationSealPreparation, PublicationContractIssue] {
  let value = issued_seal_test_value(wire)
  let usage = try {
    let writer = @encode.measuring_writer(bytes, nodes, depth)
    let cursor = @json.start_emit(value, writer)
    while !@json.advance_emit(cursor) {
      ()
    }
    @encode.finish_measurement_usage(writer)
  } catch {
    _ => return Err(Encoding)
  }
  start_issued_publication_seal_preparation(
    "result_delivery_receipt", value, usage, bytes, nodes, depth, workspace,
  )
}

///|
test "issued publication seal preserves fixed identity without text readmission" {
  let mut work = None
  for quantum in [1, 7, 64] {
    let issued = issued_seal_test_start(
      seal_preparation_test_body(),
      4096,
      32,
      4,
      1000,
    ).unwrap()
    assert_true(issued.phase is Issued)
    let (contract, used) = seal_preparation_test_finish(issued, quantum).unwrap()
    assert_eq(contract.wire, seal_preparation_test_complete())
    let legacy = start_publication_seal_preparation(
      "result_delivery_receipt",
      seal_preparation_test_body(),
      4096,
      32,
      4,
      1000,
    ).unwrap()
    let (original, legacy_work) = seal_preparation_test_finish(legacy, quantum).unwrap()
    assert_eq(contract.identity, original.identity)
    assert_true(used < legacy_work)
    if work is Some(previous) {
      assert_eq(used, previous)
    }
    work = Some(used)
    assert_eq(issued.live, 0)
    assert_true(issued.value is None && issued.writer is None)
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
test "issued publication seal keeps independent complete bounds and schema refusal" {
  let bytes = seal_preparation_test_complete().length()
  let exact = issued_seal_test_start(
    seal_preparation_test_body(),
    bytes,
    13,
    1,
    12,
  ).unwrap()
  ignore(seal_preparation_test_finish(exact, 1).unwrap())
  assert_eq(exact.peak, 12)
  for
    (body, expected) in [
      ("{}", MissingField("version")),
      ("{\"version\":\"wrong\"}", InvalidField("version")),
      (seal_preparation_test_complete(), IdentityAlreadyPresent),
    ] {
    let issued = issued_seal_test_start(body, 4096, 32, 4, 1000).unwrap()
    let legacy = start_publication_seal_preparation(
      "result_delivery_receipt", body, 4096, 32, 4, 1000,
    ).unwrap()
    assert_true(
      seal_preparation_test_finish(issued, 1) is Err(issue) && issue == expected,
    )
    assert_true(
      seal_preparation_test_finish(legacy, 1) is Err(issue) && issue == expected,
    )
  }
  assert_true(
    issued_seal_test_start(seal_preparation_test_body(), bytes, 12, 1, 12)
    is Err(InvalidWire),
  )
  for (max_bytes, workspace) in [(bytes - 1, 12), (bytes, 11)] {
    let issued = issued_seal_test_start(
      seal_preparation_test_body(),
      max_bytes,
      13,
      1,
      workspace,
    ).unwrap()
    assert_true(seal_preparation_test_finish(issued, 1) is Err(Encoding))
    assert_eq(issued.live, 0)
  }
}

///|
test "issued publication seal cancellation retires retained values and writers" {
  for wanted in 0..<5 {
    let issued = issued_seal_test_start(
      seal_preparation_test_body(),
      4096,
      32,
      4,
      1000,
    ).unwrap()
    let mut reached = false
    for _ in 0..<10000 {
      let matches = match (wanted, issued.phase) {
        (0, Issued) => true
        (1, Shape(_, false)) => true
        (2, Hash(_)) => true
        (3, Shape(_, true)) => true
        (4, Encode(_)) => true
        _ => false
      }
      if matches {
        reached = true
        break
      }
      ignore(issued.advance(1).unwrap())
    }
    assert_true(reached)
    issued.cancel()
    issued.cancel()
    assert_eq(issued.live, 0)
    assert_true(
      issued.value is None && issued.writer is None && issued.contract is None,
    )
    assert_true(issued.advance(1) is Err(Encoding))
    assert_true(issued.finish() is Err(Encoding))
  }
}
