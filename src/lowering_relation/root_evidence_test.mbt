///|
test "complete root projection binds independent source node type and demand" {
  let roots = demand_roots_for("{\"literal\":7}")
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  let evidence = @lowering_relation.prepare_root_evidence(index, 0, {
    max_nodes: 1,
    max_tests: 0,
    max_pointer_bytes: 15,
  }).unwrap()
  let out = @encode.writer(4096, 100, 20)
  @lowering_relation.emit_root_evidence(evidence, out)
  assert_eq(
    @encode.finish(out),
    "{\"contract\":{\"nullable\":false,\"type\":\"number\"},\"demand_paths\":{\"/roots/0/source\":[]},\"node\":{\"body\":7,\"op\":\"literal\"},\"parameter_pointer\":\"/exprs/out\",\"source\":{\"literal\":7},\"step_id\":\"derive_1\"}",
  )
  assert_true(
    @lowering_relation.prepare_root_evidence(index, 0, {
      max_nodes: 0,
      max_tests: 0,
      max_pointer_bytes: 100,
    })
    is Err(@lowering_relation.EvidenceLimit),
  )
  assert_true(
    @lowering_relation.prepare_root_evidence(index, 0, {
      max_nodes: 1,
      max_tests: 0,
      max_pointer_bytes: 14,
    })
    is Err(_),
  )
  assert_true(
    @lowering_relation.prepare_root_evidence(index, 1, {
      max_nodes: 10,
      max_tests: 10,
      max_pointer_bytes: 100,
    })
    is Err(@lowering_relation.MissingEvidenceRoot),
  )
}

///|
test "root evidence preserves lazy demands and cannot detach another root" {
  let roots = demand_roots_for(
    "{\"if\":[{\"literal\":true},{\"literal\":7},{\"literal\":9}]}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  // Root address 15 + three child addresses 20 + two condition addresses 20.
  let limits : @lowering_relation.RootEvidenceLimits = {
    max_nodes: 4,
    max_tests: 2,
    max_pointer_bytes: 115,
  }
  let evidence = @lowering_relation.prepare_root_evidence(index, 0, limits).unwrap()
  let out = @encode.writer(4096, 100, 20)
  @lowering_relation.emit_root_evidence(evidence, out)
  let text = @encode.finish(out)
  assert_true(
    text.contains(
      "\"/roots/0/source/if/1\":[{\"pointer\":\"/roots/0/source/if/0\",\"test\":\"true\"}]",
    ),
  )
  assert_true(
    text.contains(
      "\"/roots/0/source/if/2\":[{\"pointer\":\"/roots/0/source/if/0\",\"test\":\"not_true\"}]",
    ),
  )
  assert_true(
    @lowering_relation.prepare_root_evidence(index, 0, {
      ..limits,
      max_tests: 1,
    })
    is Err(_),
  )
  assert_true(
    @lowering_relation.prepare_root_evidence(index, 0, {
      ..limits,
      max_pointer_bytes: 114,
    })
    is Err(_),
  )
  let short = @encode.writer(1, 100, 20)
  let rejected = try {
    @lowering_relation.emit_root_evidence(evidence, short)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "root evidence excludes an implicit else source and opaque literal children" {
  for
    expr in [
      "{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"literal\":1}}]}}",
      "{\"literal\":{\"$param\":\"not-a-reference\",\"if\":[true,7,9]}}",
    ] {
    let index = @lowering_relation.prepare_demand(
      demand_roots_for(expr),
      demand_limits(),
    ).unwrap()
    let evidence = @lowering_relation.prepare_root_evidence(index, 0, {
      max_nodes: 10,
      max_tests: 10,
      max_pointer_bytes: 1000,
    }).unwrap()
    let out = @encode.writer(4096, 200, 30)
    @lowering_relation.emit_root_evidence(evidence, out)
    let text = @encode.finish(out)
    assert_false(text.contains("/source/case/else"))
    assert_false(text.contains("/source/literal/"))
  }
}
