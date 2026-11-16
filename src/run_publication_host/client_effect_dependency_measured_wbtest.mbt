///|
test "measured original dependency keeps exact encoder bytes and nodes and full raw identity admission" {
  let writer = @encode.writer(1000, 100, 16)
  @encode.begin_object(writer)
  @encode.key(writer, "value")
  @encode.string_value(writer, "fixture")
  @encode.end_object(writer)
  let (wire, bytes, nodes, depth) = @encode.finish_text_usage(writer)
  // Independent canonical text, dimensions and SHA256; no expected value is
  // obtained by parsing or hashing the body's returned token.
  let cid = "sha256:bc2674594440583782c17d5cf875c88037498d39f5661b6a5962dcf6089752c0"
  assert_eq(wire, "{\"value\":\"fixture\"}")
  assert_eq((bytes, nodes, depth), (19, 2, 1))
  let calls = Ref(0)
  let before = (b : Int, n : Int, d : Int) => {
    calls.val += 1
    b == 19 && n == 2 && d == 2
  }
  let (body, received) = admit_client_effect_dependency_capture_body(
    "request_values",
    Some(cid),
    wire,
    1000,
    100,
    16,
    Some(before),
    () => true,
    wire_extent=Some((bytes, nodes)),
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(received, 19)
  assert_eq(@publication.captured_effect_dependency_body_cid(body), cid)
  assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
  assert_true(
    admit_client_effect_dependency_capture_body(
      "request_values",
      Some(cid),
      wire,
      1000,
      100,
      16,
      Some(before),
      () => true,
      wire_extent=Some((18, 2)),
    )
    is Err(Dependency(@publication.InvalidBody)),
  )
  assert_eq(calls.val, 1)
  // Equal byte/node/depth dimensions never attest another body's identity.
  assert_true(
    admit_client_effect_dependency_capture_body(
      "request_values",
      Some(cid),
      "{\"value\":\"changed\"}",
      1000,
      100,
      16,
      Some(before),
      () => true,
      wire_extent=Some((19, 2)),
    )
    is Err(Dependency(@publication.InvalidBody)),
  )
  assert_eq(calls.val, 2)
  let fallback = Ref((0, 0))
  admit_client_effect_dependency_capture_body(
    "request_values",
    Some(cid),
    wire,
    1000,
    100,
    16,
    Some((b, n, _) => {
      fallback.val = (b, n)
      true
    }),
    () => true,
  ).unwrap()
  |> ignore
  assert_eq(fallback.val, (19, 19))
}
