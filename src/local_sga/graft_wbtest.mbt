///|
test "graft exact fold is idempotent with parallel edges and canonical typed identities" {
  let carrier = union_fold_test_carrier()
  let left = union_fold_test_input(carrier)
  let right = union_fold_test_input(carrier)
  let checked = @graph_type.check_graft(
    union_fold_test_cursor("{\"with\":\"peer\"}"),
    [carrier, carrier],
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let mut previous = None
  for quantum in [1, 7, 64] {
    let builder = @storage.prepare(
      @graph_type.union_output(checked),
      DeclaredNodes,
      union_fold_test_limits(),
    ).unwrap()
    let fold = prepare_union_fold(
      checked,
      0,
      Accumulated(left),
      Accumulated(right),
      builder,
      union_fold_test_limits(),
      100000,
    ).unwrap()
    let (output, work) = union_fold_test_finish(fold, quantum)
    if previous is Some(expected) {
      assert_eq(work, expected)
    } else {
      previous = Some(work)
    }
    cleanup_union_fold(fold)
    assert_eq(@storage.node_count(output), 2)
    assert_eq(@storage.edge_count(output), 2)
    for index in 0..<2 {
      assert_eq(
        union_property_test_wire(
          @storage.node_typed_key_at(output, index, 0).unwrap(),
        ),
        (index + 1).to_string(),
      )
      assert_eq(
        union_property_test_wire(
          @storage.node_property(output, index, 0).unwrap(),
        ),
        "2",
      )
      assert_eq(
        union_property_test_wire(
          @storage.node_property(output, index, 1).unwrap(),
        ),
        "7",
      )
      assert_eq(
        union_property_test_wire(
          @storage.edge_typed_key_at(output, index, 0).unwrap(),
        ),
        (index + 10).to_string(),
      )
      assert_eq(
        union_property_test_wire(
          @storage.edge_property(output, index, 0).unwrap(),
        ),
        "2",
      )
      assert_eq(@storage.edge_endpoints(output, index), Some((0, 1)))
    }
    @storage.discard(output)
    assert_true(@storage.available(left) && @storage.available(right))
  }
  @storage.discard(left)
  @storage.discard(right)
}

///|
test "graft rejects a shared edge endpoint conflict without reclaiming either input" {
  let carrier = union_fold_test_carrier()
  let left = union_fold_test_input(carrier)
  let right = union_fold_test_input(carrier, conflict=true)
  let checked = @graph_type.check_graft(
    union_fold_test_cursor("{\"with\":\"peer\"}"),
    [carrier, carrier],
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let builder = @storage.prepare(
    @graph_type.union_output(checked),
    DeclaredNodes,
    union_fold_test_limits(),
  ).unwrap()
  let fold = prepare_union_fold(
    checked,
    0,
    Accumulated(left),
    Accumulated(right),
    builder,
    union_fold_test_limits(),
    100000,
  ).unwrap()
  let mut work = 0
  for _ in 0..<100000 {
    match advance_union_fold(fold, 1) {
      UnionFoldContinue(used) => work += used
      UnionFoldFailed(UnionEndpointConflict, used) => {
        work += used
        break
      }
      _ => abort("graft must fail at the typed shared endpoint boundary")
    }
  } nobreak {
    abort("graft conflict did not settle")
  }
  assert_true(work > 0)
  cleanup_union_fold(fold)
  cleanup_union_fold(fold)
  assert_true(@storage.available(left) && @storage.available(right))
  @storage.discard(left)
  @storage.discard(right)
}
