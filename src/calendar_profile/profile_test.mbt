///|
fn fixture() -> String {
  "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}"
}

///|
fn limits() -> @calendar_profile.Limits {
  {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_zones: 10,
    max_transitions: 100,
  }
}

///|
fn read(
  text : String,
) -> Result[@calendar_profile.Profile, @calendar_profile.Issue] {
  let bytes = @utf8.encode(text)
  @calendar_profile.admit(
    bytes,
    "sha256:" + @sha.hex(bytes),
    "test-fixture",
    limits(),
  )
}

///|
test "fixed independent byte identity binds version and exact zone lookup" {
  // Synthetic UTC-only fixture. Expected digest computed with Node crypto,
  // not the product encoder. This is not an IANA dataset certification.
  let expected = "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca"
  let p = @calendar_profile.admit(
    @utf8.encode(fixture()),
    expected,
    "test-fixture",
    limits(),
  ).unwrap()
  assert_eq(@calendar_profile.cid(p), expected)
  assert_eq(@calendar_profile.tzdb_version(p), "test-fixture")
  let t = @calendar_profile.zone(p, "UTC").unwrap()
  assert_eq(@transition.offset_at(t, 0L), Some(0))
  assert_true(@calendar_profile.zone(p, "utc") is None)
  assert_true(@calendar_profile.zone(p, "Unknown/Zone") is None)
  assert_true(
    @calendar_profile.admit(
      @utf8.encode(fixture()),
      expected,
      "other",
      limits(),
    )
    is Err(UnsupportedVersion),
  )
  assert_true(
    @calendar_profile.admit(
      @utf8.encode(fixture()),
      "sha256:wrong",
      "test-fixture",
      limits(),
    )
    is Err(IdentityMismatch),
  )
}

///|
test "matching raw hash cannot authorize noncanonical repairs" {
  for
    text in [
      " " + fixture(),
      fixture() + "\n",
      "\u{feff}" + fixture(),
      fixture().replace(old="253402300800000", new="253402300800000.0"),
      fixture().replace(old="UTC", new="\\u0055TC"),
    ] {
    assert_true(read(text) is Err(NoncanonicalArtifact))
  }
  assert_true(
    read(fixture().replace(old="\"version\":", new="\"extra\":0,\"version\":"))
    is Err(InvalidBody),
  )
  assert_true(
    read(
      fixture().replace(
        old="\"zones\":",
        new="\"version\":\"actql-tzdb-table/0.1\",\"zones\":",
      ),
    )
    is Err(InvalidJson),
  )
}

///|
test "profile rejects unsupported law coverage and UTC substitutions" {
  assert_true(
    read(fixture().replace(old="boundaries/0.1", new="boundaries/9.9"))
    is Err(UnsupportedLaw),
  )
  assert_true(
    read(fixture().replace(old="table/0.1", new="table/9.9"))
    is Err(UnsupportedVersion),
  )
  assert_true(
    read(fixture().replace(old="-62135596800000", new="0"))
    is Err(InvalidCoverage),
  )
  assert_true(read(fixture().replace(old="UTC", new="GMT")) is Err(InvalidZone))
  assert_true(
    read(fixture().replace(old="seconds\":0", new="seconds\":1"))
    is Err(InvalidZone),
  )
}

///|
test "zone names cannot be normalized or reordered during artifact admission" {
  let zone = "{\"initial_offset_seconds\":0,\"transitions\":[]}"
  let body = fixture().replace(
    old="\"zones\":{",
    new="\"zones\":{\"A\":" + zone + ",",
  )
  assert_true(read(body) is Ok(_))
  let reordered = fixture().replace(
    old="\"zones\":{",
    new="\"zones\":{\"Z\":" + zone + ",",
  )
  assert_true(read(reordered) is Err(NoncanonicalArtifact))
  let decomposed = fixture().replace(
    old="[]}}}",
    new="[]},\"e\u{0301}\":" + zone + "}}",
  )
  assert_true(read(decomposed) is Err(NoncanonicalArtifact))
  let two = body.replace(
    old="\"A\":" + zone,
    new="\"A\":{\"initial_offset_seconds\":0,\"transitions\":[{\"at_ms\":0,\"offset_seconds\":1}]},\"B\":{\"initial_offset_seconds\":0,\"transitions\":[{\"at_ms\":0,\"offset_seconds\":1}]}",
  )
  let bytes = @utf8.encode(two)
  assert_true(
    @calendar_profile.admit(
      bytes,
      "sha256:" + @sha.hex(bytes),
      "test-fixture",
      { ..limits(), max_transitions: 1, },
    )
    is Err(BudgetExceeded),
  )
  assert_true(read(two) is Ok(_))
}

///|
test "resource limits reject before exposing a profile" {
  let bytes = @utf8.encode(fixture())
  let cid = "sha256:" + @sha.hex(bytes)
  for
    l in [
      { ..limits(), max_bytes: bytes.length() - 1, },
      { ..limits(), max_nodes: 0, },
      { ..limits(), max_depth: 0, },
      { ..limits(), max_zones: 0, },
    ] {
    assert_true(
      @calendar_profile.admit(bytes, cid, "test-fixture", l)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    @calendar_profile.admit(bytes, cid, "test-fixture", {
      ..limits(),
      max_transitions: -1,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    @calendar_profile.admit(bytes, cid, "test-fixture", {
      ..limits(),
      max_bytes: bytes.length(),
      max_transitions: 0,
    })
    is Ok(_),
  )
}

///|
test "transitions share a profile-wide budget and retain signed seconds" {
  let body = fixture().replace(
    old="\"zones\":{",
    new="\"zones\":{\"Test/Zone\":{\"initial_offset_seconds\":-30,\"transitions\":[{\"at_ms\":0,\"offset_seconds\":3600}]},",
  )
  let p = read(body).unwrap()
  let t = @calendar_profile.zone(p, "Test/Zone").unwrap()
  assert_eq(@transition.offset_at(t, -1L), Some(-30))
  assert_eq(@transition.offset_at(t, 0L), Some(3600))
  let bytes = @utf8.encode(body)
  assert_true(
    @calendar_profile.admit(
      bytes,
      "sha256:" + @sha.hex(bytes),
      "test-fixture",
      { ..limits(), max_transitions: 0, },
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    read(body.replace(old="\"at_ms\":0", new="\"at_ms\":253402300800000"))
    is Err(InvalidTable("Test/Zone", InvalidTransition(0))),
  )
}
