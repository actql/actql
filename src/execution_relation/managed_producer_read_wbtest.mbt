///|
fn managed_read_fixture(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
  index_cells? : Int,
) -> ManagedCompletedOutput[Int] raise {
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let values = prepare_managed_output_values(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(values, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 7, 12L, fn() { live.val }))).unwrap()
  if index_cells is Some(cap) {
    enable_managed_row_measurements(values, cap).unwrap()
  }
  for row in 0..<2 {
    let cells = output_fixture_row(owner, row)
    append_managed_output_values(values, cells.length(), column => {
      cells.get(column)
    }).unwrap()
  }
  let material = retain_managed_output(
    retention,
    finish_managed_output_values(values).unwrap(),
  ).unwrap()
  let port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(material),
  ).unwrap()
  complete_managed_output(port, ()).unwrap()
}

///|
test "managed completed values bind checked projections without legacy identities or cell reads" {
  let owner = capture_fixture()
  let live = Ref(true)
  let output = managed_read_fixture(owner, live)
  for
    (fields, steps, expected) in [
      ("[\"n\"]", "[{\"select\":[\"n\"]}]", [0]),
      ("[{\"renamed\":\"s\"}]", "[{\"select\":[\"renamed\"]}]", [1]),
      ("[{\"a\":\"n\"},{\"b\":\"n\"}]", "[{\"select\":[\"a\",\"b\"]}]", [0, 0]),
      ("[{\"a\":\"s\"},{\"b\":\"n\"}]", "[{\"select\":[\"a\",\"b\"]}]", [1, 0]),
    ] {
    let receiver = projected_consumer(owner, fields, steps, target=Step(1))
    let input = prepare_managed_producer_read(
      receiver, 0, owner, output, 1000, 10000,
    ).unwrap()
    let common = managed_relation_input_binding(input)
    assert_true(managed_input_binding_matches_input(common, receiver, 0))
    assert_eq(
      managed_input_binding_profile_cid(common),
      managed_execution_profile_cid(managed_test_profile()),
    )
    assert_true(
      managed_input_binding_matches_relation_reference(
        common,
        managed_completed_reference(output),
      ),
    )
    assert_true(physical_equal(managed_producer_read_receiver(input), receiver))
    assert_eq(managed_producer_read_input_index(input), 0)
    assert_eq(managed_producer_read_row_count(input), 2)
    assert_eq(
      @schema.field_count(managed_producer_read_schema(input)),
      expected.length(),
    )
    for column, source in expected {
      assert_eq(managed_producer_read_column(input, column), Some(source))
    }
    assert_eq(managed_producer_read_column(input, expected.length()), None)
    assert_true(managed_producer_read_same_binding(input, input))
    let another = prepare_managed_producer_read(
      receiver, 0, owner, output, 1000, 10000,
    ).unwrap()
    assert_false(managed_producer_read_same_binding(input, another))
    let reference = managed_completed_reference(output)
    assert_true(managed_producer_read_matches_reference(input, reference))
    assert_true(managed_producer_read_matches_reference(another, reference))
    assert_true(
      physical_equal(
        managed_producer_read_material(input).unwrap(),
        output.material,
      ),
    )
    live.val = false
    assert_false(managed_input_binding_available(common))
    assert_false(managed_producer_read_available(input))
    assert_false(managed_producer_read_matches_reference(input, reference))
    assert_true(managed_producer_read_material(input) is None)
    assert_true(
      prepare_managed_producer_read(receiver, 0, owner, output, 1000, 10000)
      is Err(Binding(ProducerUnavailable)),
    )
    live.val = true
  }
}

///|
test "managed read rejects foreign producer invocation target and bounded metadata exhaustion" {
  let owner = capture_fixture()
  let output = managed_read_fixture(owner, Ref(true))
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  assert_true(
    prepare_managed_producer_read(receiver, 1, owner, output, 1000, 10000)
    is Err(Binding(NotProducedInput)),
  )
  assert_true(
    prepare_managed_producer_read(
      receiver,
      0,
      capture_fixture(),
      output,
      1000,
      10000,
    )
    is Err(Binding(ProducerOwnerMismatch)),
  )
  let other_binding = @lower.bind_parameters(
    @lower.bound_preparation(owner),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    prepare_managed_producer_read(
      receiver, 0, other_binding, output, 1000, 10000,
    )
    is Err(Binding(ProducerBindingMismatch)),
  )
  // A different selected port is not the checked input, even under one owner.
  assert_true(
    prepare_managed_producer_read(
      receiver,
      0,
      owner,
      { ..output, target: Step(0), },
      1000,
      10000,
    )
    is Err(Binding(ProducerTargetMismatch)),
  )
  assert_true(
    prepare_managed_producer_read(receiver, 0, owner, output, -1, 10000)
    is Err(View(InvalidLimits)),
  )
  assert_true(
    prepare_managed_producer_read(receiver, 0, owner, output, 0, 10000)
    is Err(View(Limit)),
  )
  assert_true(
    prepare_managed_producer_read(receiver, 0, owner, output, 1000, 0)
    is Err(View(Limit)),
  )
}

///|
test "managed input completion preserves exact use sites and independent downstream lifetime" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let another = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let material = managed_test_material(receiver, Step(0), Ref(true))
  let profile = managed_test_profile()
  assert_true(
    prepare_managed_completion_port(
      profile,
      preparation,
      Step(0),
      1000,
      10000,
      (_ : Unit) => Some(material),
      managed_inputs=[],
    )
    is Err(ForeignInputs),
  )
  assert_true(
    prepare_managed_completion_port(
      profile,
      preparation,
      Step(0),
      1000,
      10000,
      (_ : Unit) => Some(material),
      inputs=[],
      managed_inputs=[input],
    )
    is Err(ForeignInputs),
  )
  for revoke in [false, true] {
    live.val = true
    let supplied = [input]
    let port = prepare_managed_completion_port(
      profile,
      preparation,
      Step(0),
      1000,
      10000,
      (_ : Unit) => {
        if revoke {
          live.val = false
        }
        Some(material)
      },
      managed_inputs=supplied,
    ).unwrap()
    // Preparation owns its snapshot, not the caller's mutable array.
    supplied[0] = another
    let result = complete_managed_output(port, ())
    if revoke {
      assert_true(result is Err(ForeignInputs))
    } else {
      let completed = result.unwrap()
      assert_true(
        managed_completed_output_matches_managed_inputs(completed, [input]),
      )
      assert_false(
        managed_completed_output_matches_managed_inputs(completed, [another]),
      )
      assert_false(managed_completed_output_matches_inputs(completed, []))
      live.val = false
      assert_true(managed_completed_output_available(completed))
      assert_true(
        managed_completed_output_matches_managed_inputs(completed, [input]),
      )
    }
    assert_true(complete_managed_output(port, ()) is Err(Unverified))
  }
}
