///|
fn links_demand(sequence : @lower.PreparedSequence) -> @lower.DemandIndex {
  let roots = @lower.prepare_kernel_roots(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  @lower.prepare_demand(roots, {
    max_roots: 100,
    max_nodes: 10000,
    max_work: 100000,
    max_text_bytes: 100000,
    max_links: 10000,
  }).unwrap()
}

///|
test "ordered links preserve authored slots across lexical root order" {
  let bindings = Array::makei(12, i => {
    "{\"s" + i.to_string() + "\":\"a + " + i.to_string() + "\"}"
  })
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":[" + bindings.join(",") + "]}"),
  )
  let context = execution_for(sequence, 10000L).contexts[0]
  let shapes = prepare_ordered_shapes(context.params, registry_limits()).unwrap()
  let demand = links_demand(sequence)
  let links = prepare_ordered_links(shapes, context, demand, registry_limits()).unwrap()
  assert_true(physical_equal(links.shapes, shapes))
  assert_true(physical_equal(links.limits, context))
  assert_eq(links.slots.length(), 12)
  // Independent hash of the original a/b input shape plus the empty prefix.
  assert_eq(
    links.slots[0].context_cid,
    "sha256:639a958498326fe5fa6f2aa535a5c35864fa5ec3292207e0ad6bd407fcd5696b",
  )
  for i = 0; i < 12; i = i + 1 {
    assert_eq(links.slots[i].name, "s" + i.to_string())
    let text = @identity.stringify_value(
      links.slots[i].root.value,
      10000,
      1000,
      100,
    )
    assert_true(
      text.contains(
        "\"parameter_pointer\":\"/bindings/" + i.to_string() + "/expr\"",
      ),
    )
  }
  // Lexical root slot 2 is binding 10, not authored binding 2.
  let tenth = @identity.stringify_value(
    links.slots[10].root.value,
    10000,
    1000,
    100,
  )
  assert_true(tenth.contains("/roots/2/source"))
  assert_true(links.slots[0].context_cid != links.slots[1].context_cid)
  // Enforce total bytes/nodes for the whole collection, not a fresh cap per slot.
  assert_true(
    prepare_ordered_links(shapes, context, demand, {
      ..registry_limits(),
      max_body_bytes: links.slots[0].root.bytes,
    })
    is Err(_),
  )
  assert_true(
    prepare_ordered_links(shapes, context, demand, {
      ..registry_limits(),
      max_body_nodes: links.slots[0].root.nodes,
    })
    is Err(_),
  )
}

///|
test "ordered link collection rejects a foreign demand owner and foreign limits" {
  let source = ",{\"derive\":[{\"x\":\"a\"}]}"
  let sequence = prepared_sequence(row_owner(source))
  let foreign = prepared_sequence(row_owner(source))
  let context = execution_for(sequence, 1000L).contexts[0]
  let shapes = prepare_ordered_shapes(context.params, registry_limits()).unwrap()
  let demand = links_demand(sequence)
  assert_true(
    prepare_ordered_links(
      shapes,
      context,
      links_demand(foreign),
      registry_limits(),
    )
    is Err(OwnerMismatch),
  )
  assert_true(
    prepare_ordered_links(
      shapes,
      execution_for(foreign, 1000L).contexts[0],
      demand,
      registry_limits(),
    )
    is Err(OwnerMismatch),
  )
  assert_true(
    prepare_ordered_links(shapes, context, demand, registry_limits()) is Ok(_),
  )
}
