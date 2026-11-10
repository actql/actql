///|
fn preview_cursor_fixture(wire : String) -> @decode.Cursor {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }).unwrap()
  @decode.admit(source, {
    max_nodes: 256,
    max_depth: 12,
    max_string_bytes: 8192,
    max_total_string_bytes: 8192,
  }).unwrap()
}

///|
test "funded Preview cursor retains the same admitted root and complete identity" {
  let run = preview_identity_test_cid("b")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let a = preview_identity_test_cid("a")
  let draft = preview_identity_test_wire(
    run,
    authoring,
    preview_identity_test_cid("4"),
    "original-row",
    a,
    a,
  ).replace_all(old="{\"Name\":\"After\"}", new="{\"é\":2,\"é\":1}")
  let (wire, _) = author_effect_preview_semantic_wire(
    draft, run, authoring, 8192, 256, 12,
  ).unwrap()
  let (original, root) = admit_effect_preview_identity_cursor_with_original(
    wire,
    preview_cursor_fixture(wire),
    run,
    authoring,
    8192,
    256,
    12,
  ).unwrap()
  let same = admit_effect_preview_identity(wire, run, authoring, 8192, 256, 12).unwrap()
  assert_eq(
    effect_preview_semantic_identity(original),
    effect_preview_semantic_identity(same),
  )
  assert_eq(
    effect_preview_row_identity(original, 0, 0),
    effect_preview_row_identity(same, 0, 0),
  )
  assert_eq(@json.stringify_value(root, 8192, 256, 12), wire)
  let data = effect_preview_row_intended_value_wire(original, 0, 0).unwrap()
  assert_true(data.contains("\"é\":2"))
  assert_true(data.contains("\"é\":1"))
}

///|
test "funded Preview cursor refuses foreign wire Run and nested identity without reissue" {
  let run = preview_identity_test_cid("b")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let a = preview_identity_test_cid("a")
  let (wire, _) = author_effect_preview_semantic_wire(
    preview_identity_test_wire(
      run,
      authoring,
      preview_identity_test_cid("4"),
      "original-row",
      a,
      a,
    ),
    run,
    authoring,
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    admit_effect_preview_identity_cursor_with_original(
      wire + " ",
      preview_cursor_fixture(wire),
      run,
      authoring,
      8192,
      256,
      12,
    )
    is Err(PreviewShape(InvalidWire)),
  )
  assert_true(
    admit_effect_preview_identity_cursor_with_original(
      wire,
      preview_cursor_fixture(wire),
      a,
      authoring,
      8192,
      256,
      12,
    )
    is Err(RunBindingMismatch),
  )
  let changed = wire.replace_all(old="After", new="Other")
  assert_true(
    admit_effect_preview_identity_cursor_with_original(
      changed,
      preview_cursor_fixture(changed),
      run,
      authoring,
      8192,
      256,
      12,
    )
    is Err(_),
  )
}
