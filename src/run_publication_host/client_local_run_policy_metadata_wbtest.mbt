///|
fn local_policy_metadata_source(wire : String) -> @source.Node {
  @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap()
}

///|
fn local_policy_metadata_at(
  cursor : @decode.Cursor,
  path : Array[String],
) -> @decode.Cursor {
  let mut value = cursor
  for name in path {
    value = @decode.lookup(@decode.open_object(value).unwrap(), name).unwrap()
  }
  value
}

///|
test "actual old109 run original refuses whole-body 8K decoder before policy projection" {
  let wire = local_policy_metadata_old109_run_wire()
  assert_eq(@utf8.encode(wire).length(), 45018)
  assert_eq(
    @sha.hex(@utf8.encode(wire)),
    "f4a9b5e68b66f4d0818431e49e070258ee6438676628e0126021c1e04e7e5b50",
  )
  let result = @decode.admit(local_policy_metadata_source(wire), {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 8192,
    max_total_string_bytes: 65536,
  })
  guard result is Err(issue) else {
    fail("must refuse the genuine large compute strings")
  }
  assert_eq(issue.kind, @decode.BudgetExceeded)
  assert_eq(issue.path, [
    @source.Key("native"),
    @source.Key("run"),
    @source.Key("source_free"),
    @source.Key("ordered"),
  ])
}

///|
test "policy metadata projection retains exact policy values spans and original identity" {
  let bytes = @utf8.encode(local_policy_metadata_old109_run_wire())
  let prior_hash = @sha.hex(bytes)
  let full = @decode.admit(
    local_policy_metadata_source(local_policy_metadata_old109_run_wire()),
    {
      max_nodes: 8192,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    },
  ).unwrap()
  let projected = client_local_run_policy_metadata_cursor(bytes).unwrap()
  for
    path in [
      ["version"],
      ["native", "run", "namespace_id"],
      ["native", "run", "retention_policy_wire"],
      ["native", "run", "source_free", "result_policy_wire"],
      ["native", "run", "source_free", "result_policy_cid"],
    ] {
    let old = local_policy_metadata_at(full, path)
    let current = local_policy_metadata_at(projected, path)
    assert_eq(@decode.text(current), @decode.text(old))
    assert_eq(@decode.cursor_span(current), @decode.cursor_span(old))
    assert_eq(@decode.cursor_path(current), @decode.cursor_path(old))
  }
  let values = local_policy_metadata_at(projected, [
    "native", "run", "source_free",
  ])
  assert_eq(@decode.object_field_names(values).unwrap(), [
    "result_policy_cid", "result_policy_wire",
  ])
  assert_eq(
    @decode.text(local_policy_metadata_at(values, ["result_policy_cid"])).unwrap(),
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  )
  assert_eq(@sha.hex(bytes), prior_hash)
  assert_true(@decode.admission_usage(projected).largest_string_bytes <= 8192)
}

///|
test "policy projection keeps source intake and policy string bounds without truncation or repair" {
  let original = @json.parse(local_policy_metadata_old109_run_wire())
  guard original is Object(root) &&
    root["native"] is Object(native) &&
    native["run"] is Object(run) else {
    fail("fixture")
  }
  run["retention_policy_wire"] = Json::string("x".repeat(8193))
  assert_eq(
    client_local_run_policy_metadata_cursor(@utf8.encode(original.stringify())).map(_ => {
        0
      },
    ),
    Err(ConfigurationLimit),
  )
  let valid = local_policy_metadata_old109_run_wire()
  assert_eq(
    client_local_run_policy_metadata_cursor(
      @utf8.encode(valid + " ".repeat(65537)),
    ).map(_ => 0),
    Err(ConfigurationLimit),
  )
  for wire in [valid + " ", valid] {
    // Whitespace is accepted by the original Source reader, never deleted from
    // custody. The projection cannot replace the original body with its view.
    assert_true(
      client_local_run_policy_metadata_cursor(@utf8.encode(wire)) is Ok(_),
    )
  }
}

///|
test "policy projection rejects unknown envelope fields malformed bodies and duplicate original keys" {
  let original = local_policy_metadata_old109_run_wire()
  for
    wire in [
      original.replace(old="{", new="{\"unknown\":null,"),
      original.replace(
        old="\"source_free\":{",
        new="\"source_free\":{\"unknown\":null,",
      ),
      original.replace(old="{", new="{\"native\":null,"),
      "{}",
      "{",
      "[]",
    ] {
    assert_true(
      client_local_run_policy_metadata_cursor(@utf8.encode(wire)) is Err(_),
    )
  }
}

///|
test "policy metadata projection preserves raw Unicode and CR LF values" {
  let wire = "{\"version\":\"actql-config/0.1\",\"native\":{\"run\":{\"namespace_id\":\"é\",\"retention_policy_wire\":\"a\\r\\nb\\rc\\n\",\"source_free\":{\"registry\":\"" +
    "x".repeat(8193) +
    "\",\"result_policy_cid\":\"sha256:abc\",\"result_policy_wire\":\"é\"}}}}"
  let cursor = client_local_run_policy_metadata_cursor(@utf8.encode(wire)).unwrap()
  assert_eq(
    @decode.text(
      local_policy_metadata_at(cursor, ["native", "run", "namespace_id"]),
    ),
    Ok("é"),
  )
  assert_eq(
    @decode.text(
      local_policy_metadata_at(cursor, [
        "native", "run", "retention_policy_wire",
      ]),
    ),
    Ok("a\r\nb\rc\n"),
  )
  // The actual Policy Owner still admits CID/body, version and domain semantics;
  // projecting these strings does not grant their synthetic values authority.
}
