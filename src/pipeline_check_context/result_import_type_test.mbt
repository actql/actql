///|
fn import_type_links(identity : ProgramSourceIdentity) -> ProgramIncomingLinks {
  let requirements = collect_program_operation_requirements(
    close_program_expressions(identity, 10000000, 100).unwrap(),
    10000000,
    100,
  ).unwrap()
  let limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 100,
  }
  link_program_incoming(
    resolution_profiles(requirements),
    collect_program_incoming(identity, limits).unwrap(),
    limits,
  ).unwrap()
}

///|
test "Result import type identity comes from the exact prepared publication port" {
  let (identity, _, _) = prepared_identity_fixture()
  let links = import_type_links(identity)
  let incoming = incoming_links_requirements(links)
  // Independent canonical row contract: closed non-null object with id/value,
  // both non-null number. Node crypto SHA-256, UTF-8 size and JSON node count.
  let expected = "sha256:f49cc6ff77d79a594264c5d3b2bd93126e05fd52a4b9d92574910c9400d25a76"
  for i in 1..<3 {
    let v = identify_result_import_type(links, i, 158, 11, 3).unwrap().unwrap()
    assert_eq(result_import_type_cid(v), expected)
    assert_eq(result_import_type_usage(v), (158, 11))
    assert_true(physical_equal(result_import_type_incoming(v), links))
    let site = program_incoming_at(incoming, i).unwrap()
    assert_true(physical_equal(result_import_type_site(v), site))
    guard site.requirement is Result(_, _, port) else { fail("Result import") }
    assert_true(
      physical_equal(
        result_import_type_contract(v),
        @schema.as_object(@results.port_schema(@stage_results.input_port(port))).unwrap(),
      ),
    )
    for (bytes, nodes, depth) in [(157, 11, 3), (158, 10, 3), (158, 11, 2)] {
      assert_true(
        identify_result_import_type(links, i, bytes, nodes, depth)
        is Err(Hash(@encode.OutputLimit)),
      )
    }
    for (bytes, nodes, depth) in [(-1, 11, 3), (158, -1, 3), (158, 11, -1)] {
      assert_true(
        identify_result_import_type(links, i, bytes, nodes, depth)
        is Err(InvalidLimits),
      )
    }
  }
  assert_true(
    identify_result_import_type(links, 0, 158, 11, 3) is Err(NotResult),
  )
  for absent in [-2147483648, -1, 3, 2147483647] {
    assert_true(
      identify_result_import_type(links, absent, 158, 11, 3) is Ok(None),
    )
  }
  let first = identify_result_import_type(links, 1, 158, 11, 3)
    .unwrap()
    .unwrap()
  let again = identify_result_import_type(links, 2, 158, 11, 3)
    .unwrap()
    .unwrap()
  assert_false(
    physical_equal(
      result_import_type_site(first),
      result_import_type_site(again),
    ),
  )
  assert_eq(result_import_type_cid(first), result_import_type_cid(again))
  // Equal row contracts from a rebuilt Program never merge admission owners.
  let (other_identity, _, _) = prepared_identity_fixture()
  let other_links = import_type_links(other_identity)
  let other = identify_result_import_type(other_links, 1, 158, 11, 3)
    .unwrap()
    .unwrap()
  assert_eq(result_import_type_cid(other), expected)
  assert_false(physical_equal(result_import_type_incoming(other), links))
  assert_false(
    physical_equal(
      result_import_type_site(other),
      result_import_type_site(first),
    ),
  )
}

///|
test "Result row types exclude unprojected producer fields and charge each occurrence" {
  let links = import_type_links(incoming_fixture())
  // This producer's Result selects only id, although its pipeline also derives x.
  let v = identify_result_import_type(links, 1, 115, 8, 3).unwrap().unwrap()
  assert_eq(
    result_import_type_cid(v),
    "sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c",
  )
  assert_eq(result_import_type_usage(v), (115, 8))
  let (identity, _, _) = prepared_identity_fixture()
  let repeated = import_type_links(identity)
  for total in [315, 316] {
    let first = identify_result_import_type(repeated, 1, total, 22, 3)
      .unwrap()
      .unwrap()
    let (bytes, nodes) = result_import_type_usage(first)
    let second = identify_result_import_type(
      repeated,
      2,
      total - bytes,
      22 - nodes,
      3,
    )
    if total == 316 {
      assert_true(second is Ok(Some(_)))
    } else {
      assert_true(second is Err(Hash(@encode.OutputLimit)))
    }
  }
}
