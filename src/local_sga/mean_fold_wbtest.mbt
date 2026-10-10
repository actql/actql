///|
fn mean_fold_test_checked(
  carrier : @carrier.Carrier,
  weights? : String = "[1,2,0]",
  support? : String = "1",
  missing? : String = "exclude",
  nulls? : String = "exclude",
) -> @graph_type.CheckedMean {
  let fields = "{\"p\":{\"mean\":{\"missing\":\"" +
    missing +
    "\",\"nulls\":\"" +
    nulls +
    "\"}},\"q\":\"exact_equal\"}"
  @graph_type.check_mean(
    union_fold_test_cursor(
      "{\"with\":[\"a\",\"b\",\"a\"],\"weights\":" +
      weights +
      ",\"support\":{\"nodes\":" +
      support +
      ",\"edges\":" +
      support +
      "},\"properties\":{\"nodes\":" +
      fields +
      ",\"edges\":" +
      fields +
      "}}",
    ),
    [carrier, carrier, carrier],
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn mean_fold_test_single(
  carrier : @carrier.Carrier,
  property : String,
) -> @storage.Storage {
  let builder = @storage.prepare(
    carrier,
    DeclaredNodes,
    union_fold_test_limits(),
  ).unwrap()
  let key = union_property_test_value(
    @contract.primitive(NumberType, nullable=false),
    "1",
  )
  let number = @contract.primitive(NumberType, nullable=true)
  @storage.append_node(builder, 0, [key], [
    union_property_test_value(number, property),
    union_property_test_value(number, "7"),
  ]).unwrap()
  @storage.finish(builder).unwrap()
}

///|
test "Mean Graph property policies preserve whole entity absence versus present NULL" {
  let carrier = union_fold_test_carrier()
  let six = mean_fold_test_single(carrier, "6")
  let null = mean_fold_test_single(carrier, "null")
  let empty = @storage.finish(
    @storage.prepare(carrier, DeclaredNodes, union_fold_test_limits()).unwrap(),
  ).unwrap()
  for
    (missing, nulls, expected) in [
      ("exclude", "exclude", "6"),
      ("exclude", "zero", "2"),
      ("zero", "exclude", "1.5"),
      ("zero", "zero", "1"),
    ] {
    let checked = mean_fold_test_checked(
      carrier,
      weights="[1,2,3]",
      support="0.5",
      missing~,
      nulls~,
    )
    for quantum in [1, 7, 64] {
      let fold = mean_fold_test_prepare(checked, [six, null, empty])
      let (output, _) = mean_fold_test_finish(fold, quantum)
      assert_eq(@storage.node_count(output), 1)
      assert_eq(@storage.edge_count(output), 0)
      assert_eq(
        union_property_test_wire(@storage.node_property(output, 0, 0).unwrap()),
        expected,
      )
      assert_eq(
        union_property_test_wire(@storage.node_property(output, 0, 1).unwrap()),
        "7",
      )
      cleanup_mean_fold(fold)
      @storage.discard(output)
    }
  }
  // A zero denominator is an observed NULL, not a missing output field.
  let checked = mean_fold_test_checked(carrier, weights="[1,2,0]")
  let fold = mean_fold_test_prepare(checked, [null, null, six])
  let (output, _) = mean_fold_test_finish(fold, 1)
  assert_eq(
    union_property_test_wire(@storage.node_property(output, 0, 0).unwrap()),
    "null",
  )
  cleanup_mean_fold(fold)
  @storage.discard(output)
  for input in [six, null, empty] {
    assert_true(@storage.available(input))
    @storage.discard(input)
  }
}

///|
test "Mean Graph field alignment uses semantic names not declaration positions" {
  let first = union_fold_test_carrier()
  let second = union_fold_test_carrier(reordered=true)
  let input = union_fold_test_input(first)
  let peer = union_fold_test_input(second, reordered=true)
  let fields = "{\"p\":{\"mean\":{\"missing\":\"exclude\",\"nulls\":\"exclude\"}},\"Q\":\"exact_equal\"}"
  let checked = @graph_type.check_mean(
    union_fold_test_cursor(
      "{\"with\":[\"a\",\"b\",\"a\"],\"weights\":[1,2,0],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":" +
      fields +
      ",\"edges\":" +
      fields +
      "}}",
    ),
    [first, second, first],
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let fold = mean_fold_test_prepare(checked, [input, peer, input])
  let (output, _) = mean_fold_test_finish(fold, 1)
  for node in 0..<2 {
    assert_eq(
      union_property_test_wire(@storage.node_property(output, node, 0).unwrap()),
      "2",
    )
    assert_eq(
      union_property_test_wire(@storage.node_property(output, node, 1).unwrap()),
      "7",
    )
  }
  cleanup_mean_fold(fold)
  @storage.discard(output)
  @storage.discard(input)
  @storage.discard(peer)
}

///|
test "Mean cancellation retains input and private output until common stop acknowledgement and cleanup retry" {
  let carrier = union_fold_test_carrier()
  let input = union_fold_test_input(carrier)
  let checked = mean_fold_test_checked(carrier)
  // Private cursor lifecycle test, not a claim of public Host dispatch. The
  // production connection must supply the same shared bounded session owner.
  for boundary in [SupplyMeanProperty, AppendMeanRecord, FinishMeanFold] {
    let fold = mean_fold_test_prepare(checked, [input, input, input])
    let control = @bounded.control()
    let advances = Ref(0)
    let cleanups = Ref(0)
    let (session, first) = @bounded.start(
      control,
      fold,
      (state, quantum, _reader) => {
        advances.val += 1
        match advance_mean_fold(state, quantum) {
          MeanFoldContinue(work) => @bounded.Continue(0, work)
          MeanFoldComplete(output, work) => @bounded.Complete(output, 1, work)
          MeanFoldFailed(issue, work) => @bounded.Failed(issue, 0, work)
        }
      },
      state => {
        cleanups.val += 1
        if cleanups.val == 1 {
          false
        } else {
          cleanup_mean_fold(state)
          true
        }
      },
      output => {
        @storage.discard(output)
        true
      },
    )
    let mut token = first
    for _ in 0..<100000 {
      match @bounded.advance(session, token, 1).unwrap() {
        @bounded.ContinueWith(next, ..) => token = next
        _ => abort("Mean completed before selected cancellation boundary")
      }
      if fold.phase == boundary {
        break
      }
    } nobreak {
      abort("Mean cancellation boundary was not reached")
    }
    let before = advances.val
    let nodes = @storage.builder_node_count(fold.builder)
    let bytes = @storage.builder_retained_value_bytes(fold.builder)
    assert_true(@bounded.request_cancel(control))
    assert_true(@storage.available(input))
    assert_eq(@storage.builder_node_count(fold.builder), nodes)
    assert_eq(@storage.builder_retained_value_bytes(fold.builder), bytes)
    assert_true(@bounded.cleanup(session) is Err(@bounded.NotStopped))
    assert_true(
      @bounded.advance(session, token, 1).unwrap()
      is @bounded.StoppedWith(@bounded.Cancelled, ..),
    )
    assert_eq(advances.val, before)
    assert_eq(@bounded.cleanup(session).unwrap(), false)
    assert_true(@bounded.cleanup_pending(session))
    assert_eq(@storage.builder_retained_value_bytes(fold.builder), bytes)
    assert_eq(@bounded.cleanup(session).unwrap(), true)
    assert_eq(@storage.builder_retained_value_bytes(fold.builder), 0)
    assert_eq(@storage.builder_node_count(fold.builder), 0)
    assert_true(@storage.available(input))
    assert_eq(advances.val, before)
    // The common owner reports whether this call made a new transition,
    // not whether an already completed cleanup remains complete.
    assert_eq(@bounded.cleanup(session).unwrap(), false)
    assert_eq(@bounded.cleanup_pending(session), false)
    assert_eq(cleanups.val, 2)
  }
  @storage.discard(input)
}

///|
fn mean_fold_test_prepare(
  checked : @graph_type.CheckedMean,
  inputs : Array[@storage.Storage],
  work? : Int = 1000000,
  exact_work? : Int = 100000,
) -> MeanFold {
  prepare_mean_fold(
    checked,
    inputs.map(input => Accumulated(input)),
    @storage.prepare(
      @graph_type.mean_output(checked),
      DeclaredNodes,
      union_fold_test_limits(),
    ).unwrap(),
    union_fold_test_limits(),
    work,
    { max_bits: 8192, remaining: exact_work, },
  ).unwrap()
}

///|
fn mean_fold_test_finish(
  value : MeanFold,
  quantum : Int,
) -> (@storage.Storage, Int) raise {
  let mut work = 0
  for _ in 0..<1000000 {
    match advance_mean_fold(value, quantum) {
      MeanFoldContinue(used) => {
        assert_true(used > 0 && used <= quantum)
        work += used
      }
      MeanFoldComplete(output, used) => {
        assert_true(used > 0 && used <= quantum)
        return (output, work + used)
      }
      MeanFoldFailed(issue, _) =>
        abort("unexpected Mean fold failure " + @debug.to_string(issue))
    }
  }
  abort("finite Mean fold did not finish")
}

///|
test "Mean fold preserves repeated samples canonical identities and independent parallel edges across quantums" {
  let carrier = union_fold_test_carrier()
  let input = union_fold_test_input(carrier)
  let checked = mean_fold_test_checked(carrier)
  let mut previous_work = None
  for quantum in [1, 7, 64] {
    let fold = mean_fold_test_prepare(checked, [input, input, input])
    let (output, work) = mean_fold_test_finish(fold, quantum)
    if previous_work is Some(previous) {
      assert_eq(work, previous)
    } else {
      previous_work = Some(work)
    }
    assert_eq(@storage.node_count(output), 2)
    assert_eq(@storage.edge_count(output), 2)
    for node in 0..<2 {
      assert_eq(
        union_property_test_wire(
          graph_read_node_key_component(Accumulated(output), node, 0).unwrap(),
        ),
        (node + 1).to_string(),
      )
      assert_eq(
        union_property_test_wire(
          @storage.node_property(output, node, 0).unwrap(),
        ),
        "2",
      )
      assert_eq(
        union_property_test_wire(
          @storage.node_property(output, node, 1).unwrap(),
        ),
        "7",
      )
    }
    for edge in 0..<2 {
      assert_eq(
        union_property_test_wire(
          graph_read_edge_key_component(Accumulated(output), edge, 0).unwrap(),
        ),
        (edge + 10).to_string(),
      )
      assert_eq(
        union_property_test_wire(
          @storage.edge_property(output, edge, 0).unwrap(),
        ),
        "2",
      )
      assert_eq(
        union_property_test_wire(
          @storage.edge_property(output, edge, 1).unwrap(),
        ),
        "7",
      )
      assert_eq(@storage.edge_endpoints(output, edge), Some((0, 1)))
    }
    cleanup_mean_fold(fold)
    cleanup_mean_fold(fold)
    assert_true(@storage.available(output) && @storage.available(input))
    @storage.discard(output)
  }
  @storage.discard(input)
}

///|
test "Mean support uses exact threshold while zero weight samples do not contribute" {
  let carrier = union_fold_test_carrier()
  let input = union_fold_test_input(carrier)
  let empty = @storage.finish(
    @storage.prepare(carrier, DeclaredNodes, union_fold_test_limits()).unwrap(),
  ).unwrap()
  // Entity support is exactly 1/4. At the next representable binary64
  // threshold it must fail; rounded division is not the membership rule.
  for (threshold, expected) in [("0.25", 2), ("0.25000000000000006", 0)] {
    let checked = mean_fold_test_checked(
      carrier,
      weights="[1,3,0]",
      support=threshold,
    )
    let fold = mean_fold_test_prepare(checked, [input, empty, input])
    let (output, _) = mean_fold_test_finish(fold, 1)
    assert_eq(@storage.node_count(output), expected)
    assert_eq(@storage.edge_count(output), expected)
    cleanup_mean_fold(fold)
    @storage.discard(output)
  }
  assert_true(@storage.available(input) && @storage.available(empty))
  @storage.discard(input)
  @storage.discard(empty)
}

///|
test "Mean fold rejects conflicting endpoints and keeps private output until cleanup" {
  let carrier = union_fold_test_carrier()
  let input = union_fold_test_input(carrier)
  let conflict = union_fold_test_input(carrier, conflict=true)
  let fold = mean_fold_test_prepare(mean_fold_test_checked(carrier), [
    input, conflict, input,
  ])
  for _ in 0..<100000 {
    match advance_mean_fold(fold, 1) {
      MeanFoldContinue(_) => ()
      MeanFoldFailed(MeanEndpointConflict, _) => break
      _ => abort("endpoint mismatch must fail before Graph completion")
    }
  } nobreak {
    abort("endpoint fixture failed to stop")
  }
  assert_eq(@storage.builder_node_count(fold.builder), 2)
  assert_eq(@storage.builder_edge_count(fold.builder), 0)
  cleanup_mean_fold(fold)
  cleanup_mean_fold(fold)
  assert_eq(@storage.builder_node_count(fold.builder), 0)
  assert_true(@storage.available(input) && @storage.available(conflict))
  @storage.discard(input)
  @storage.discard(conflict)
}

///|
test "empty Mean fold has independently counted cumulative control and exact primitive boundaries" {
  let carrier = union_fold_test_carrier()
  let empty = @storage.finish(
    @storage.prepare(carrier, DeclaredNodes, union_fold_test_limits()).unwrap(),
  ).unwrap()
  let checked = mean_fold_test_checked(carrier)
  // Three sample admissions + admission transition; four node scan actions;
  // four reset actions; four edge scan actions; private Store seal.
  let control = 3 + 1 + (3 + 1) + (3 + 1) + (3 + 1) + 1
  assert_eq(control, 17)
  // All three sample weights, including zero, are admitted exactly once.
  let exact = 3
  for quantum in [1, 7, 64] {
    for
      (work, arithmetic, expected) in [
        (control, exact, None),
        (control - 1, exact, Some(MeanFoldWorkLimit)),
        (control, exact - 1, Some(MeanExactWorkLimit)),
      ] {
      let fold = mean_fold_test_prepare(
        checked,
        [empty, empty, empty],
        work~,
        exact_work=arithmetic,
      )
      let mut used = 0
      for _ in 0..<(control + 1) {
        match advance_mean_fold(fold, quantum) {
          MeanFoldContinue(work) => used += work
          MeanFoldComplete(output, work) => {
            used += work
            assert_eq(expected, None)
            assert_eq(used, control)
            assert_eq(@storage.node_count(output), 0)
            assert_eq(@storage.edge_count(output), 0)
            @storage.discard(output)
            break
          }
          MeanFoldFailed(issue, _) => {
            assert_eq(Some(issue), expected)
            break
          }
        }
      } nobreak {
        abort("empty Mean failed to terminate")
      }
      cleanup_mean_fold(fold)
      assert_true(@storage.available(empty))
    }
  }
  @storage.discard(empty)
}

///|
test "Mean exact arithmetic allowance is shared across identities and properties" {
  let carrier = union_fold_test_carrier()
  let input = union_fold_test_input(carrier)
  let checked = mean_fold_test_checked(carrier)
  // Three admitted weights, two positive support additions and one support
  // comparison for the first node, two products and one final rounding for p.
  // Nine actions exhaust the allowance before the second node's support.
  let fold = mean_fold_test_prepare(
    checked,
    [input, input, input],
    exact_work=9,
  )
  for _ in 0..<100000 {
    match advance_mean_fold(fold, 1) {
      MeanFoldContinue(_) => ()
      MeanFoldFailed(MeanExactWorkLimit, _) => break
      _ => abort("exact work must not reset at the next identity")
    }
  } nobreak {
    abort("exact allowance fixture failed to terminate")
  }
  assert_eq(@storage.builder_node_count(fold.builder), 1)
  assert_eq(fold.arithmetic.remaining, 0)
  cleanup_mean_fold(fold)
  assert_eq(@storage.builder_node_count(fold.builder), 0)
  assert_true(@storage.available(input))
  @storage.discard(input)
}
