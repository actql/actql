///|
// Explicit UTC-only fixture artifact; providing its table is not profile permission.
fn utc_range_profile() -> @calendar_profile.Profile {
  let text = "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}"
  @calendar_profile.admit(
    @utf8.encode(text),
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
    "test-fixture",
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
}

///|
fn range_fixture(
  calendar : Bool,
  start : String,
  end : String,
  supplied : String,
) -> ProgramOperationFills {
  let name = if calendar { "calendar_series" } else { "time_series" }
  let options = if calendar {
    ",\"unit\":\"day\",\"timezone\":\"UTC\""
  } else {
    ",\"step\":1"
  }
  let steps = "[{\"" +
    name +
    "\":{\"start\":" +
    start +
    ",\"end\":" +
    end +
    options +
    "},\"as\":\"grid\"},{\"derive\":{\"x\":\"concat($p, to_string($n))\"}}]"
  let parameters = "{\"p\":{\"type\":\"string\",\"default\":\"x\"},\"n\":{\"type\":\"timestamp\",\"default\":\"2000-01-01T00:00:00.000Z\"}}"
  let requirements = operation_order_fixture(
    steps,
    parameters~,
    supplied=Some(cursor("{\"n\":\"" + supplied + "\"}")),
    tea=true,
    calendar~,
  )
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  check_program_operation_fills(frames, 10000000, 100).unwrap()
}

///|
test "bound UTC ranges accept equality and reject reversed endpoints without host time conversion" {
  let symbolic = "{\"$param\":\"n\"}"
  let literal = "\"2000-01-01T00:00:00.000Z\""
  for calendar in [false, true] {
    for first in [true, false] {
      for
        (bound, order) in [
          ("0001-01-01T00:00:00.000Z", -1),
          ("1999-12-31T23:59:59.999Z", -1),
          ("2000-01-01T00:00:00.000Z", 0),
          ("2000-01-01T00:00:00.001Z", 1),
          ("9999-12-31T23:59:59.999Z", 1),
        ] {
        let fills = range_fixture(
          calendar,
          if first {
            symbolic
          } else {
            literal
          },
          if first {
            literal
          } else {
            symbolic
          },
          bound,
        )
        let result = check_program_operation_ranges(fills, 10000000, 3)
        let accepted = if first { order <= 0 } else { order >= 0 }
        assert_eq(result is Ok(_), accepted)
        if accepted {
          let result = result.unwrap()
          assert_eq(operation_ranges_count(result), 3)
          assert_true(physical_equal(operation_ranges_fills(result), fills))
          for i in 0..<3 {
            let entry = operation_range_at(result, i).unwrap()
            assert_eq(entry.start_parameter is Some(_), first)
            assert_eq(entry.end_parameter is Some(_), !first)
            assert_eq(if first { entry.start } else { entry.end }, bound)
            let p = if first {
              entry.start_parameter.unwrap()
            } else {
              entry.end_parameter.unwrap()
            }
            assert_true(p.origin is Supplied)
            assert_eq(p.name, "n")
            let scalars = operation_frames_scalars(
              operation_fills_frames(fills),
            )
            let scalar = operation_scalar_at(scalars, i).unwrap()
            assert_eq(scalar.value, Timestamp(bound))
            assert_true(physical_equal(scalar.parameter, p))
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
          let work = operation_ranges_work(result)
          assert_true(check_program_operation_ranges(fills, work, 3) is Ok(_))
          assert_true(
            check_program_operation_ranges(fills, work - 1, 3)
            is Err(BudgetExceeded),
          )
          assert_true(
            check_program_operation_ranges(fills, work, 2)
            is Err(BudgetExceeded),
          )
          assert_true(
            check_program_operation_ranges(fills, -1, 3) is Err(InvalidLimits),
          )
          assert_true(
            check_program_operation_ranges(fills, work, -1)
            is Err(InvalidLimits),
          )
          assert_true(operation_range_at(result, -1) is None)
          assert_true(operation_range_at(result, 3) is None)
        } else {
          assert_true(result is Err(ReversedRange(_)))
        }
      }
    }
  }
}

///|
test "identical bound endpoints are empty while calendar rejects year zero" {
  let endpoint = "{\"$param\":\"n\"}"
  for calendar in [false, true] {
    for year_zero in [false, true] {
      let text = if year_zero {
        "0000-02-29T00:00:00.000Z"
      } else {
        "2000-02-29T00:00:00.000Z"
      }
      let fills = range_fixture(calendar, endpoint, endpoint, text)
      let result = check_program_operation_ranges(fills, 10000000, 100)
      if calendar && year_zero {
        assert_true(result is Err(InvalidCalendarYear(_)))
      } else {
        let result = result.unwrap()
        for i in 0..<3 {
          let entry = operation_range_at(result, i).unwrap()
          assert_eq(entry.start, entry.end)
          assert_true(
            physical_equal(
              entry.start_parameter.unwrap(),
              entry.end_parameter.unwrap(),
            ),
          )
        }
      }
    }
  }
}
