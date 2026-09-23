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
