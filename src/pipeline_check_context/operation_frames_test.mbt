///|
fn frame_fixture(
  start : String,
  end : String,
  n : String,
) -> ProgramOperationScalars {
  let steps = scalar_steps(
    "{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":" +
    start +
    ",\"end\":" +
    end +
    "},\"functions\":{\"first\":{\"fn\":\"first_value\",\"expr\":\"id\"}}}}",
  )
  let requirements = operation_order_fixture(
    steps,
    supplied=Some(cursor("{\"n\":" + n + "}")),
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  check_program_operation_scalars(orders, 10000000, 100).unwrap()
}

///|
test "owned ROWS frame comparisons preserve direction equality and exact large distances" {
  for direction in ["preceding", "following"] {
    for parameter_first in [true, false] {
      let symbolic = "{\"" + direction + "\":{\"$param\":\"n\"}}"
      let literal = "{\"" + direction + "\":2}"
      for
        (n, distance) in [
          ("1", 1L),
          ("2", 2L),
          ("3", 3L),
          ("9007199254740991", 9007199254740991L),
        ] {
        let start = if parameter_first { symbolic } else { literal }
        let end = if parameter_first { literal } else { symbolic }
        let scalars = frame_fixture(start, end, n)
        let result = check_program_operation_frames(scalars, 10000000, 100)
        let a = if parameter_first { distance } else { 2L }
        let z = if parameter_first { 2L } else { distance }
        let accepted = if direction == "preceding" { a >= z } else { a <= z }
        assert_eq(result is Ok(_), accepted)
        if accepted {
          let result = result.unwrap()
          assert_eq(operation_frames_count(result), 3)
          assert_true(physical_equal(operation_frames_scalars(result), scalars))
          for i in 0..<3 {
            let entry = operation_frame_at(result, i).unwrap()
            assert_eq(entry.start_distance, a)
            assert_eq(entry.end_distance, z)
            assert_eq(entry.start_parameter is Some(_), parameter_first)
            assert_eq(entry.end_parameter is Some(_), !parameter_first)
            let bound = if parameter_first {
              entry.start_parameter.unwrap()
            } else {
              entry.end_parameter.unwrap()
            }
            assert_eq(bound.name, "n")
            assert_true(bound.origin is Supplied)
            let requirements = operation_orders_requirements(
              operation_scalars_orders(scalars),
            )
            assert_true(
              physical_equal(
                entry.site,
                operation_requirements_at(requirements, entry.requirement_index).unwrap(),
              ),
            )
          }
          let work = operation_frames_work(result)
          assert_true(check_program_operation_frames(scalars, work, 3) is Ok(_))
          assert_true(
            check_program_operation_frames(scalars, work - 1, 3)
            is Err(BudgetExceeded),
          )
          assert_true(
            check_program_operation_frames(scalars, work, 2)
            is Err(BudgetExceeded),
          )
          assert_true(
            check_program_operation_frames(scalars, -1, 3) is Err(InvalidLimits),
          )
          assert_true(
            check_program_operation_frames(scalars, work, -1)
            is Err(InvalidLimits),
          )
          assert_true(operation_frame_at(result, -1) is None)
          assert_true(operation_frame_at(result, 3) is None)
        } else {
          assert_true(result is Err(InvalidFrame(_)))
        }
      }
    }
  }
}

///|
test "identical symbolic frame boundaries need scalar admission but no comparison obligation" {
  let boundary = "{\"preceding\":{\"$param\":\"n\"}}"
  let scalars = frame_fixture(boundary, boundary, "1")
  assert_eq(operation_scalars_count(scalars), 6)
  let result = check_program_operation_frames(scalars, 10000000, 0).unwrap()
  assert_eq(operation_frames_count(result), 0)
  let work = operation_frames_work(result)
  assert_true(check_program_operation_frames(scalars, work, 0) is Ok(_))
  assert_true(
    check_program_operation_frames(scalars, work - 1, 0) is Err(BudgetExceeded),
  )
}
