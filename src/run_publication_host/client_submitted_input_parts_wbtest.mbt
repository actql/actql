///|
fn submitted_parts_wire() -> String {
  "{\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"kind\":\"aql\",\"parameters\":null}"
}

///|
fn submitted_parts_tree_limits() -> @decode.Limits {
  {
    max_nodes: 1000,
    max_depth: 20,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }
}

///|
// The previous immediate consumer reconstructed the already issued wire.
fn previous_submitted_input_parts(
  wire : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
  tree : @decode.Limits,
  read : (Bytes, @source.ParseLimits) -> Result[
    @source.Node,
    @source.ParseError,
  ],
) -> Result[
  (ClientSubmittedIntent, @canonical.CanonicalValue, @decode.Cursor),
  ClientSubmittedIntentIssue,
] {
  let (intent, _, _) = match
    prepare_client_submitted_intent_originals(
      wire, bytes, nodes, depth, false, read,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let source = match
    read(@utf8.encode(intent.wire), {
      max_input_bytes: bytes,
      max_nodes: nodes,
      max_depth: depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(Limit)
  }
  let value = @canonical.from_source(
    source,
    nodes,
    depth,
    bytes,
    data_keys=true,
  ) catch {
    _ => return Err(InvalidEnvelope)
  }
  let cursor = match @decode.admit(source, tree) {
    Ok(value) => value
    Err(_) => return Err(InvalidEnvelope)
  }
  Ok((intent, value, cursor))
}

///|
fn submitted_parts_text(cursor : @decode.Cursor) -> @decode.Cursor {
  let root = @decode.open_object(cursor).unwrap()
  let input = @decode.required(root, "input").unwrap()
  @decode.required(@decode.open_object(input).unwrap(), "text").unwrap()
}

///|
test "canonical submitted input parses once and retains the exact prior facts" {
  let wire = submitted_parts_wire()
  let calls = Ref(0)
  let read = (bytes, limits) => {
    calls.val += 1
    @source.parse_json_bytes_preserving(bytes, limits)
  }
  let prior = previous_submitted_input_parts(
    wire,
    10000,
    1000,
    20,
    submitted_parts_tree_limits(),
    read,
  ).unwrap()
  assert_eq(calls.val, 2)
  calls.val = 0
  let current = prepare_client_submitted_input_parts_with_reader(
    wire,
    10000,
    1000,
    20,
    submitted_parts_tree_limits(),
    read,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(current.0, prior.0)
  assert_eq(@canonical.stringify_value(current.1, 10000, 1000, 20), wire)
  assert_eq(@decode.text(submitted_parts_text(current.2)), Ok("SELECT 1 AS n"))
  assert_eq(
    @decode.cursor_span(submitted_parts_text(current.2)),
    @decode.cursor_span(submitted_parts_text(prior.2)),
  )
  assert_eq(
    @decode.cursor_key_span(submitted_parts_text(current.2)),
    @decode.cursor_key_span(submitted_parts_text(prior.2)),
  )
  assert_eq(
    @decode.cursor_path(submitted_parts_text(current.2)),
    @decode.cursor_path(submitted_parts_text(prior.2)),
  )
}

///|
test "noncanonical submitted input keeps its original canonical diagnostic coordinates" {
  let wire = " {\"parameters\":null, \"kind\":\"aql\", \"input\":{\"text\":\"SELECT 1 AS n\", \"format\":\"sql\"}} "
  let calls = Ref(0)
  let read = (bytes, limits) => {
    calls.val += 1
    @source.parse_json_bytes_preserving(bytes, limits)
  }
  let current = prepare_client_submitted_input_parts_with_reader(
    wire,
    10000,
    1000,
    20,
    submitted_parts_tree_limits(),
    read,
  ).unwrap()
  assert_eq(calls.val, 2)
  let prior = previous_submitted_input_parts(
    wire,
    10000,
    1000,
    20,
    submitted_parts_tree_limits(),
    read,
  ).unwrap()
  assert_eq(current.0, prior.0)
  assert_eq(current.0.wire, submitted_parts_wire())
  assert_eq(
    @decode.cursor_span(submitted_parts_text(current.2)),
    @decode.cursor_span(submitted_parts_text(prior.2)),
  )
  assert_eq(
    @decode.cursor_key_span(submitted_parts_text(current.2)),
    @decode.cursor_key_span(submitted_parts_text(prior.2)),
  )
}

///|
test "submitted input parts retain source tree and decoder refusal ordering" {
  let read = (bytes, limits) => {
    @source.parse_json_bytes_preserving(bytes, limits)
  }
  let tree = submitted_parts_tree_limits()
  let wire = submitted_parts_wire()
  for
    (input, bytes, nodes, depth, selected_tree) in [
      (wire, -1, 1000, 20, tree),
      (wire, wire.length() - 1, 1000, 20, tree),
      (wire, 10000, 1, 20, tree),
      (wire, 10000, 1000, 1, tree),
      (wire, 10000, 1000, 2147483647, tree),
      (wire, 10000, 1000, 20, { ..tree, max_nodes: 1, }),
      (wire, 10000, 1000, 20, { ..tree, max_string_bytes: 2, }),
      (wire, 10000, 1000, 20, { ..tree, max_total_string_bytes: 2, }),
      (wire + "x", 10000, 1000, 20, tree),
      ("{}", 10000, 1000, 20, tree),
      (
        "{\"kind\":\"aql\",\"input\":{},\"parameters\":null,\"readOnly\":false}",
        10000, 1000, 20, tree,
      ),
    ] {
    let prior = previous_submitted_input_parts(
      input, bytes, nodes, depth, selected_tree, read,
    )
    let current = prepare_client_submitted_input_parts_with_reader(
      input, bytes, nodes, depth, selected_tree, read,
    )
    guard prior is Err(before) && current is Err(after) else {
      fail("Expected both preparations to refuse")
    }
    assert_true(
      match (before, after) {
        (InvalidLimits, InvalidLimits)
        | (Limit, Limit)
        | (InvalidEnvelope, InvalidEnvelope)
        | (Encoding, Encoding) => true
        _ => false
      },
    )
  }
  // A finite policy depth above the former implementation cap remains valid.
  // Only overflow of the hash-envelope headroom is an invalid limit.
  let prior = previous_submitted_input_parts(wire, 10000, 1000, 65, tree, read).unwrap()
  let current = prepare_client_submitted_input_parts_with_reader(
    wire, 10000, 1000, 65, tree, read,
  ).unwrap()
  assert_eq(current.0, prior.0)
  assert_eq(current.0.wire, wire)
}

///|
test "submitted input parts retain only their own immutable values and cursor" {
  let wire = submitted_parts_wire()
  let first = prepare_client_submitted_input_parts(
    wire,
    10000,
    1000,
    20,
    submitted_parts_tree_limits(),
  ).unwrap()
  let changed_wire = "{\"input\":{\"format\":\"sql\",\"text\":\"SELECT 2 AS n\"},\"kind\":\"aql\",\"parameters\":null}"
  let next = prepare_client_submitted_input_parts(
    changed_wire,
    10000,
    1000,
    20,
    submitted_parts_tree_limits(),
  ).unwrap()
  assert_false(first.0.cid == next.0.cid)
  assert_eq(@decode.text(submitted_parts_text(first.2)), Ok("SELECT 1 AS n"))
  assert_eq(@decode.text(submitted_parts_text(next.2)), Ok("SELECT 2 AS n"))
  let fields = @canonical.object_fields(first.1).unwrap()
  fields[0] = (
    "changed",
    @canonical.object_field(first.1, "parameters").unwrap(),
  )
  assert_eq(@canonical.stringify_value(first.1, 10000, 1000, 20), wire)
  assert_eq(first.0.wire, wire)
}
