///|
test "provider target identity aliases 15 and 18 character RecordIds" {
  let update = write_request_body(WriteUpdateById).projection
  let short = prepare_write_target_identity(
    update,
    RecordId("001000000000001"),
    128,
    4096,
  ).unwrap()
  let long = prepare_write_target_identity(
    update,
    RecordId("001000000000001AAA"),
    128,
    4096,
  ).unwrap()
  assert_eq(
    write_target_boundary_cid(short),
    "sha256:9e37c0e9bdcb6567340a1808788f6cbd7ae02e22620d7bbe9130e8449bb3afe6",
  )
  assert_eq(
    write_target_scheme_cid(short),
    "sha256:0b931f3ba6061d9129c1b4fd3a81cb3e10db282b196840e4b9119908de7ac813",
  )
  assert_eq(
    write_target_object_cid(short),
    "sha256:228a771786b54de0ec76234e0affcc084c49ad6a990dc4ff78ae1223af91c61a",
  )
  assert_eq(write_target_boundary_cid(short), write_target_boundary_cid(long))
  assert_eq(write_target_scheme_cid(short), write_target_scheme_cid(long))
  assert_eq(write_target_object_cid(short), write_target_object_cid(long))
  assert_true(
    prepare_write_target_identity(
      update,
      RecordId("001000000000001AAB"),
      128,
      4096,
    )
    is Err(InvalidTarget),
  )
  let case_distinct = prepare_write_target_identity(
    update,
    RecordId("00100000000000A"),
    128,
    4096,
  ).unwrap()
  assert_true(
    write_target_object_cid(short) != write_target_object_cid(case_distinct),
  )
  let other_org = {
    ..update,
    binding: { ..update.binding, org_id: "00D000000000002EAA", },
  }
  let foreign = prepare_write_target_identity(
    other_org,
    RecordId("001000000000001"),
    128,
    4096,
  ).unwrap()
  assert_true(
    write_target_boundary_cid(short) != write_target_boundary_cid(foreign),
  )
  let other_resource = { ..update, resource: "Other_Record__c", }
  let foreign_resource = prepare_write_target_identity(
    other_resource,
    RecordId("001000000000001"),
    128,
    4096,
  ).unwrap()
  assert_eq(
    write_target_boundary_cid(short),
    write_target_boundary_cid(foreign_resource),
  )
  assert_true(
    write_target_object_cid(short) != write_target_object_cid(foreign_resource),
  )
}

///|
test "external target identity follows only confirmed metadata matching" {
  let sensitive = collection_case_write_body(",\"caseSensitive\":true").projection
  let insensitive = collection_case_write_body(",\"caseSensitive\":false").projection
  let unknown = collection_case_write_body("").projection
  let upper = prepare_write_target_identity(
    sensitive,
    ExternalText("ABC123"),
    128,
    4096,
  ).unwrap()
  let lower = prepare_write_target_identity(
    sensitive,
    ExternalText("abc123"),
    128,
    4096,
  ).unwrap()
  assert_true(write_target_object_cid(upper) != write_target_object_cid(lower))
  let folded_upper = prepare_write_target_identity(
    insensitive,
    ExternalText("ABC123"),
    128,
    4096,
  ).unwrap()
  let folded_lower = prepare_write_target_identity(
    insensitive,
    ExternalText("abc123"),
    128,
    4096,
  ).unwrap()
  assert_eq(
    write_target_object_cid(folded_upper),
    write_target_object_cid(folded_lower),
  )
  assert_true(
    write_target_scheme_cid(upper) != write_target_scheme_cid(folded_upper),
  )
  assert_true(
    prepare_write_target_identity(unknown, ExternalText("ABC123"), 128, 4096)
    is Err(InvalidTarget),
  )
  assert_true(
    prepare_write_target_identity(insensitive, ExternalText("É"), 128, 4096)
    is Err(InvalidTarget),
  )
}

///|
test "Preview row target must match the exact physical target" {
  let body = write_request_body(WriteUpdateById)
  let single = prepare_single_write_request(
    body,
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
  assert_eq(
    single_write_request_matches_preview_row_target(
      single, "\"001000000000001AAA\"", 4096,
    ),
    Ok(true),
  )
  assert_eq(
    single_write_request_matches_preview_row_target(
      single, "\"001000000000002\"", 4096,
    ),
    Ok(false),
  )
  assert_true(
    single_write_request_matches_preview_row_target(
      single, "\"001000000000001AAB\"", 4096,
    )
    is Err(InvalidTarget),
  )
  let collection = prepare_continue_write_collection(
    [
      {
        row_preview_cid: collection_request_test_cid("1"),
        body,
        target: RecordId("001000000000001"),
      },
      {
        row_preview_cid: collection_request_test_cid("2"),
        body,
        target: RecordId("001000000000002"),
      },
    ],
    "v66.0",
    collection_request_test_limits(),
  ).unwrap()
  assert_eq(
    write_collection_request_matches_preview_row_target(
      collection, 0, "\"001000000000001AAA\"", 4096,
    ),
    Ok(true),
  )
  assert_eq(
    write_collection_request_matches_preview_row_target(
      collection, 1, "\"001000000000001\"", 4096,
    ),
    Ok(false),
  )
  assert_true(
    write_collection_request_matches_preview_row_target(
      collection, 2, "\"001000000000001\"", 4096,
    )
    is Err(InvalidRows),
  )
  let sensitive = collection_case_write_body(",\"caseSensitive\":true").projection
  let insensitive = collection_case_write_body(",\"caseSensitive\":false").projection
  assert_eq(
    write_target_matches_preview_correlation(
      sensitive,
      ExternalText("abc123"),
      "\"ABC123\"",
      100,
      4096,
    ),
    Ok(false),
  )
  assert_eq(
    write_target_matches_preview_correlation(
      insensitive,
      ExternalText("abc123"),
      "\"ABC123\"",
      100,
      4096,
    ),
    Ok(true),
  )
}

///|
test "physical requests retain their own target footprint evidence" {
  let body = write_request_body(WriteUpdateById)
  let short = prepare_single_write_request(
    body,
    "v66.0",
    RecordId("001000000000001"),
    write_request_test_limits(),
  ).unwrap()
  let long = prepare_single_write_request(
    body,
    "v66.0",
    RecordId("001000000000001AAA"),
    write_request_test_limits(),
  ).unwrap()
  let short_identity = single_write_request_target_identity(short, 4096)
    .unwrap()
    .unwrap()
  let long_identity = single_write_request_target_identity(long, 4096)
    .unwrap()
    .unwrap()
  assert_eq(
    write_target_object_cid(short_identity),
    write_target_object_cid(long_identity),
  )
  assert_true(
    single_write_request_target_identity(
      prepare_single_write_request(
        write_request_body(WriteCreate),
        "v66.0",
        NoWriteTarget,
        write_request_test_limits(),
      ).unwrap(),
      4096,
    )
    is Ok(None),
  )
  let rows_short : Array[WriteCollectionItem] = [
    {
      row_preview_cid: collection_request_test_cid("1"),
      body,
      target: RecordId("001000000000001"),
    },
  ]
  let rows_long : Array[WriteCollectionItem] = [
    {
      row_preview_cid: collection_request_test_cid("1"),
      body,
      target: RecordId("001000000000001AAA"),
    },
  ]
  let collection_short = prepare_continue_write_collection(
    rows_short,
    "v66.0",
    collection_request_test_limits(),
  ).unwrap()
  let collection_long = prepare_continue_write_collection(
    rows_long,
    "v66.0",
    collection_request_test_limits(),
  ).unwrap()
  let collection_identity = write_collection_request_target_identity(
      collection_short, 0, 4096,
    )
    .unwrap()
    .unwrap()
  let collection_alias = write_collection_request_target_identity(
      collection_long, 0, 4096,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    write_target_object_cid(collection_identity),
    write_target_object_cid(short_identity),
  )
  assert_eq(
    write_target_object_cid(collection_identity),
    write_target_object_cid(collection_alias),
  )
  assert_true(
    write_collection_request_target_identity(collection_short, 1, 4096)
    is Err(InvalidRows),
  )
  let unknown_matching = prepare_single_write_request(
    collection_case_write_body(""),
    "v66.0",
    ExternalText("ABC123"),
    write_request_test_limits(),
  ).unwrap()
  assert_true(
    single_write_request_target_identity(unknown_matching, 4096)
    is Err(InvalidTarget),
  )
}
