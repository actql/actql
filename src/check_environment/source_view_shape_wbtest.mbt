///|
fn sv_cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(text, {
    max_input_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 10000,
    max_depth: 100,
    max_string_bytes: 100000,
    max_total_string_bytes: 100000,
  }).unwrap()
}

///|
test "complete SourceView rule accepts a minimal body and rejects nested shape mutations" {
  let wire =
    #|{"schema":"actql.source_view/0.1","connector_id":"x","connector_version":"x","resource_kind":"x","view_id":"x","view_version":"x","acquisition":{"kind":"scan","authority":"read_metadata","request_schema":{"id":"x","version":"x","cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modes":[{"mode":"snapshot","bounded":false}],"default_mode":"snapshot"},"request_processing":{"mutates_business_state":false},"output":{"carrier":"relation","schema":{"id":"x","version":"x","cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"facts":{"id":"x","version":"x","cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"data_policy":{"id":"x","version":"x","cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}},"pushdown":{"contract":{"id":"x","version":"x","cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"operations":[]},"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
  let rule = source_view_shape_rule()
  let used = sv_probe(wire, rule).unwrap()
  assert_eq(sv_probe(wire, rule, cap=used).unwrap(), used)
  assert_true(
    sv_probe(wire, rule, cap=used - 1) is Err(e) && e.kind == WorkLimit,
  )
  for
    (old, replacement) in [
      ("\"connector_version\":\"x\",", ""),
      ("\"scan\"", "\"unknown\""),
      ("\"bounded\":false", "\"bounded\":null"),
      ("\"mutates_business_state\":false", "\"mutates_business_state\":true"),
      ("\"operations\":[]", "\"operations\":[\"x\",\"x\"]"),
      (
        "\"default_mode\":\"snapshot\"", "\"default_mode\":\"snapshot\",\"unknown\":0",
      ),
      ("\"carrier\":\"relation\"", "\"carrier\":\"unknown\""),
    ] {
    assert_true(sv_probe(wire.replace(old~, new=replacement), rule) is Err(_))
  }
}

///|
fn sv_probe(
  text : String,
  rule : SourceViewRule,
  cap? : Int = 10000,
) -> Result[Int, SourceViewShapeIssue] {
  let budget = { left: cap, }
  try {
    validate_view_shape(sv_cursor(text), rule, budget)
    Ok(cap - budget.left)
  } catch {
    ViewShapeStop(e) => Err(e)
  }
}

///|
test "SourceView rule interpreter keeps closed required nullable and unique distinctions" {
  let rule = SVObject([
    ("names", true, SVArray(1, true, SVText(1, [], false))),
    ("flag", false, SVBoolean(Some(false))),
  ])
  let wire = "{\"names\":[\"a\",\"b\"],\"flag\":false}"
  let used = sv_probe(wire, rule).unwrap()
  assert_eq(sv_probe(wire, rule, cap=used).unwrap(), used)
  assert_true(
    sv_probe(wire, rule, cap=used - 1) is Err(e) && e.kind == WorkLimit,
  )
  for
    text in [
      "{}", "{\"names\":null}", "{\"names\":[]}", "{\"names\":[\"\"]}", "{\"names\":[\"a\",\"a\"]}",
      "{\"names\":[\"a\"],\"flag\":true}", "{\"names\":[\"a\"],\"flag\":null}", "{\"names\":[\"a\"],\"extra\":0}",
    ] {
    assert_true(sv_probe(text, rule) is Err(_))
  }
  assert_true(sv_probe("{\"names\":[\"a\"]}", rule) is Ok(_))
  match sv_probe("{\"names\":[\"a\",\"a\"]}", rule) {
    Err(e) => {
      assert_eq(e.kind, DuplicateItem("a"))
      assert_eq(@decode.cursor_path(e.source.unwrap()), [
        @source.Key("names"),
        @source.Index(1),
      ])
    }
    Ok(_) => abort("duplicate accepted")
  }
}

///|
test "SourceView integer schema does not invent a safe integer ceiling" {
  for text in ["1", "9007199254740992", "1e100"] {
    assert_true(sv_probe(text, SVPositiveInteger) is Ok(_))
  }
  for text in ["0", "-1", "1.5", "null", "true", "\"1\""] {
    assert_true(sv_probe(text, SVPositiveInteger) is Err(_))
  }
  assert_true(
    sv_probe("\"sha256:" + "a".repeat(64) + "\"", SVText(0, [], true)) is Ok(_),
  )
  for
    text in [
      "sha256:" + "A".repeat(64),
      "sha256:" + "a".repeat(63),
      "sha256:" + "g".repeat(64),
    ] {
    assert_true(sv_probe("\"" + text + "\"", SVText(0, [], true)) is Err(_))
  }
}

///|
test "Resource identity subtree uses the same generated SourceView rule and work budget" {
  let wire =
    #|{"version":"actql.resource_identity/0.1","provider_namespace":"drive","resource_kind":"file","provider_id_field":"id","output_field":"resource","boundary_topology":"connector_connection"}
  let cursor = sv_cursor(wire)
  let used = check_source_view_resource_identity_shape(cursor, 10000).unwrap()
  assert_true(used > 0)
  assert_eq(
    check_source_view_resource_identity_shape(cursor, used).unwrap(),
    used,
  )
  assert_true(
    check_source_view_resource_identity_shape(cursor, used - 1) is Err(issue) &&
    issue.kind == WorkLimit,
  )
  assert_true(
    check_source_view_resource_identity_shape(cursor, -1) is Err(issue) &&
    issue.kind == InvalidLimits,
  )
  guard source_view_shape_rule() is SVObject(fields) else {
    fail("generated root")
  }
  let mut compared = false
  for (name, _, rule) in fields {
    if name == "resource_identity" {
      assert_eq(sv_probe(wire, rule).unwrap(), used)
      compared = true
    }
  }
  assert_true(compared)
  for
    (old, replacement) in [
      ("drive", ""),
      ("connector_connection", "view"),
      ("actql.resource_identity/0.1", "other"),
      ("\"output_field\":\"resource\"", "\"output_field\":true"),
    ] {
    assert_true(
      check_source_view_resource_identity_shape(
        sv_cursor(wire.replace(old~, new=replacement)),
        10000,
      )
      is Err(_),
    )
  }
}
