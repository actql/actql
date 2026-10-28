///|
test "subtree metadata keeps original preorder boundaries for source raw JSON and flat columns" {
  let long = String::make(10000, 'z')
  let first = node(
    @source.Object([
      entry("type", node(@source.String("number"))),
      entry("enum", node(@source.Array([node(@source.String(long))]))),
    ]),
  )
  let source = node(
    @source.Object([
      entry("first", first),
      entry(
        "later",
        node(
          @source.Object([entry("resource_kind", node(@source.String(long)))]),
        ),
      ),
    ]),
  )
  let raw = @json.parse(
    "{\"first\":{\"type\":\"number\",\"enum\":[\"" +
    long +
    "\"]},\"later\":{\"resource_kind\":\"" +
    long +
    "\"}}",
  )
  for
    root in [
      admit(source, budget(total_bytes=100000)).unwrap(),
      admit_raw_json(raw, source.span, budget(total_bytes=100000)).unwrap(),
    ] {
    let view = open_object(root).unwrap()
    let original = required(view, "first").unwrap()
    let geometry = observe_subtree_geometry(original, [
      "type", "resource_kind", "element_type",
    ])
    assert_eq(geometry, {
      nodes: 4,
      objects: 1,
      arrays: 1,
      fields: 2,
      max_fields: 2,
      max_array_items: 1,
      max_selected_text_units: 6,
      outer_depth: 1,
      work: 8L,
    })
    assert_eq(observe_subtree_size(original), (4, 3L))
    let all = observe_subtree_geometry(root, [
      "type", "resource_kind", "element_type",
    ])
    assert_eq(all.nodes, 7)
    assert_eq(all.max_selected_text_units, 10000)
    assert_eq(
      geometry,
      observe_subtree_geometry(original, [
        "type", "resource_kind", "element_type",
      ]),
    )
    assert_eq(
      text(
        element_at(required(open_object(original).unwrap(), "enum").unwrap(), 0).unwrap(),
      ),
      Ok(long),
    )
  }
  let flat = admit_raw_scalar_column(
    [Json::string("a"), Json::null(), @json.parse("true")],
    source.span,
    budget(),
  ).unwrap()
  let geometry = observe_subtree_geometry(flat, [])
  assert_eq(geometry.nodes, 4)
  assert_eq(geometry.arrays, 1)
  assert_eq(geometry.max_array_items, 3)
  assert_eq(geometry.work, 4L)
  let leaf = observe_subtree_geometry(element_at(flat, 0).unwrap(), [])
  assert_eq((leaf.nodes, leaf.outer_depth, leaf.work), (1, 1, 2L))
  assert_eq(observe_subtree_size(flat), (4, 2L))
  assert_eq(observe_subtree_size(element_at(flat, 0).unwrap()), (1, 1L))
}

///|
test "subtree size visits original last-child spine rather than all wide siblings" {
  let source = node(@source.Null)
  let flat = admit_raw_scalar_column(
    Array::make(1000, Json::null()),
    source.span,
    budget(nodes=1001),
  ).unwrap()
  assert_eq(observe_subtree_size(flat), (1001, 2L))
  assert_eq(observe_subtree_geometry(flat, []).nodes, 1001)
}
