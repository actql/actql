///|
test "ordered binding closes the node roots contexts shapes and limits without accepting foreign IDs" {
  let links = bodies_links(
    ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}",
  )
  let binding = prepare_ordered_binding(links, registry_limits()).unwrap()
  assert_eq(
    binding.node.graph.cid,
    "sha256:45961666ce15c01a481fc383d390b4b1f86b152d0fb918bf4ccc69aeb4733755",
  )
  let text = @identity.stringify_value(
    binding.artifact.value,
    100000,
    10000,
    100,
  )
  assert_true(text.contains("\"mode\":\"ordered_array\""))
  assert_true(text.contains("\"input_passthrough\":true"))
  assert_true(text.contains("\"failure_scope\":\"row-binding-expression\""))
  assert_true(text.contains(links.limits.cid))
  assert_true(text.contains(links.shapes.input_cid))
  assert_true(text.contains(links.shapes.output_cid))
  for slot in links.slots {
    assert_true(text.contains(slot.root.cid))
    assert_true(text.contains(slot.context_cid))
  }
  links.slots.clear()
  let out = @encode.writer(100000, 10000, 100)
  emit_ordered_evidence(binding, 2, out)
  guard @json.parse(@encode.finish(out)) is Object(closure) else {
    fail("closure")
  }
  assert_eq(closure.length(), 4)
  for
    (name, count) in [
      ("bindings", 1),
      ("contexts", 2),
      ("limits", 1),
      ("shapes", 2),
    ] {
    let value = @identity.from_json(
      closure.get(name).unwrap(),
      10000,
      100,
      100000,
    )
    assert_body_closure(
      @identity.stringify_value(value, 100000, 10000, 100),
      count,
    )
  }
  assert_eq(binding.links.slots.map(slot => slot.name), ["old", "a"])
}

///|
test "ordered binding construction budget includes both node artifacts and binding body" {
  let links = bodies_links(",{\"derive\":[{\"a\":\"a\"}]}")
  let binding = prepare_ordered_binding(links, registry_limits()).unwrap()
  let bytes = binding.node.source.bytes +
    binding.node.graph.bytes +
    binding.artifact.bytes
  let nodes = binding.node.source.nodes +
    binding.node.graph.nodes +
    binding.artifact.nodes
  let exact = {
    ..registry_limits(),
    max_body_bytes: bytes,
    max_body_nodes: nodes,
  }
  assert_true(prepare_ordered_binding(links, exact) is Ok(_))
  assert_true(
    prepare_ordered_binding(links, { ..exact, max_body_bytes: bytes - 1, })
    is Err(OutputLimit),
  )
  assert_true(
    prepare_ordered_binding(links, { ..exact, max_body_nodes: nodes - 1, })
    is Err(OutputLimit),
  )
}
