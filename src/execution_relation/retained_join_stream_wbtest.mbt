///|
test "retained join keys require exact completed content verification" {
  for options in [",\"cardinality\":\"one_to_one\"", ",\"null_key\":\"fail\""] {
    let (owner, profile, memory, retained, live) = retained_join_validation_fixture(
      options,
    )
    let stream = prepare_fixed_join_stream(owner, profile, [retained], {
      max_rows: 2,
      max_work: 10000,
      max_entries: 1000,
    }).unwrap()
    let scan = prepare_retained_producer_scan(
      retained,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    attach_retained_join_scan(scan, stream).unwrap()
    assert_true(attach_retained_join_scan(scan, stream) is Err(InputMismatch))
    for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
      append_retained_producer_scan_wire(scan, row, retained_row_test_limits()).unwrap()
      |> ignore
    }
    assert_false(stream.verified[0])
    // Only the key is retained, not the second string column or whole row.
    assert_eq(stream.rows[0][0].length(), 1)
    assert_eq(stream.rows[1][0].length(), 1)
    finish_retained_producer_scan(scan).unwrap() |> ignore
    let evidence = finish_fixed_join_stream(stream).unwrap()
    assert_true(
      fixed_join_validation_matches(evidence, owner, profile, [retained]),
    )
    assert_false(
      fixed_join_validation_matches(evidence, owner, profile, [memory]),
    )
    assert_true(stream.rows[0].is_empty())
    assert_true(stream.rows[1].is_empty())
    assert_true(finish_fixed_join_stream(stream) is Err(InputMismatch))
    live.val = false
    assert_false(
      fixed_join_validation_matches(evidence, owner, profile, [retained]),
    )
  }
}

///|
test "partial or altered retained join input cannot produce evidence" {
  for
    rows in [
      ["{\"n\":1,\"s\":\"é\"}"],
      ["{\"n\":1,\"s\":\"é\"}", "{\"n\":1,\"s\":\"😀\"}"],
    ] {
    let (owner, profile, _, retained, _) = retained_join_validation_fixture(
      ",\"cardinality\":\"one_to_one\"",
    )
    let stream = prepare_fixed_join_stream(owner, profile, [retained], {
      max_rows: 2,
      max_work: 10000,
      max_entries: 1000,
    }).unwrap()
    let scan = prepare_retained_producer_scan(
      retained,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    attach_retained_join_scan(scan, stream).unwrap()
    for row in rows {
      append_retained_producer_scan_wire(scan, row, retained_row_test_limits()).unwrap()
      |> ignore
    }
    assert_true(finish_retained_producer_scan(scan) is Err(IdentityMismatch))
    assert_true(finish_fixed_join_stream(stream) is Err(InputMismatch))
    assert_true(stream.rows[0].is_empty())
    assert_true(stream.rows[1].is_empty())
  }
}

///|
test "unfinished retained join and cancelled scan consume their provisional state" {
  let (owner, profile, _, retained, _) = retained_join_validation_fixture(
    ",\"null_key\":\"fail\"",
  )
  let limits = { max_rows: 2, max_work: 10000, max_entries: 1000, }
  let stream = prepare_fixed_join_stream(owner, profile, [retained], limits).unwrap()
  assert_true(finish_fixed_join_stream(stream) is Err(InputMismatch))
  let scan = prepare_retained_producer_scan(
    retained,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  assert_true(attach_retained_join_scan(scan, stream) is Err(InputMismatch))
  let replacement = prepare_fixed_join_stream(
    owner,
    profile,
    [retained],
    limits,
  ).unwrap()
  attach_retained_join_scan(scan, replacement).unwrap()
  append_retained_producer_scan_wire(
    scan,
    "{\"n\":1,\"s\":\"é\"}",
    retained_row_test_limits(),
  ).unwrap()
  |> ignore
  assert_true(cancel_retained_producer_scan(scan))
  assert_true(replacement.rows[0].is_empty())
  assert_true(finish_fixed_join_stream(replacement) is Err(InputMismatch))
}

///|
test "join key scratch is cumulative and checks its exact capacity before retention" {
  let (owner, profile, memory, _, _) = retained_join_validation_fixture(
    ",\"cardinality\":\"one_to_one\"",
  )
  let stream = prepare_fixed_join_stream(owner, profile, [memory], {
    max_rows: 2,
    max_work: 10000,
    max_entries: 1000,
  }).unwrap()
  let evidence = finish_fixed_join_stream(stream).unwrap()
  let (work, peak) = fixed_join_validation_usage(evidence)
  let exact = prepare_fixed_join_stream(owner, profile, [memory], {
    max_rows: 2,
    max_work: work,
    max_entries: peak,
  }).unwrap()
  assert_true(finish_fixed_join_stream(exact) is Ok(_))
  let short_work = prepare_fixed_join_stream(owner, profile, [memory], {
    max_rows: 2,
    max_work: work - 1,
    max_entries: peak,
  }).unwrap()
  assert_true(finish_fixed_join_stream(short_work) is Err(RowLimit))
  assert_true(short_work.rows[0].is_empty())
  match
    prepare_fixed_join_stream(owner, profile, [memory], {
      max_rows: 2,
      max_work: work,
      max_entries: peak - 1,
    }) {
    Err(issue) => assert_true(issue is RowLimit)
    Ok(short_space) => {
      assert_true(finish_fixed_join_stream(short_space) is Err(RowLimit))
      assert_true(short_space.rows[1].is_empty())
    }
  }
}

///|
test "verified retained keys preserve left-side NULL and duplicate failure precedence" {
  for nulls in [false, true] {
    let n = if nulls { "null" } else { "1" }
    let rows = [
      "{\"n\":" + n + ",\"s\":\"é\"}",
      "{\"n\":" + n + ",\"s\":\"😀\"}",
    ]
    let source = bound_pipeline(
      "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":true},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[" +
      rows[0] +
      "," +
      rows[1] +
      "]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"]}]",
    )
    let (owner, profile, memory, retained, _) = retained_join_validation_fixture(
      ",\"null_key\":\"fail\",\"cardinality\":\"one_to_one\"",
      source_owner=source,
    )
    let limits = { max_rows: 2, max_work: 10000, max_entries: 1000, }
    let stream = prepare_fixed_join_stream(owner, profile, [retained], limits).unwrap()
    let scan = prepare_retained_producer_scan(
      retained,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    attach_retained_join_scan(scan, stream).unwrap()
    for row in rows {
      append_retained_producer_scan_wire(scan, row, retained_row_test_limits()).unwrap()
      |> ignore
    }
    finish_retained_producer_scan(scan).unwrap() |> ignore
    assert_true(@lower.inner_join_assertion(profile) is Some(OneToOne))
    assert_eq(stream.rows[0].length(), 2)
    if !nulls {
      assert_true(stream.rows[0][0][0] is Number(1.0))
      assert_true(stream.rows[0][1][0] is Number(1.0))
    }
    let result = finish_fixed_join_stream(stream)
    let baseline = validate_fixed_join_inputs(owner, profile, [memory], limits)
    if nulls {
      assert_true(result is Err(JoinNullKey(true, 0, 0)))
      assert_true(baseline is Err(JoinNullKey(true, 0, 0)))
    } else {
      let detail = match result {
        Err(JoinDuplicateKey(left, row, previous)) =>
          "duplicate \{left} \{row} \{previous}"
        Err(RowLimit) => "limit"
        Err(InputMismatch) => "input"
        Err(Comparison(_)) => "comparison"
        Err(_) => "other"
        Ok(_) => "success"
      }
      assert_eq(detail, "duplicate true 1 0")
      assert_true(result is Err(JoinDuplicateKey(true, 1, 0)))
      assert_true(baseline is Err(JoinDuplicateKey(true, 1, 0)))
    }
    assert_true(stream.rows[0].is_empty())
    assert_true(stream.rows[1].is_empty())
  }
}
