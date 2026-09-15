///|
test "lexical selection retains environment and independent byte pin under exact work" {
  let pin = "sha256:" + "a".repeat(64)
  let (body, cid) = wire(
    "{\"text_rank\":{\"profile_bytes_cid\":\"" +
    pin +
    "\",\"version\":\"actql-text-rank-selection/0.1\"}}",
    "[]",
  )
  let environment = read(@utf8.encode(body), cid, caps()).unwrap()
  // Independent Node SHA-256 of the fixed canonical envelope preimage.
  assert_eq(
    cid, "sha256:f675acaace30f4eff8016f14a34a6e0efd0b708ebe72776cea44eeb12d516da1",
  )
  let selected = read_text_rank_selection(environment, 1000).unwrap()
  assert_true(
    physical_equal(text_rank_selection_environment(selected), environment),
  )
  assert_eq(text_rank_selection_cid(selected), pin)
  let pin_source = text_rank_selection_source(selected)
  assert_eq(@decode.text(pin_source), Ok(pin))
  assert_true(physical_equal(pin_source, text_rank_selection_source(selected)))
  assert_true(pin != cid)
  let used = text_rank_selection_work(selected)
  assert_true(read_text_rank_selection(environment, used) is Ok(_))
  assert_true(
    read_text_rank_selection(environment, used - 1) is Err(BudgetExceeded),
  )
  assert_true(read_text_rank_selection(environment, -1) is Err(InvalidLimits))
  let (empty, id) = wire("{}", "[]")
  assert_true(
    read_text_rank_selection(
      read(@utf8.encode(empty), id, caps()).unwrap(),
      1000,
    )
    is Err(MissingSelection),
  )
}

///|
test "lexical selection rejects malformed supplied components even without consumers" {
  for
    value in [
      "null",
      "[]",
      "{}",
      "{\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":null,\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"extra\":1,\"profile_bytes_cid\":\"sha256:" +
      "a".repeat(64) +
      "\",\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":\"sha256:" +
      "A".repeat(64) +
      "\",\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":\"sha256:" +
      "a".repeat(63) +
      "\",\"version\":\"actql-text-rank-selection/0.1\"}",
      "{\"profile_bytes_cid\":\"sha256:" +
      "a".repeat(64) +
      "\",\"version\":\"actql-text-rank-selection/1.0\"}",
    ] {
    let (body, id) = wire("{\"text_rank\":" + value + "}", "[]")
    let environment = read(@utf8.encode(body), id, caps()).unwrap()
    assert_true(
      read_text_rank_selection(environment, 1000) is Err(InvalidComponent),
    )
  }
}

///|
fn lexical_selection(pin : String) -> TextRankSelection {
  let (body, id) = wire(
    "{\"text_rank\":{\"profile_bytes_cid\":\"" +
    pin +
    "\",\"version\":\"actql-text-rank-selection/0.1\"}}",
    "[]",
  )
  read_text_rank_selection(read(@utf8.encode(body), id, caps()).unwrap(), 1000).unwrap()
}

///|
test "profile admission uses selected original bytes and retains exact environment ownership" {
  let selection = lexical_selection(text_profile_fixture_cid())
  let bytes = @utf8.encode(text_profile_fixture())
  let dependencies = text_profile_blobs()
  let limits : @lexical.Limits = {
    max_profile_bytes: bytes.length(),
    max_dependency_bytes: 1000,
    max_nodes: 1000,
    max_depth: 20,
  }
  let admitted = admit_text_rank_profile(selection, bytes, dependencies, limits).unwrap()
  assert_true(physical_equal(selected_text_rank_selection(admitted), selection))
  assert_eq(
    @lexical.cid(selected_text_rank_profile(admitted)),
    text_rank_selection_cid(selection),
  )
  dependencies.clear()
  assert_eq(
    @lexical.dependency_bytes(selected_text_rank_profile(admitted), UnicodeData),
    @utf8.encode("UnicodeData"),
  )
  let reissued = lexical_selection(text_profile_fixture_cid())
  let other = admit_text_rank_profile(
    reissued,
    bytes,
    text_profile_blobs(),
    limits,
  ).unwrap()
  assert_true(
    !physical_equal(
      text_rank_selection_environment(selected_text_rank_selection(admitted)),
      text_rank_selection_environment(selected_text_rank_selection(other)),
    ),
  )
  assert_true(
    admit_text_rank_profile(
      lexical_selection("sha256:" + "0".repeat(64)),
      bytes,
      text_profile_blobs(),
      limits,
    )
    is Err(IdentityMismatch),
  )
  assert_true(admit_text_rank_profile(selection, bytes, [], limits) is Err(_))
  let changed = text_profile_blobs()
  changed[0] = (@lexical.UnicodeData, @utf8.encode("different"))
  assert_true(
    admit_text_rank_profile(selection, bytes, changed, limits)
    is Err(DependencyMismatch(UnicodeData)),
  )
  assert_true(
    admit_text_rank_profile(
      selection,
      @utf8.encode(" " + text_profile_fixture()),
      text_profile_blobs(),
      { ..limits, max_profile_bytes: bytes.length() + 1, },
    )
    is Err(_),
  )
  assert_true(
    admit_text_rank_profile(selection, bytes, text_profile_blobs(), {
      ..limits,
      max_profile_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    admit_text_rank_profile(selection, bytes, text_profile_blobs(), {
      ..limits,
      max_dependency_bytes: 0,
    })
    is Err(BudgetExceeded),
  )
}
