///|
fn fixture() -> String {
  "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}"
}

///|
fn mutate(old : String, replacement : String) -> String {
  fixture().replace(old~, new=replacement)
}

///|
fn limits() -> @capacity_policy.Limits {
  { max_bytes: 4096, max_nodes: 100, max_depth: 4, }
}

///|
fn read(
  text : String,
) -> Result[@capacity_policy.Policy, @capacity_policy.Issue] {
  let bytes = @utf8.encode(text)
  @capacity_policy.admit(bytes, "sha256:" + @sha.hex(bytes), limits())
}

///|
test "optional string ceiling preserves absence and rejects invalid supplied values" {
  assert_true(
    @capacity_policy.ceiling(
      read(fixture()).unwrap(),
      "max_aggregate_string_bytes",
    )
    is None,
  )
  let prefix = "\"max_aggregate_array_items\":1,"
  for value in ["7", "9007199254740991"] {
    let text = mutate(
      prefix,
      prefix + "\"max_aggregate_string_bytes\":" + value + ",",
    )
    let p = read(text).unwrap()
    let c = @capacity_policy.ceiling(p, "max_aggregate_string_bytes").unwrap()
    assert_true(physical_equal(@capacity_policy.ceiling_policy(c), p))
    if value == "7" {
      assert_eq(@capacity_policy.ceiling_value(c), 7L)
      assert_eq(
        @capacity_policy.cid(p),
        "sha256:8f40fb3e2049be98cec1579dd6ea84dadc4e8dd028eb7888f8a74b94528da9a6",
      )
    } else {
      assert_eq(@capacity_policy.ceiling_value(c), 9007199254740991L)
    }
    let bytes = @utf8.encode(text)
    let exact : @capacity_policy.Limits = {
      max_bytes: bytes.length(),
      max_nodes: 20,
      max_depth: 1,
    }
    assert_true(
      @capacity_policy.admit(bytes, @capacity_policy.cid(p), exact) is Ok(_),
    )
    assert_true(
      @capacity_policy.admit(bytes, @capacity_policy.cid(p), {
        ..exact,
        max_nodes: 19,
      })
      is Err(BudgetExceeded),
    )
    assert_true(
      @capacity_policy.admit(bytes, @capacity_policy.cid(p), {
        ..exact,
        max_bytes: bytes.length() - 1,
      })
      is Err(BudgetExceeded),
    )
  }
  for value in ["null", "0", "-1", "1.5", "9007199254740992", "false", "\"7\""] {
    assert_true(
      read(
        mutate(prefix, prefix + "\"max_aggregate_string_bytes\":" + value + ","),
      )
      is Err(InvalidCeiling("max_aggregate_string_bytes")),
    )
  }
  assert_true(
    read(mutate(prefix, prefix + "\"max_aggregate_string_bytes\":7.0,"))
    is Err(NoncanonicalArtifact),
  )
}

///|
test "policy and ceilings retain an independently pinned canonical source" {
  // Synthetic policy, all ceilings one. Expected identity computed with Node crypto.
  let expected = "sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63"
  let policy = @capacity_policy.admit(
    @utf8.encode(fixture()),
    expected,
    limits(),
  ).unwrap()
  assert_eq(@capacity_policy.cid(policy), expected)
  let row = @capacity_policy.ceiling(policy, "max_relation_output_rows").unwrap()
  assert_eq(@capacity_policy.ceiling_value(row), 1L)
  assert_eq(@capacity_policy.ceiling_field(row), "max_relation_output_rows")
  assert_eq(
    @capacity_policy.cid(@capacity_policy.ceiling_policy(row)),
    expected,
  )
  assert_true(@capacity_policy.ceiling(policy, "max_rows") is None)
  assert_true(
    @capacity_policy.admit(@utf8.encode(fixture()), "sha256:wrong", limits())
    is Err(IdentityMismatch),
  )
  let changed = read(
    mutate("\"max_relation_output_rows\":1", "\"max_relation_output_rows\":2"),
  ).unwrap()
  assert_true(@capacity_policy.cid(changed) != expected)
  assert_eq(@capacity_policy.ceiling_value(row), 1L)
}

///|
test "policy fields are closed required positive safe integers" {
  for bad in ["0", "-1", "1.5", "9007199254740992", "\"1\"", "false"] {
    assert_true(
      read(mutate("\"max_artifact_bytes\":1", "\"max_artifact_bytes\":" + bad))
      is Err(InvalidCeiling("max_artifact_bytes")),
    )
  }
  assert_true(read(mutate("\"max_artifact_bytes\":1,", "")) is Err(InvalidBody))
  assert_true(
    read(mutate("\"max_artifact_bytes\"", "\"unknown\"")) is Err(InvalidBody),
  )
  assert_true(
    read(mutate("actql-capacity-host-policy/0.1", "other"))
    is Err(UnsupportedVersion),
  )
  let maximum = read(
    mutate(
      "\"max_artifact_bytes\":1", "\"max_artifact_bytes\":9007199254740991",
    ),
  ).unwrap()
  assert_eq(
    @capacity_policy.ceiling_value(
      @capacity_policy.ceiling(maximum, "max_artifact_bytes").unwrap(),
    ),
    9007199254740991L,
  )
}

///|
test "self-consistent identity does not admit repaired policy bytes" {
  for
    text in [
      " " + fixture(),
      fixture() + "\n",
      "\u{FEFF}" + fixture(),
      mutate("\"max_artifact_bytes\":1", "\"max_artifact_bytes\":1.0"),
      mutate("\"max_artifact_bytes\":1", "\"max_artifact_bytes\":1e0"),
      mutate("max_artifact_bytes", "max_artifact_byte\\u0073"),
    ] {
    assert_true(read(text) is Err(NoncanonicalArtifact))
  }
  assert_true(
    read(
      mutate(
        "\"max_artifact_bytes\":1", "\"max_artifact_bytes\":1,\"max_artifact_bytes\":1",
      ),
    )
    is Err(InvalidJson),
  )
  assert_true(read("{") is Err(InvalidJson))
}

///|
test "policy admission respects exact byte node and depth limits" {
  let bytes = @utf8.encode(fixture())
  let expected = "sha256:" + @sha.hex(bytes)
  let exact : @capacity_policy.Limits = {
    max_bytes: bytes.length(),
    max_nodes: 19,
    max_depth: 1,
  }
  assert_true(@capacity_policy.admit(bytes, expected, exact) is Ok(_))
  assert_true(
    @capacity_policy.admit(bytes, expected, {
      ..exact,
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_policy.admit(bytes, expected, { ..exact, max_nodes: 18, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_policy.admit(bytes, expected, { ..exact, max_depth: 0, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_policy.admit(bytes, expected, { ..exact, max_bytes: -1, })
    is Err(InvalidLimits),
  )
}
