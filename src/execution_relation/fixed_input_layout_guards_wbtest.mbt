///|
test "fixed input measurement preserves selected NULL values and failure frontiers across layouts" {
  let owner = row_owner("")
  let row = RowTable({
    owner,
    id: "rows",
    names: ["id"],
    rows: [[Number(2)], [Null], [Number(2)]],
  })
  // Physical slot 1 is not selected. Repeated slot 2 is a repeated logical
  // occurrence, not a permission to discount measurement or remove a row.
  let typed = NumberTable({
    owner,
    id: "columns",
    names: ["id"],
    count: 3,
    selection: Some([2, 0, 2]),
    columns: [
      {
        values: FixedArray::from_array([0.0, 99.0, 2.0]),
        valid: FixedArray::from_array([b'\x00', b'\x01', b'\x01']),
      },
    ],
  })
  for table in [row, typed] {
    for phase in [FixedInputGuardPhase::InputValues, Output] {
      let exact : FixedInputGuardBudget = {
        work: 6,
        bytes: 6,
        nodes: 3,
        depth: 0,
      }
      assert_true(measure_input_values(table, 4, phase, exact) is Ok(_))
      assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))

      let work : FixedInputGuardBudget = {
        work: 5,
        bytes: 6,
        nodes: 3,
        depth: 0,
      }
      assert_true(
        measure_input_values(table, 4, phase, work) is Err(MeasurementWork),
      )
      assert_eq((work.work, work.bytes, work.nodes), (0, 1, 1))

      let bytes : FixedInputGuardBudget = {
        work: 6,
        bytes: 5,
        nodes: 3,
        depth: 0,
      }
      assert_true(
        measure_input_values(table, 4, phase, bytes)
        is Err(Measurement(_, 2, 0, _)),
      )
      assert_eq((bytes.work, bytes.bytes, bytes.nodes), (0, 0, 1))

      let nodes : FixedInputGuardBudget = {
        work: 6,
        bytes: 6,
        nodes: 2,
        depth: 0,
      }
      assert_true(
        measure_input_values(table, 4, phase, nodes)
        is Err(Measurement(_, 2, 0, _)),
      )
      assert_eq((nodes.work, nodes.bytes, nodes.nodes), (0, 1, 0))

      let ceiling : FixedInputGuardBudget = {
        work: 6,
        bytes: 6,
        nodes: 3,
        depth: 0,
      }
      assert_true(
        measure_input_values(table, 3, phase, ceiling)
        is Err(ValueBytes(_, 1, 0)),
      )
      assert_eq((ceiling.work, ceiling.bytes, ceiling.nodes), (2, 1, 1))
    }
    // Input and output share a ledger rather than resetting at a representation
    // or phase boundary. Independently: 2 * (6 work, 6 bytes, 3 scalar nodes).
    let shared : FixedInputGuardBudget = {
      work: 12,
      bytes: 12,
      nodes: 6,
      depth: 0,
    }
    assert_true(measure_input_values(table, 4, InputValues, shared) is Ok(_))
    assert_true(measure_input_values(table, 4, Output, shared) is Ok(_))
    assert_eq((shared.work, shared.bytes, shared.nodes), (0, 0, 0))
  }
}
