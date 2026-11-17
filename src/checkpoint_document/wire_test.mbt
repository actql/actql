///|
fn limits() -> @checkpoint_document.Limits {
  { max_wire_bytes: 10000, max_nodes: 100, max_depth: 10, }
}

///|
test "pure Checkpoint document profiles preserve the closed existing table and claim order" {
  for
    (kind, artifact) in [
      ("run_scope", "prepared_invocation"),
      ("read_access", "read_scope"),
      ("data_egress", "egress_scope"),
      ("cost_scope", "budget_scope"),
      ("model_invocation", "model_invocation_scope"),
      ("effect_set", "effect_set_preview"),
    ] {
    assert_eq(@checkpoint_document.artifact_type(kind), Some(artifact))
    assert_true(
      @checkpoint_document.requirements_valid(
        kind,
        if kind == "effect_set" {
          ["effect_scope_approved"]
        } else {
          ["invocation_scope_approved"]
        },
      ),
    )
  }
  assert_true(
    @checkpoint_document.combination_valid(
      "prepare_attempt", "preflight", "run_scope",
    ),
  )
  assert_false(
    @checkpoint_document.combination_valid("run_unit", "preflight", "run_scope"),
  )
  assert_true(
    @checkpoint_document.combination_valid("run_unit", "commit", "effect_set"),
  )
  assert_false(
    @checkpoint_document.combination_valid(
      "run_unit", "preflight", "effect_set",
    ),
  )
  assert_false(
    @checkpoint_document.combination_valid(
      "foreign", "preflight", "read_access",
    ),
  )
  assert_eq(@checkpoint_document.artifact_type("foreign"), None)
  assert_false(
    @checkpoint_document.requirements_valid("foreign", [
      "invocation_scope_approved",
    ]),
  )
  assert_false(
    @checkpoint_document.requirements_valid("effect_set", [
      "partial_application_accepted", "effect_scope_approved",
    ]),
  )
  assert_false(
    @checkpoint_document.requirements_valid("effect_set", [
      "effect_scope_approved", "effect_scope_approved",
    ]),
  )
}

///|
test "pure Checkpoint document canonical bytes retain exact data Text and existing identifier domain" {
  let original = @checkpoint_document.parse_wire(
    "{\"b\":\"e\\u0301\\r\\n\",\"a\":true}",
    limits(),
  ).unwrap()
  assert_eq(
    @checkpoint_document.wire_of(original, limits()),
    Some("{\"a\":true,\"b\":\"é\\r\\n\"}"),
  )
  assert_true(@checkpoint_document.canonical_text("é"))
  assert_false(@checkpoint_document.canonical_text("é"))
  assert_false(@checkpoint_document.canonical_text("a\r\nb"))
  assert_true(@checkpoint_document.valid_timestamp("2024-02-29T00:00:00.000Z"))
  assert_false(@checkpoint_document.valid_timestamp("2026-02-29T00:00:00.000Z"))
  // Checkpoint decision windows deliberately use their existing fixed-width
  // millisecond domain, independently of SQL scalar Timestamp precision.
  assert_false(
    @checkpoint_document.valid_timestamp("2024-02-29T00:00:00.123456789Z"),
  )
  assert_true(
    @checkpoint_document.parse_wire("{}", { ..limits(), max_wire_bytes: 1, })
    is None,
  )
}

///|
test "pure Reviewer signature representation rejects aliases lengths and nonzero pad bits" {
  let canonical = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
  assert_true(@checkpoint_document.reviewer_signature_valid(canonical))
  for
    signature in [
      "",
      "AAAA",
      canonical + "\n",
      canonical.replace(old="AA==", new="AB=="),
      canonical.replace(old="==", new="__"),
    ] {
    assert_false(@checkpoint_document.reviewer_signature_valid(signature))
  }
}
