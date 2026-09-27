///|
fn group_step_cell(value : Value) -> String {
  match value {
    Null => "null"
    Boolean(value) => "b" + value.to_string()
    Number(value) => "n" + value.to_string()
    Text(value) => "t" + value
    Captured(@admitted.Decimal(decimal)) =>
      "d" + decimal.coefficient + "/" + decimal.scale.to_string()
    Captured(_) => "captured"
  }
}

///|
test "bounded group pays at most one unit per advance and matches the sequence" {
  let program =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"k":{"type":"number","nullable":true},"n":{"type":"number","nullable":true},"flag":{"type":"boolean","nullable":true},"amount":{"type":"decimal","precision":4,"scale":2,"nullable":true},"label":{"type":"string","nullable":true}},"rows":[{"id":1,"k":2,"n":4,"flag":true,"amount":"1.25","label":{"literal":"béta"}},{"id":2,"k":null,"n":2,"flag":true,"amount":"-0.25","label":{"literal":"a"}},{"id":3,"k":1,"n":null,"flag":null,"amount":null,"label":null},{"id":4,"k":2,"n":8,"flag":false,"amount":"2.00","label":{"literal":"alpha"}},{"id":5,"k":null,"n":6,"flag":false,"amount":"0.50","label":{"literal":"c"}},{"id":6,"k":2,"n":8,"flag":true,"amount":"0.75","label":{"literal":"béta"}}]},"as":"seed"},{"group":{"by":["k"],"aggregates":{"labels":{"fn":"count","field":"label","distinct":true},"hits":{"fn":"count_if","field":"flag"},"highest":{"fn":"max","field":"label"},"lowest":{"fn":"min","field":"label"},"total":{"fn":"sum","field":"amount"},"first":{"fn":"first","field":"label","order_by":[{"id":"asc"}]},"median":{"fn":"percentile_disc","field":"n","fraction":0.5},"spread":{"fn":"var_pop","field":"n"},"deviation":{"fn":"stddev_pop","field":"n"}}}}]
  let owner = bound_pipeline(program)
  let sequence = prepared_sequence(owner)
  let group = @lower.kernel_group(row_kernel(owner, 1)).unwrap()
  // The ordinary sequence result.
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let expected = test_row_output(completed_output(completed, Step(1)).unwrap())
  // The group input rows.
  let seed_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let seed_completed = execute_generated_sequence(seed_generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let seed = test_row_output(completed_output(seed_completed, Step(0)).unwrap())
  let rows : Array[Array[String]] = []
  let control : ControlBudget = { remaining: 100000, max_frames: 100, }
  let state = start_bounded_group(
    group,
    seed,
    1000,
    control,
    row_output(),
    { limit: 100000, live: 0, peak: 0, },
    None,
    (row, _representative, _names, _sources) => {
      rows.push(row.map(group_step_cell))
      Ok(())
    },
    [],
    {
      max_nodes: 1000,
      max_text_bytes: 100000,
      max_depth: 16,
      max_work: 100000,
    },
    None,
    step=1,
  )
  let mut advances = 0
  let mut names = None
  while names is None {
    advances += 1
    let before = control.remaining
    match advance_bounded_group(state) {
      Ok(None) => ()
      Ok(Some(value)) => names = Some(value)
      Err(_) => fail("bounded group failed")
    }
    assert_true(before - control.remaining <= 1)
  }
  assert_eq(names.unwrap(), expected.names)
  assert_eq(rows, expected.rows.map(row => row.map(group_step_cell)))
  assert_eq(rows.length(), 3)
  // Six input rows take far more than one advance per row.
  assert_true(advances > 200)
}
