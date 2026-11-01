///|
test "member hash retains the same completed depth without repeating its usage callback" {
  let bytes = @utf8.encode("{\"a\":[1,2]}")
  let cursor = @decode.admit(
    @source.parse_json_bytes(bytes, {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
  let limits : Limits = {
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
    max_members: 10,
  }
  let depth : Ref[Int] = Ref(-1)
  let calls : Ref[Int] = Ref(0)
  let emitted : Ref[(Int, Int)?] = Ref(None)
  let observe = (size, nodes) => {
    calls.val += 1
    emitted.val = Some((size, nodes))
  }
  let (cid, size, nodes) = hash(
    cursor,
    limits,
    false,
    usage=Some(observe),
    depth_out=Some(depth),
  )
  assert_eq(cid, "sha256:" + @sha.hex(bytes))
  assert_eq((size, nodes, depth.val), (bytes.length(), 4, 2))
  assert_eq(calls.val, 1)
  assert_eq(emitted.val, Some((size, nodes)))
  depth.val = -1
  calls.val = 0
  emitted.val = None
  let refused = try {
    let _ = hash(
      cursor,
      { ..limits, max_depth: 1, },
      false,
      usage=Some(observe),
      depth_out=Some(depth),
    )
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(refused)
  assert_eq(depth.val, -1)
  assert_eq(calls.val, 1)
  assert_true(emitted.val is Some(_))
}
