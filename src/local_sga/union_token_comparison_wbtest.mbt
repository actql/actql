///|
fn union_token_carrier() -> @carrier.Carrier {
  let properties = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let key = @contract.primitive(StringType, nullable=false)
  let node = @carrier.graph_node_definition(
    "N",
    [key],
    properties,
    ["Entity"],
    key_columns=["node_key"],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.graph_edge_definition(
    @carrier.graph_node_definition(
      "E",
      [key],
      properties,
      ["Connection"],
      key_columns=["edge_key"],
      max_fields=10,
      max_name_bytes=100,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  @carrier.graph(
    "sha256:" + "0".repeat(64),
    [node],
    [edge],
    max_definitions=10,
    max_contract_work=1000,
  ).unwrap()
}

///|
fn union_token_input(
  carrier : @carrier.Carrier,
  conflict? : Bool = false,
) -> @storage.Storage {
  let builder = @storage.prepare(
    carrier,
    DeclaredNodes,
    union_fold_test_limits(),
  ).unwrap()
  let contract = @contract.primitive(StringType, nullable=false)
  let key = (suffix : String) => {
    union_property_test_value(contract, "\"" + "x".repeat(512) + suffix + "\"")
  }
  // Declaration order opposes UTF-16 order, including its surrogate boundary.
  @storage.append_node(builder, 0, [key("\ue000")], []).unwrap()
  @storage.append_node(builder, 0, [key("𐀀")], []).unwrap()
  @storage.append_edge(
    builder,
    0,
    [key("edge")],
    [key("𐀀")],
    [key(if conflict { "𐀀" } else { "\ue000" })],
    [],
  ).unwrap()
  @storage.finish(builder).unwrap()
}

///|
fn union_token_fold(
  carrier : @carrier.Carrier,
  left : @storage.Storage,
  right : @storage.Storage,
) -> UnionFoldPreparation {
  let checked = @graph_type.check_union(
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
    @graph_type.union_fold_output(checked, 0).unwrap(),
    DeclaredNodes,
    union_fold_test_limits(),
  ).unwrap()
  prepare_union_fold(
    checked,
    0,
    Accumulated(left),
    Accumulated(right),
    builder,
    union_fold_test_limits(),
    100000,
  ).unwrap()
}

///|
fn union_token_reach_phase(
  active : UnionFoldPreparation,
  phase : UnionFoldPhase,
) -> Unit raise {
  for _ in 0..<100000 {
    if active.phase == phase {
      assert_true(active.comparison is Some(_))
      return
    }
    assert_true(advance_union_fold(active, 1) is UnionFoldContinue(1))
  }
  abort("token comparison phase was not reached")
}

///|
test "union canonical token comparisons preserve order logical charges and quantum invariant work" {
  let carrier = union_token_carrier()
  let left = union_token_input(carrier)
  let right = union_token_input(carrier)
  let mut expected = None
  for quantum in [1, 7, 256] {
    let active = union_token_fold(carrier, left, right)
    let (output, work) = union_fold_test_finish(active, quantum)
    let charges = (
      work,
      @storage.construction_work(output),
      @storage.measured_input_value_bytes(output),
      @storage.retained_value_bytes(output),
      @storage.retained_workspace_slots(output),
    )
    if expected is Some(prior) {
      assert_eq(charges, prior)
    } else {
      expected = Some(charges)
    }
    assert_eq(@storage.node_count(output), 2)
    assert_eq(@storage.edge_count(output), 1)
    for (index, suffix) in [(0, "𐀀"), (1, "\ue000")] {
      assert_eq(
        union_property_test_wire(
          @storage.node_typed_key_at(output, index, 0).unwrap(),
        ),
        "\"" + "x".repeat(512) + suffix + "\"",
      )
    }
    assert_eq(@storage.edge_endpoints(output, 0), Some((0, 1)))
    cleanup_union_fold(active)
    assert_true(@storage.available(left) && @storage.available(right))
    @storage.discard(output)
  }
}

///|
test "union selected token comparison has independently counted exact and one short work" {
  let carrier = union_token_carrier()
  let left = union_token_input(carrier)
  let right = union_token_input(carrier)
  // Canonical identity token: [{"definition":"N","domain":"sha256:<64>",
  // "key":["<512 x><suffix>"],"key_types":[{"kind":"string"}]}].
  // The prefix through the opening key quote has 110 UTF-16 units. Compare
  // the 512 common x units, then D800 versus E000: 623 concrete steps.
  let comparison_work = 110 + 512 + 1
  for quantum in [1, 7, 256] {
    for ceiling in [comparison_work - 1, comparison_work] {
      let active = union_token_fold(carrier, left, right)
      union_token_reach_phase(active, CompareUnionSelected)
      active.remaining = ceiling
      let mut total = 0
      while total < ceiling {
        let budget = Int::min(quantum, ceiling - total)
        assert_true(
          advance_union_fold(active, budget) is UnionFoldContinue(used) &&
          used == budget,
        )
        total += budget
      }
      assert_eq(total, ceiling)
      if ceiling == comparison_work {
        assert_true(
          active.phase is ScanUnionElements && active.comparison is None,
        )
        assert_eq(active.left_index, 1)
      } else {
        assert_true(
          active.phase is CompareUnionSelected && active.comparison is Some(_),
        )
        assert_eq(active.left_index, 0)
      }
      assert_true(
        advance_union_fold(active, 1) is UnionFoldFailed(UnionFoldWorkLimit, 0),
      )
      assert_eq(@storage.builder_node_count(active.builder), 0)
      cleanup_union_fold(active)
      assert_true(active.candidate is None && active.comparison is None)
      assert_true(@storage.available(left) && @storage.available(right))
    }
  }
}

///|
test "union token cancellation drops borrowed comparison state without reclaiming inputs" {
  let carrier = union_token_carrier()
  let left = union_token_input(carrier)
  let right = union_token_input(carrier)
  for
    phase in [CompareUnionSelected, CompareUnionPrevious, CompareUnionEndpoints] {
    let active = union_token_fold(carrier, left, right)
    union_token_reach_phase(active, phase)
    assert_true(advance_union_fold(active, 7) is UnionFoldContinue(7))
    assert_true(active.phase == phase)
    assert_true(active.comparison is Some(_))
    cleanup_union_fold(active)
    cleanup_union_fold(active)
    assert_true(active.comparison is None && active.candidate is None)
    assert_true(active.previous is None && active.selected is None)
    assert_eq(@storage.builder_node_count(active.builder), 0)
    assert_eq(@storage.builder_edge_count(active.builder), 0)
    assert_true(
      advance_union_fold(active, 1) is UnionFoldFailed(InvalidUnionFold, 0),
    )
    assert_true(@storage.available(left) && @storage.available(right))
    assert_eq(@storage.node_count(left), 2)
    assert_eq(@storage.edge_count(right), 1)
  }
}

///|
test "union token comparison cannot complete after an input generation is lost" {
  let carrier = union_token_carrier()
  for
    phase in [CompareUnionSelected, CompareUnionPrevious, CompareUnionEndpoints] {
    let left = union_token_input(carrier)
    let right = union_token_input(carrier)
    let active = union_token_fold(carrier, left, right)
    union_token_reach_phase(active, phase)
    assert_true(advance_union_fold(active, 7) is UnionFoldContinue(7))
    @storage.discard(right)
    assert_true(
      advance_union_fold(active, 256)
      is UnionFoldFailed(UnionInputUnavailable, 0),
    )
    cleanup_union_fold(active)
    assert_true(active.comparison is None && @storage.available(left))
    assert_eq(@storage.node_count(left), 2)
    @storage.discard(left)
  }
}

///|
test "union endpoint canonical token conflict remains atomic after a long common prefix" {
  let carrier = union_token_carrier()
  let left = union_token_input(carrier)
  let right = union_token_input(carrier, conflict=true)
  let mut expected = None
  for quantum in [1, 7, 256] {
    let active = union_token_fold(carrier, left, right)
    let mut total = 0
    for _ in 0..<100000 {
      match advance_union_fold(active, quantum) {
        UnionFoldContinue(used) => total += used
        UnionFoldFailed(UnionEndpointConflict, used) => {
          total += used
          if expected is Some(prior) {
            assert_eq(total, prior)
          } else {
            expected = Some(total)
          }
          assert_eq(@storage.builder_node_count(active.builder), 2)
          assert_eq(@storage.builder_edge_count(active.builder), 0)
          break
        }
        _ => abort("endpoint token conflict was not rejected")
      }
    } nobreak {
      abort("endpoint token conflict did not terminate")
    }
    cleanup_union_fold(active)
    assert_true(active.comparison is None)
    assert_true(@storage.available(left) && @storage.available(right))
  }
}

///|
test "subtraction shares held canonical token comparisons without changing removal or input custody" {
  let carrier = union_token_carrier()
  let left = union_token_input(carrier)
  let right = union_token_input(carrier)
  let mut expected_work = None
  for quantum in [1, 7, 256] {
    let (active, _) = subtraction_fold_prepare(carrier, left, right, "")
    let (output, work) = union_fold_test_finish(active, quantum)
    assert_eq(@storage.node_count(output), 0)
    assert_eq(@storage.edge_count(output), 0)
    if expected_work is Some(prior) {
      assert_eq(work, prior)
    } else {
      expected_work = Some(work)
    }
    cleanup_union_fold(active)
    assert_true(@storage.available(left) && @storage.available(right))
    @storage.discard(output)
  }
  for
    phase in [CompareUnionSelected, CompareUnionPrevious, CompareUnionEndpoints] {
    let (active, _) = subtraction_fold_prepare(carrier, left, right, "")
    union_token_reach_phase(active, phase)
    assert_true(advance_union_fold(active, 7) is UnionFoldContinue(7))
    assert_true(active.phase == phase && active.comparison is Some(_))
    cleanup_union_fold(active)
    assert_true(active.comparison is None && active.candidate is None)
    assert_true(@storage.available(left) && @storage.available(right))
    assert_eq(@storage.node_count(left), 2)
    assert_eq(@storage.edge_count(right), 1)
  }
}
