///|
// Distinct checked producer originals exercise the same Text-key JOIN and
// borrowed binding chain as installed multi-Source UPDATE computation. This
// qualifies the constructor, not provider authentication or public approval.
fn borrowed_text_join_fixture(
  count : Int,
) -> (
  @execution.GeneratedSequence,
  Array[@execution.ProducerRead],
  Array[@execution.CompletedOutput],
) raise {
  let check : @pipeline.Limits = {
    max_steps: 100,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }
  let key = "é😀".repeat(64)
  let schema = "{\"id\":{\"type\":\"string\",\"nullable\":false},\"name\":{\"type\":\"string\",\"nullable\":false}}"
  let rows = "[{\"id\":" +
    Json::string(key).stringify() +
    ",\"name\":\"selected\"},{\"id\":\"control\",\"name\":\"unchanged\"}]"
  let owners = []
  let outputs = []
  let inputs = []
  for index in 0..<count {
    let owner = chain_lifetime_bind(
      @pipeline.check(
        chain_lifetime_cursor(
          "[{\"values\":{\"schema\":" +
          schema +
          ",\"rows\":" +
          rows +
          "},\"as\":\"seed\"}]",
        ),
        [],
        None,
        None,
        check,
      ).unwrap(),
    )
    let output = @execution.completed_output(
      @execution.execute_generated_sequence(
        chain_lifetime_generated(owner),
        [],
        chain_lifetime_limits(),
      ).unwrap(),
      @pipeline.Step(0),
    ).unwrap()
    let producer = @pipeline.produced_input(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    ).unwrap()
    inputs.push(("s" + index.to_string(), @pipeline.ProducedInput(producer)))
    owners.push(owner)
    outputs.push(output)
  }
  assert_false(physical_equal(owners[0], owners[1]))
  assert_false(physical_equal(outputs[0], outputs[1]))
  let steps = []
  let mut from = "s0"
  for index in 1..<count {
    let name = "joined" + index.to_string()
    steps.push(
      "{\"from\":\"" +
      from +
      "\",\"join\":{\"with\":\"s" +
      index.to_string() +
      "\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\",\"name\":\"left.name\"}},\"as\":\"" +
      name +
      "\"}",
    )
    from = name
  }
  steps.push(
    "{\"from\":\"" +
    from +
    "\",\"derive\":{\"next_name\":{\"literal\":\"updated\"}},\"as\":\"updated\"}",
  )
  steps.push(
    "{\"from\":\"updated\",\"select\":[\"id\",\"name\",\"next_name\"]}",
  )
  let receiver = chain_lifetime_bind(
    @pipeline.check_with_evidence(
      chain_lifetime_cursor("[" + steps.join(",") + "]"),
      inputs,
      None,
      None,
      check,
    ).unwrap(),
  )
  let reads = Array::makei(count, index => {
    @execution.prepare_producer_read(
      receiver,
      @execution.bind_completed_input(
        receiver,
        index,
        owners[index],
        outputs[index],
      ).unwrap(),
      1000,
      10000,
    ).unwrap()
  })
  (chain_lifetime_generated(receiver, fragment_work=20000000L), reads, outputs)
}

///|
test "required Text-key multi-input Join borrows originals under bounded startup and preserves work refusal" {
  for count in [2, 3] {
    let (sequence, reads, parents) = borrowed_text_join_fixture(count)
    let values : @execution.ValueLimits = {
      max_nodes: 20000,
      max_text_bytes: 20000000,
      max_depth: 100,
      max_work: 20000000,
    }
    let limits = {
      ..chain_lifetime_limits(),
      rows: {
        ..chain_lifetime_limits().rows,
        input_values: values,
        output_values: values,
      },
      max_work: 20000000,
    }
    let registry = @connector.prepare_capability_registry(
      [
        {
          name: "local",
          acquisition: false,
          fixed_compute: true,
          effect: false,
        },
      ],
      1,
      100,
    ).unwrap()
    let installed = prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      [sequence],
      limits,
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(installed, 0, sequence).unwrap()
    let startup = local_module_metered_output_start_capacity(
      installed, 0, sequence,
    ).unwrap()
    assert_true(startup.retained_bytes < full.retained_bytes)
    assert_true(startup.execution_bytes < full.execution_bytes)
    assert_true(startup.retained_bytes + startup.execution_bytes < 536870912L)
    for small in [false, true] {
      let selected = if small { { ..limits, max_work: 1, } } else { limits }
      let requests = []
      let funded = @execution.bind_generated_workspace_growth(
        sequence,
        selected,
        536870912L,
        bytes => {
          requests.push(bytes)
          Ok(())
        },
        meter_retained_outputs=true,
      ).unwrap()
      let (active, state) = bounded_relation_chain_execution_state(
        funded,
        reads.map(managed_provider_relation_input),
        selected,
        chain_lifetime_measurement(),
        10000,
        None,
        [],
      ).unwrap()
      let mut output = None
      let mut failed = false
      for _ in 0..<100000 {
        if output is Some(_) || failed {
          break
        }
        match advance_managed_provider(active, 1).unwrap() {
          Continue(..) | Waiting(..) => ()
          Complete(value, ..) => output = Some(value)
          Failed(issue, ..) => {
            assert_true(small)
            assert_true(issue is @connector.Execution(@execution.InputLimit))
            failed = true
          }
          _ => fail("unexpected original Text JOIN outcome")
        }
      }
      if small {
        assert_true(failed)
        assert_true(output is None)
      } else {
        let output = output.unwrap()
        assert_eq(@execution.completed_row_count(output), 2)
        for
          row, (id, name) in [
            ("é😀".repeat(64), "selected"),
            ("control", "unchanged"),
          ] {
          for field, expected in [id, name, "updated"] {
            assert_true(
              @execution.completed_cell(output, row, field)
              is Some(@execution.Text(actual)) &&
              actual == expected,
            )
          }
        }
        assert_false(requests.is_empty())
        assert_true(requests.all(bytes => bytes >= 0L && bytes < 536870912L))
      }
      let mut clean = false
      for _ in 0..<10000 {
        if cleanup_managed_provider(active).unwrap() {
          clean = true
          break
        }
      }
      assert_true(clean)
      assert_true(state.current is None)
      assert_true(state.children.is_empty())
      assert_true(state.completed.is_empty())
      assert_true(reads.all(@execution.producer_read_available))
      assert_true(parents.all(@execution.completed_output_available))
    }
    @connector.close_capability_registry(registry)
  }
}
