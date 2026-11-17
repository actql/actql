///|
fn scalar_count_text_chain_fixture(
  recursive? : Bool = false,
) -> (
  @execution.GeneratedSequence,
  @execution.ProducerRead,
  @execution.CompletedOutput,
) raise {
  let first =
    #|[{"from":"source","derive":{"x":{"case":{"when":[{"when":{"eq":[{"field":"id"},{"literal":2}]},"then":{"literal":"z"}}],"else":{"literal":"a"}}},"y":{"case":{"when":[{"when":{"eq":[{"field":"id"},{"literal":1}]},"then":{"cast":{"value":{"literal":null},"target":{"type":"string"}}}}],"else":{"literal":"a"}}}}},{"select":["id","x","y"]},{"derive":{"value":{"concat_strict":[{"field":"x"},{"field":"y"}]}
  let rest =
    #|}},{"group":{"by":["value"],"aggregates":{"n":{"fn":"count"}}}},{"select":["value","n"]},{"sort":[{"field":"value","dir":"asc","nulls":"last"}]}]
  chain_lifetime_fixture(
    first +
    (if recursive { ",\"extra\":{\"array\":[{\"field\":\"id\"}]}" } else { "" }) +
    rest,
  )
}

///|
fn scalar_count_text_chain_limits() -> @execution.SequenceExecutionLimits {
  let values : @execution.ValueLimits = {
    max_nodes: 2600,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  {
    ..chain_lifetime_limits(),
    rows: {
      ..chain_lifetime_limits().rows,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
  }
}

///|
fn scalar_count_text_chain_measurement() -> @execution.FixedInputGuardMeasureLimits {
  { max_work: 20000000, max_bytes: 120075433, max_nodes: 5200, max_depth: 100, }
}

///|
test "constructed Text followed by scalar COUNT retains full DATA and its genuine bounded chain recipe" {
  let (sequence, _, _) = scalar_count_text_chain_fixture()
  assert_eq(@execution.generated_sequence_step_count(sequence), 6)
  guard @execution.generated_sequence_step_at(sequence, 3)
    is Some(@lower.RowStep(group)) else {
    fail("original COUNT child missing")
  }
  assert_true(@execution.bounded_number_group_borrows_input(group))
  let limits = scalar_count_text_chain_limits()
  let measurement = scalar_count_text_chain_measurement()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let installed = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity(installed, 0).unwrap()
  let startup = local_module_metered_output_start_capacity(
    installed, 0, sequence,
  ).unwrap()
  assert_eq(startup.retained_bytes, full.retained_bytes)
  assert_true(startup.execution_bytes < full.execution_bytes)
  assert_true(startup.retained_bytes + startup.execution_bytes < 536870912L)
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    Err(@connector.InvalidLimits)
  })
  let foreign = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(foreign, 0, sequence) is None,
  )
  let (recursive, _, _) = scalar_count_text_chain_fixture(recursive=true)
  let fallback = prepare_local_compute_module(
    registry,
    registration,
    [recursive],
    limits,
    measurement,
    100000,
    1,
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(fallback, 0, recursive) is None,
  )
  @connector.close_capability_registry(registry)
}

///|
test "scalar COUNT chain funds constructed Text before transfer and keeps original input through refusal and cleanup" {
  for refuse in [false, true] {
    let (sequence, read, source) = scalar_count_text_chain_fixture()
    let limits = scalar_count_text_chain_limits()
    let requests = []
    let funded = @execution.bind_generated_workspace_growth(
      sequence,
      limits,
      536870912L,
      bytes => {
        requests.push(bytes)
        if refuse {
          Err(@execution.WorkspaceUnavailable)
        } else {
          Ok(())
        }
      },
      // Exercise the existing before-output hook independently. The selected
      // module recipe above keeps its complete standing retention instead.
      meter_retained_outputs=true,
    ).unwrap()
    let (active, state) = bounded_relation_chain_execution_state(
      funded,
      [managed_provider_relation_input(read)],
      limits,
      scalar_count_text_chain_measurement(),
      10000,
      None,
      [],
    ).unwrap()
    let mut output : @execution.CompletedOutput? = None
    let mut failed = false
    for _ in 0..<100000 {
      match advance_managed_provider(active, 1).unwrap() {
        Continue(..) | Waiting(..) => ()
        Complete(value, ..) => {
          output = Some(value)
          break
        }
        Failed(_, ..) => {
          failed = true
          break
        }
        _ => fail("unexpected original COUNT chain outcome")
      }
    }
    if refuse {
      assert_true(failed && output is None)
    } else {
      let completed = output.unwrap()
      assert_false(failed)
      assert_eq(@execution.completed_row_count(completed), 2)
      for
        row, expected in [
          "{\"n\":2,\"value\":\"za\"}", "{\"n\":1,\"value\":null}",
        ] {
        assert_eq(
          @json.parse(
            @execution.completed_output_row_wire(completed, row, 1000, 100, 10).unwrap(),
          ),
          @json.parse(expected),
        )
      }
    }
    assert_false(requests.is_empty())
    assert_true(requests.all(bytes => bytes >= 0L && bytes <= 536870912L))
    let mut cleaned = false
    for _ in 0..<10000 {
      if cleanup_managed_provider(active).unwrap() {
        cleaned = true
        break
      }
    }
    assert_true(cleaned)
    assert_true(
      state.current is None &&
      state.children.is_empty() &&
      state.completed.is_empty(),
    )
    assert_true(@execution.completed_output_available(source))
  }
}
