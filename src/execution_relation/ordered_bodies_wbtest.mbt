///|
fn bodies_links(tail : String) -> OrderedLinks raise {
  let sequence = prepared_sequence(row_owner(tail))
  let limits = execution_for(sequence, 10000L).contexts[0]
  let shapes = prepare_ordered_shapes(limits.params, registry_limits()).unwrap()
  prepare_ordered_links(
    shapes,
    limits,
    links_demand(sequence),
    registry_limits(),
  ).unwrap()
}

///|
fn assert_body_closure(text : String, expected_count : Int) -> Unit raise {
  guard @json.parse(text) is Array(bodies) else { fail("array") }
  assert_eq(bodies.length(), expected_count)
  let mut previous = ""
  for body in bodies {
    guard body is Object(fields) else { fail("body") }
    guard fields.get("self_cid") is Some(String(cid)) else { fail("cid") }
    assert_true(@canonical.compare_utf16(previous, cid) < 0)
    previous = cid
    fields.remove("self_cid") |> ignore
    let value = @identity.from_json(body, 10000, 100, 100000)
    assert_eq(@identity.cid_value(value, 100000, 10000, 100), cid)
  }
}

///|
test "ordered closure bodies carry exact self identities and sort without reordering slots" {
  let links = bodies_links(
    ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"z\":\"a\"}]}",
  )
  let contexts = @encode.writer(100000, 10000, 100)
  emit_ordered_context_bodies(links, 3, contexts)
  assert_body_closure(@encode.finish(contexts), 3)
  let shapes = @encode.writer(100000, 10000, 100)
  emit_ordered_shape_bodies(links, shapes)
  assert_body_closure(@encode.finish(shapes), 2)
  let limits = @encode.writer(100000, 10000, 100)
  emit_ordered_limit_bodies(links, limits)
  assert_body_closure(@encode.finish(limits), 1)
  assert_eq(links.slots.map(slot => slot.name), ["old", "a", "z"])
  let short = @encode.writer(100000, 10000, 100)
  let rejected = try {
    emit_ordered_context_bodies(links, 2, short)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "identical input output shape is emitted once and writer budget spans members" {
  let links = bodies_links(",{\"derive\":[{\"a\":\"a\"}]}")
  assert_eq(links.shapes.input_cid, links.shapes.output_cid)
  let shapes = @encode.writer(100000, 10000, 100)
  emit_ordered_shape_bodies(links, shapes)
  let text = @encode.finish(shapes)
  assert_body_closure(text, 1)
  // ASCII fixture: exactly one member fits; another member cannot reset budget.
  let exact = @encode.writer(text.length() + 2, 10000, 100)
  @encode.begin_array(exact)
  emit_ordered_shape_bodies(links, exact)
  let rejected = try {
    emit_ordered_limit_bodies(links, exact)
    @encode.end_array(exact)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
