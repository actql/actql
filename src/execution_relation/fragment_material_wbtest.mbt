///|
fn material_request(tail : String) -> @lower.FragmentRequest {
  let pipeline = @lower.prepare_fragment_pipeline(
    prepared_sequence(row_owner(tail)),
    1,
    { max_roots: 100, max_pointer_bytes: 10000, max_work: 100000, },
  ).unwrap()
  @lower.prepare_fragment_request(pipeline, 10L, 1000L).unwrap()
}

///|
fn material_demands() -> @lower.DemandLimits {
  {
    max_roots: 100,
    max_nodes: 1000,
    max_work: 100000,
    max_text_bytes: 100000,
    max_links: 10000,
  }
}

///|
test "fragment material derives graph and complete roots from the request owner" {
  let request = artifact_request("{\"literal\":7}", 10L)
  let budget = {
    max_body_bytes: 10000,
    max_body_nodes: 1000,
    max_body_depth: 100,
  }
  let material = prepare_fragment_material(request, material_demands(), budget).unwrap()
  assert_true(physical_equal(material.request.request, request))
  assert_eq(material.roots.length(), 1)
  assert_eq(
    material.roots[0].cid,
    "sha256:39003a1c38b4fd68e3fe52959ec054812c4d510d5ec05bc28b2bd7f887e064f3",
  )
  assert_eq(
    @identity.stringify_value(material.graph.value, 10000, 1000, 100),
    "{\"output\":\"derive_1\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{\"x\":{\"body\":7,\"op\":\"literal\"}}}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  let bytes = material.request.artifact.bytes +
    material.graph.bytes +
    material.roots[0].bytes
  assert_true(
    prepare_fragment_material(request, material_demands(), {
      ..budget,
      max_body_bytes: bytes,
    })
    is Ok(_),
  )
  assert_true(
    prepare_fragment_material(request, material_demands(), {
      ..budget,
      max_body_bytes: bytes - 1,
    })
    is Err(_),
  )
  let nodes = material.request.artifact.nodes +
    material.graph.nodes +
    material.roots[0].nodes
  assert_true(
    prepare_fragment_material(request, material_demands(), {
      ..budget,
      max_body_nodes: nodes,
    })
    is Ok(_),
  )
  assert_true(
    prepare_fragment_material(request, material_demands(), {
      ..budget,
      max_body_nodes: nodes - 1,
    })
    is Err(_),
  )
  assert_true(
    prepare_fragment_material(
      request,
      { ..material_demands(), max_roots: 0, },
      budget,
    )
    is Err(Demand(_)),
  )
}

///|
test "empty snapshot retains the graph and multiple roots retain lexical positions" {
  let budget = {
    max_body_bytes: 10000,
    max_body_nodes: 1000,
    max_body_depth: 100,
  }
  let empty = prepare_fragment_material(
    material_request(",{\"derive\":{}}"),
    material_demands(),
    budget,
  ).unwrap()
  assert_eq(empty.roots.length(), 0)
  assert_true(
    @identity.stringify_value(empty.graph.value, 10000, 1000, 100).contains(
      "\"op\":\"REL.derive\"",
    ),
  )
  let material = prepare_fragment_material(
    material_request(
      ",{\"derive\":{\"z\":{\"literal\":2},\"c\":{\"literal\":1}}}",
    ),
    material_demands(),
    budget,
  ).unwrap()
  assert_eq(material.roots.length(), 2)
  let out = @encode.writer(10000, 1000, 100)
  emit_fragment_material_roots(material, out)
  match @json.parse(@encode.finish(out)) {
    Array(entries) =>
      match (entries[0], entries[1]) {
        (Object(first), Object(second)) => {
          assert_true(
            first.get("parameter_pointer") is Some(String("/exprs/c")),
          )
          assert_true(
            second.get("parameter_pointer") is Some(String("/exprs/z")),
          )
        }
        _ => fail("expected root objects")
      }
    _ => fail("expected complete root array")
  }
}
