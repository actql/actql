///|
priv struct TestRetainedProof {
  material : RetainedOutputMaterial
  successful : Bool
}

///|
fn retained_fixture(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
) -> (CompletedOutput, RetainedOutputHandle[String]) raise {
  let stream = prepare_admitted_output_stream(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    let supplied = output_fixture_row(owner, row)
    append_admitted_output_stream(stream, supplied.length(), column => {
      supplied.get(column)
    }).unwrap()
    |> ignore
  }
  let (receipt, _) = finish_admitted_output_stream(stream).unwrap()
  let handle = retain_admitted_output_stream(receipt, "opaque test storage", fn() {
    live.val
  })
  let material = retained_output_material(handle)
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  // Trusted test implementation; tests below distinguish content admission
  // from this proof-typed execution/retention admission boundary.
  let port = prepare_trusted_retained_output_port(
    preparation,
    Step(1),
    1000,
    10000,
    fn(proof : TestRetainedProof) {
      if proof.successful && physical_equal(proof.material, material) {
        Some(proof.material)
      } else {
        None
      }
    },
  ).unwrap()
  assert_true(
    complete_trusted_retained_output(port, { material, successful: false, })
    is Err(Unverified),
  ) catch {
    _ => abort("unverified output")
  }
  (
    complete_trusted_retained_output(port, { material, successful: true, }).unwrap(),
    handle,
  )
}

///|
test "retained completion and producer admission do not require cell storage" {
  let owner = capture_fixture()
  let live = Ref(true)
  let (output, handle) = retained_fixture(owner, live)
  assert_false(completed_has_cell_access(output))
  assert_true(output.table is None)
  assert_eq(completed_row_count(output), 2)
  assert_eq(completed_column_count(output), 2)
  assert_true(completed_cell(output, 0, 0) is None)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let read = prepare_producer_read(receiver, bound, 1000, 10000).unwrap()
  assert_true(producer_read_available(read))
  assert_false(producer_read_has_cell_access(read))
  assert_eq(
    retained_producer_payload(handle, read),
    Some("opaque test storage"),
  )
  assert_eq(retained_producer_columns(handle, read, 100), Some([0, 1]))
  assert_true(retained_producer_columns(handle, read, 0) is None)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  assert_true(
    execute_fixed_producer_input(generated, read, compute_test_limits())
    is Err(InputRepresentationRequired(0)),
  )
  assert_true(producer_read_matches_operation_input(read, receiver, 0, 0))
  assert_false(producer_read_matches_operation_input(read, receiver, 0, 1))
  assert_false(producer_read_matches_operation_input(read, receiver, 1, 0))
  assert_false(
    producer_read_matches_operation_input(
      read,
      typed_receiver(owner, "[{\"select\":[\"n\"]}]"),
      0,
      0,
    ),
  )
  let (_, other) = retained_fixture(owner, Ref(true))
  assert_true(retained_producer_payload(other, read) is None)
  live.val = false
  assert_false(producer_read_available(read))
  assert_true(retained_producer_payload(handle, read) is None)
  assert_true(
    prepare_producer_read(receiver, bound, 1000, 10000)
    is Err(ProducerUnavailable),
  )
  assert_true(
    bind_completed_input(receiver, 0, owner, output) is Err(ProducerUnavailable),
  )
  // Completion itself has not been rewritten into failed execution.
  assert_true(completion_is_live(output.completion))
  assert_eq(completed_row_count(output), 2)
}

///|
test "retained identity reuses verified bytes while enforcing new hash budgets" {
  let owner = capture_fixture()
  let (output, _) = retained_fixture(owner, Ref(true))
  let identity = identify_completed_rows(output, row_wire_limits()).unwrap()
  let expected = @encode.hashing_writer(1000, 100, 10)
  @encode.emit_json(
    @json.parse("[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]"),
    expected,
  )
  assert_eq(row_wire_cid(identity), "sha256:" + @encode.finish_hash(expected))
  assert_true(row_wire_matches_output(identity, output))
  let (other, _) = retained_fixture(owner, Ref(true))
  assert_false(row_wire_matches_output(identity, other))
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_bytes: 2, })
    is Err(Encoding(_)),
  )
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_nodes: 1, })
    is Err(Encoding(_)),
  )
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_depth: 1, })
    is Err(Encoding(_)),
  )
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_depth: 2, })
    is Ok(_),
  )
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_columns: 1, })
    is Err(OrderLimit),
  )
}

///|
test "retained port rejects wrong owner target and unavailable physical holding" {
  let owner = capture_fixture()
  let live = Ref(true)
  let (_, handle) = retained_fixture(owner, live)
  let material = retained_output_material(handle)
  let foreign = capture_fixture()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(foreign),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let port = prepare_trusted_retained_output_port(
    preparation,
    Step(1),
    1000,
    10000,
    fn(proof : TestRetainedProof) {
      if proof.successful {
        Some(proof.material)
      } else {
        None
      }
    },
  ).unwrap()
  assert_true(
    complete_trusted_retained_output(port, { material, successful: true, })
    is Err(ForeignOutput),
  )
  live.val = false
  assert_true(
    complete_trusted_retained_output(port, { material, successful: true, })
    is Err(Unverified),
  )
  assert_true(
    prepare_trusted_retained_output_port(preparation, Step(0), 1000, 10000, fn(
      _proof : TestRetainedProof,
    ) {
      Some(material)
    })
    is Err(InvalidTarget),
  )
}

///|
test "physical representation quantities do not change canonical receipt or availability" {
  let owner = capture_fixture()
  let (_, original) = retained_fixture(owner, Ref(true))
  let receipt = original.material.receipt
  assert_eq(
    retained_output_storage_bytes(original.material),
    Some(receipt.bytes.to_int64()),
  )
  for bytes in [0L, 1L, 2147483648L] {
    let live = Ref(true)
    let copy = retain_admitted_output_representation(
      receipt,
      "verified alternative representation",
      bytes,
      fn() { live.val },
    ).unwrap()
    let material = retained_output_material(copy)
    assert_true(retained_output_matches_receipt(material, receipt))
    assert_eq(retained_output_storage_bytes(material), Some(bytes))
    assert_true(physical_equal(material.receipt, receipt))
    let (_, foreign) = retained_fixture(owner, Ref(true))
    assert_false(
      retained_output_matches_receipt(material, foreign.material.receipt),
    )
    live.val = false
    assert_true(retained_output_storage_bytes(material) is None)
    assert_false(retained_output_matches_receipt(material, receipt))
  }
  assert_true(
    retain_admitted_output_representation(receipt, (), -1L, () => true)
    is Err(InvalidLimits),
  )
  assert_true(
    retain_admitted_output_representation(receipt, (), 10L, () => false)
    is Err(NotRetained),
  )
}
