///|
fn content_read_preparation(
  owner : @lower.BoundPrepared,
) -> CompletionPreparation raise {
  prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
}

///|
fn content_read_descriptor() -> RetainedCompletionDescriptor raise {
  retained_completion_descriptor(
    retain_completion_evidence(
      evidence_fixture(capture_fixture(), Ref(true)),
      10,
      10,
    ).unwrap(),
  )
}

///|
fn content_read_limits() -> RetainedRowDecodeLimits {
  { max_bytes: 128, max_nodes: 20, max_depth: 10, max_text_bytes: 128, }
}

///|
test "retained content read revalidates exact canonical content without retaining rows or completion authority" {
  let owner = capture_fixture()
  let descriptor = content_read_descriptor()
  let read = prepare_retained_content_read(
    content_read_preparation(owner),
    descriptor,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_retained_content_read(read, row, content_read_limits()).unwrap()
    assert_true(read.stream.buffer.rows.is_empty())
  }
  let receipt = finish_retained_content_read(read).unwrap()
  assert_true(physical_equal(output_stream_owner(receipt), owner))
  assert_eq(
    receipt.cid,
    "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
  )
  assert_eq(receipt.usage, { nodes: 6, text_bytes: 10, work: 16, })
  assert_true(finish_retained_content_read(read) is Err(Closed))
  assert_true(
    append_retained_content_read(read, "{}", content_read_limits())
    is Err(Closed),
  )
  // No CompletedOutput, physical holding, or ProducerRead is created here.
}

///|
test "retained content read rejects contract and metadata mismatches before reading" {
  let preparation = content_read_preparation(capture_fixture())
  let expected = content_read_descriptor()
  for
    altered in [
      { ..expected, registry_cid: "foreign", },
      { ..expected, values_contract_cid: "foreign", },
      { ..expected, output_step: 999, },
      { ..expected, input_count: expected.input_count + 1, },
      { ..expected, columns: expected.columns + 1, },
    ] {
    assert_true(
      prepare_retained_content_read(
        preparation,
        altered,
        2,
        stream_value_limits(),
        row_wire_limits(),
        64,
      )
      is Err(ForeignContract),
    )
  }
  for
    altered in [
      { ..expected, rows: 3, },
      { ..expected, bytes: -1, },
      { ..expected, nodes: -1, },
      { ..expected, depth: -1, },
      { ..expected, values: { ..expected.values, work: -1, }, },
    ] {
    assert_true(
      prepare_retained_content_read(
        preparation,
        altered,
        2,
        stream_value_limits(),
        row_wire_limits(),
        64,
      )
      is Err(MetadataLimit),
    )
  }
}

///|
test "retained content read rejects changed order omitted rows and forged metrics" {
  let preparation = content_read_preparation(capture_fixture())
  let expected = content_read_descriptor()
  for case_ in 0..<4 {
    let descriptor = if case_ == 2 {
      {
        ..expected,
        values: { ..expected.values, work: expected.values.work + 1, },
      }
    } else if case_ == 3 {
      { ..expected, depth: expected.depth + 1, }
    } else {
      expected
    }
    let read = prepare_retained_content_read(
      preparation,
      descriptor,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    let rows = if case_ == 0 {
      ["{\"n\":2,\"s\":\"😀\"}", "{\"n\":1,\"s\":\"é\"}"]
    } else if case_ == 1 {
      ["{\"n\":1,\"s\":\"é\"}"]
    } else {
      ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"]
    }
    for row in rows {
      append_retained_content_read(read, row, content_read_limits()).unwrap()
    }
    assert_true(finish_retained_content_read(read) is Err(IdentityMismatch))
    assert_true(finish_retained_content_read(read) is Err(Closed))
  }
}

///|
test "retained content read fails closed on malformed bounded rows and cumulative overflow" {
  let preparation = content_read_preparation(capture_fixture())
  let expected = content_read_descriptor()
  for
    row in [
      "{}", "{\"n\":null,\"s\":\"é\"}", "{\"n\":1,\"s\":\"é\",\"extra\":0}",
    ] {
    let read = prepare_retained_content_read(
      preparation,
      expected,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    assert_true(
      append_retained_content_read(read, row, content_read_limits())
      is Err(Row(_)),
    )
    assert_true(finish_retained_content_read(read) is Err(Closed))
  }
  let read = prepare_retained_content_read(
    preparation,
    expected,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for _ in 0..<2 {
    append_retained_content_read(
      read,
      "{\"n\":1,\"s\":\"é\"}",
      content_read_limits(),
    ).unwrap()
  }
  assert_true(
    append_retained_content_read(
      read,
      "{\"n\":1,\"s\":\"é\"}",
      content_read_limits(),
    )
    is Err(Encoding(Admission(CaptureLimit))),
  )
  assert_true(finish_retained_content_read(read) is Err(Closed))
  let cancelled = prepare_retained_content_read(
    preparation,
    expected,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  assert_true(cancel_retained_content_read(cancelled))
  assert_false(cancel_retained_content_read(cancelled))
  assert_true(finish_retained_content_read(cancelled) is Err(Closed))
}
