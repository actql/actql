///|
// Experimental reader only. The measured JS candidate was slower; keep the
// production path unchanged until a representative improvement is established.
priv struct CheckedGuardRow {
  values : Array[@admitted.CheckedValue]
}

///|
impl IndexedRows for CheckedGuardRow with fn row_count(_self) {
  1
}

///|
impl IndexedRows for CheckedGuardRow with fn column_count(self) {
  self.values.length()
}

///|
impl IndexedRows for CheckedGuardRow with fn row_width(self, _row) {
  self.values.length()
}

///|
impl IndexedRows for CheckedGuardRow with fn read_cell(self, _row, column) {
  capture(self.values[column].value)
}

///|
test "borrowed checked row preserves measurement charges and failure frontiers" {
  let owner = capture_fixture()
  let values = output_fixture_row(owner, 0)
  let borrowed = CheckedGuardRow::{ values, }
  let copied = SingleAdmittedGuardRow::{
    values: values.map(value => value.value),
  }
  assert_true(physical_equal(borrowed.values, values))
  for work in 0..<8 {
    for bytes in 0..<16 {
      for nodes in 0..<5 {
        for ceiling in [0, 1, 100] {
          let a : FixedInputGuardBudget = { work, bytes, nodes, depth: 10, }
          let b : FixedInputGuardBudget = { work, bytes, nodes, depth: 10, }
          let first = measure_input_values(borrowed, ceiling, InputValues, a)
          let second = measure_input_values(copied, ceiling, InputValues, b)
          // Compare the public guard frontier without relying on Error equality.
          let classify = fn(result) {
            match result {
              Ok(_) => (0, -1, -1)
              Err(MeasurementWork) => (1, -1, -1)
              Err(Measurement(_, row, column, _)) => (2, row, column)
              Err(ValueBytes(_, row, column)) => (3, row, column)
              Err(_) => (4, -1, -1)
            }
          }
          assert_eq(classify(first), classify(second))
          assert_eq((a.work, a.bytes, a.nodes), (b.work, b.bytes, b.nodes))
        }
      }
    }
  }
  let exact : FixedInputGuardBudget = {
    work: 100,
    bytes: 100,
    nodes: 100,
    depth: 10,
  }
  measure_input_values(borrowed, 100, InputValues, exact).unwrap()
  // Fixture values are 1 and "é": canonical UTF-8 scalar bytes 1 + 4.
  assert_eq((100 - exact.work, 100 - exact.bytes, 100 - exact.nodes), (3, 5, 2))
}

///|
test "checked row measurement paired diagnostic" {
  guard @env.get_env_var("ACTQL_CHECKED_ROW_DIAGNOSTIC") == Some("1") else {
    return
  }
  let sample = output_fixture_row(capture_fixture(), 0)
  let values = Array::makei(64, i => sample[i % 2])
  let count = 10000
  // Component diagnostic only: setup outside timing, alternating order, same
  // scalar emitter and budget. It is not a registered end-to-end acceptance run.
  for pair in 0..<8 {
    for leg in 0..<2 {
      let borrow = (pair + leg) % 2 == 0
      let budget : FixedInputGuardBudget = {
        work: count * 65,
        bytes: count * 160,
        nodes: count * 64,
        depth: 10,
      }
      let clock = @bench.monotonic_clock_start()
      for _ in 0..<count {
        if borrow {
          measure_input_values(
            CheckedGuardRow::{ values, },
            100,
            InputValues,
            budget,
          ).unwrap()
        } else {
          measure_input_values(
            SingleAdmittedGuardRow::{
              values: values.map(value => value.value),
            },
            100,
            InputValues,
            budget,
          ).unwrap()
        }
      }
      let elapsed = @bench.monotonic_clock_end(clock)
      assert_eq((budget.work, budget.bytes, budget.nodes), (0, 0, 0))
      if pair > 0 {
        println(
          "CHECKED_ROW_DIAGNOSTIC pair=" +
          pair.to_string() +
          " borrowed=" +
          borrow.to_string() +
          " elapsed=" +
          elapsed.to_string(),
        )
      }
    }
  }
}
