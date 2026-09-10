///|
fn limits() -> @text_rank_profile.Limits {
  {
    max_profile_bytes: 10000,
    max_dependency_bytes: 1000,
    max_nodes: 1000,
    max_depth: 20,
  }
}

///|
fn read(
  text : String,
) -> Result[@text_rank_profile.Profile, @text_rank_profile.Issue] {
  let bytes = @utf8.encode(text)
  @text_rank_profile.admit(
    bytes,
    "sha256:" + @sha.hex(bytes),
    blobs(),
    limits(),
  )
}

///|
test "selected profile retains detached dependencies and their identities" {
  let supplied = blobs()
  let p = @text_rank_profile.admit(
    @utf8.encode(fixture()),
    fixture_cid(),
    supplied,
    limits(),
  ).unwrap()
  assert_eq(@text_rank_profile.cid(p), fixture_cid())
  for (kind, bytes) in supplied {
    assert_eq(@text_rank_profile.dependency_bytes(p, kind), bytes)
    assert_eq(
      @text_rank_profile.dependency_cid(p, kind),
      "sha256:" + @sha.hex(bytes),
    )
  }
  supplied.clear()
  assert_eq(
    @text_rank_profile.dependency_bytes(p, UnicodeData),
    @utf8.encode("UnicodeData"),
  )
}

///|
test "dependency set and byte integrity are checked independently" {
  let bytes = @utf8.encode(fixture())
  assert_rejection(
    @text_rank_profile.admit(bytes, "wrong", blobs(), limits()),
    Err(IdentityMismatch),
  )
  let missing = blobs()
  ignore(missing.pop())
  assert_rejection(
    @text_rank_profile.admit(bytes, fixture_cid(), missing, limits()),
    Err(MissingDependency(NumericVectors)),
  )
  let duplicate = blobs()
  duplicate[6] = duplicate[0]
  assert_rejection(
    @text_rank_profile.admit(bytes, fixture_cid(), duplicate, limits()),
    Err(DuplicateDependency(UnicodeData)),
  )
  for i = 0; i < 7; i = i + 1 {
    let changed = blobs()
    let (kind, _) = changed[i]
    changed[i] = (kind, @utf8.encode("changed"))
    assert_rejection(
      @text_rank_profile.admit(bytes, fixture_cid(), changed, limits()),
      Err(DependencyMismatch(kind)),
    )
  }
}

///|
test "canonical bytes and complete supported laws are mandatory" {
  assert_rejection(read(fixture() + "\n"), Err(NoncanonicalArtifact))
  assert_rejection(
    read(fixture().replace(old="maximal_runs", new="different_runs")),
    Err(UnsupportedLaw),
  )
  assert_rejection(
    read(
      fixture().replace(
        old="actql-text-rank-profile/0.1",
        new="unknown-profile",
      ),
    ),
    Err(UnsupportedVersion),
  )
  assert_rejection(read("{}"), Err(InvalidBody))
  assert_rejection(read("{\"x\":1,\"x\":2}"), Err(InvalidJson))
  assert_rejection(read("{"), Err(InvalidJson))
  assert_rejection(
    read(fixture().replace(old="sha256:", new="SHA256:")),
    Err(InvalidDigest),
  )
}

///|
test "profile and cumulative dependency byte limits are inclusive" {
  let bytes = @utf8.encode(fixture())
  let mut size = 0
  for (_, data) in blobs() {
    size += data.length()
  }
  let exact : @text_rank_profile.Limits = {
    max_profile_bytes: bytes.length(),
    max_dependency_bytes: size,
    // Independently counted from the fixed JSON model: keys are not nodes,
    // root object depth is one and the deepest law arrays/objects are three.
    max_nodes: 63,
    max_depth: 3,
  }
  assert_true(
    @text_rank_profile.admit(bytes, fixture_cid(), blobs(), exact) is Ok(_),
  )
  assert_rejection(
    @text_rank_profile.admit(bytes, fixture_cid(), blobs(), {
      ..exact,
      max_profile_bytes: bytes.length() - 1,
    }),
    Err(BudgetExceeded),
  )
  assert_rejection(
    @text_rank_profile.admit(bytes, fixture_cid(), blobs(), {
      ..exact,
      max_dependency_bytes: size - 1,
    }),
    Err(BudgetExceeded),
  )
  assert_rejection(
    @text_rank_profile.admit(bytes, fixture_cid(), blobs(), {
      ..exact,
      max_nodes: 62,
    }),
    Err(BudgetExceeded),
  )
  assert_rejection(
    @text_rank_profile.admit(bytes, fixture_cid(), blobs(), {
      ..exact,
      max_depth: 2,
    }),
    Err(BudgetExceeded),
  )
  assert_rejection(
    @text_rank_profile.admit(bytes, fixture_cid(), blobs(), {
      ..exact,
      max_dependency_bytes: -1,
    }),
    Err(InvalidLimits),
  )
}

///|
fn assert_rejection(
  actual : Result[@text_rank_profile.Profile, @text_rank_profile.Issue],
  expected : Result[Unit, @text_rank_profile.Issue],
) -> Unit raise {
  match actual {
    Ok(_) => fail("expected profile rejection")
    Err(e) => assert_eq(Err(e), expected)
  }
}
