///|
test "presence row cursor shares cumulative charges without replacing absence with NULL" {
  let owner = presence_output_owner()
  // Three outer rows, six physical cells, and names id/p (three bytes per
  // row): nine nodes plus nine text bytes, hence eighteen logical work.
  let output = prepare_admitted_output(owner, Step(0), 3, {
    max_nodes: 9,
    max_text_bytes: 9,
    max_depth: 2,
    max_work: 18,
  }).unwrap()
  for row in 0..<3 {
    let cursor = start_admitted_presence_output_row(output, 3, column => {
      Some(
        if column == 0 {
          Present(@admitted.number_value((row + 1).to_double()).unwrap())
        } else if row == 0 {
          Present(@admitted.number_value(7.0).unwrap())
        } else if row == 1 {
          Present(@admitted.null_value())
        } else {
          Absent
        },
      )
    }).unwrap()
    let mut terminal = false
    let mut polls = 0
    // Number/NULL each need read + two recheck polls. Absence needs only
    // its read. Charging needs start + two names + two cells + commit.
    let exact_polls = if row == 2 { 10 } else { 12 }
    while !terminal && polls < exact_polls {
      assert_true(finish_admitted_output(output) is Err(ClosedCapture))
      terminal = advance_admitted_output_row(cursor).unwrap()
      polls += 1
    }
    assert_true(terminal)
    assert_eq(polls, exact_polls)
    assert_eq(cursor.workspace.peak, 3)
    assert_true(cleanup_admitted_output_row(cursor))
    assert_false(cleanup_admitted_output_row(cursor))
    assert_eq(cursor.workspace.live, 0)
    assert_eq(output.buffer.presence_rows.length(), row + 1)
  }
  let rows = finish_admitted_output(output).unwrap()
  assert_eq(admitted_output_usage(rows), { nodes: 9, text_bytes: 9, work: 18, })
  for row, wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
    let retained = rows.presence_rows[row]
    assert_eq(relation_row_usage(retained), {
      nodes: 3,
      text_bytes: 3,
      work: 6,
    })
    let writer = @encode.writer(100, 10, 3)
    emit_relation_row(retained, writer)
    assert_eq(@encode.finish(writer), wire)
    let reread = read_retained_relation_row(
      retained.schema,
      wire,
      retained_row_test_limits(),
      stream_value_limits(),
    ).unwrap()
    assert_true(
      relation_row_required_value(reread, 1) is Err(PresenceNotGuaranteed(1)),
    )
    if row == 2 {
      assert_true(relation_row_cell(reread, 1) is Ok(Absent))
    } else if row == 1 {
      assert_true(relation_row_cell(reread, 1) is Ok(Present(@admitted.Null)))
    }
  }
}

///|
test "presence row cursor rejects missing required cells and preserves failed custody" {
  let owner = presence_output_owner()
  for unavailable in [false, true] {
    let output = prepare_admitted_output(
      owner,
      Step(0),
      1,
      stream_value_limits(),
    ).unwrap()
    assert_true(
      start_admitted_output_row(output, 3, _ => None)
      is Err(OutputRowCapture(ConditionalInputRequiresPresence)),
    )
    assert_true(
      start_admitted_presence_output_row(output, 2, _ => Some(Absent))
      is Err(OutputRowWorkspace),
    )
    let cursor = start_admitted_presence_output_row(output, 3, _ => {
      if unavailable {
        None
      } else {
        Some(Absent)
      }
    }).unwrap()
    assert_eq(
      advance_admitted_output_row(cursor),
      Err(OutputRowCapture(InvalidCheckedRow)),
    )
    assert_true(output.buffer.reading)
    assert_eq(cursor.workspace.live, 3)
    assert_true(output.buffer.presence_rows.is_empty())
    assert_true(cleanup_admitted_output_row(cursor))
    assert_false(cleanup_admitted_output_row(cursor))
    assert_eq(cursor.workspace.live, 0)
    assert_true(finish_admitted_output(output) is Err(ClosedCapture))
  }
}

///|
test "presence row cursor retains each one-short failure and cancellation boundary" {
  let owner = presence_output_owner()
  let read = column => {
    Some(
      if column == 0 {
        Present(@admitted.number_value(3.0).unwrap())
      } else {
        Absent
      },
    )
  }
  for short in [0, 1, 2] {
    let output = prepare_admitted_output(owner, Step(0), 1, {
      max_nodes: if short == 0 {
        2
      } else {
        3
      },
      max_text_bytes: if short == 1 {
        2
      } else {
        3
      },
      max_depth: 2,
      max_work: if short == 2 {
        5
      } else {
        6
      },
    }).unwrap()
    let cursor = start_admitted_presence_output_row(output, 3, read).unwrap()
    let mut rejected = false
    for _ in 0..<10 {
      match advance_admitted_output_row(cursor) {
        Ok(false) => ()
        Err(OutputRowCapture(CaptureLimit)) => {
          rejected = true
          break
        }
        _ => fail("one-short must preserve its capture limit")
      }
    }
    assert_true(rejected)
    assert_true(output.buffer.reading)
    assert_true(output.buffer.presence_rows.is_empty())
    assert_true(cleanup_admitted_output_row(cursor))
    assert_eq(cursor.workspace.live, 0)
  }
  for barrier in 1..<10 {
    let output = prepare_admitted_output(
      owner,
      Step(0),
      1,
      stream_value_limits(),
    ).unwrap()
    let cursor = start_admitted_presence_output_row(output, 3, read).unwrap()
    for _ in 0..<barrier {
      assert_eq(advance_admitted_output_row(cursor), Ok(false))
    }
    assert_true(output.buffer.reading)
    assert_true(output.buffer.presence_rows.is_empty())
    assert_true(cleanup_admitted_output_row(cursor))
    assert_false(cleanup_admitted_output_row(cursor))
    assert_eq(cursor.workspace.live, 0)
    assert_true(output.buffer.presence_rows.is_empty())
    assert_eq(
      advance_admitted_output_row(cursor),
      Err(OutputRowCapture(ClosedCapture)),
    )
  }
}

///|
test "presence row cursor yields inside nested cells and charges immutable sharing" {
  let schema = @schema.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        Required,
      ),
      (
        Unqualified("p"),
        @contract.primitive(JsonType, nullable=false),
        Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let owner = presence_output_owner(schema~)
  let number = @admitted.number_value(7.0).unwrap()
  let nested = @admitted.array_value(Array::make(128, number))
  let read = column => Some(Present(if column == 0 { number } else { nested }))
  // One row + id + array + 128 scalar occurrences = 131 nodes. The three
  // name bytes add three logical work even when all scalar backing is shared.
  for short in [false, true] {
    let output = prepare_admitted_output(owner, Step(0), 1, {
      max_nodes: 131,
      max_text_bytes: 3,
      max_depth: 3,
      max_work: if short {
        133
      } else {
        134
      },
    }).unwrap()
    let cursor = start_admitted_presence_output_row(output, 5, read).unwrap()
    let mut terminal = false
    for _ in 0..<1000 {
      match advance_admitted_output_row(cursor) {
        Ok(false) => ()
        Ok(true) => {
          assert_false(short)
          let rows = finish_admitted_output(output).unwrap()
          assert_eq(admitted_output_usage(rows), {
            nodes: 131,
            text_bytes: 3,
            work: 134,
          })
          terminal = true
          break
        }
        Err(OutputRowCapture(CaptureLimit)) => {
          assert_true(short)
          assert_true(output.buffer.presence_rows.is_empty())
          terminal = true
          break
        }
        _ => fail("nested presence failed outside the logical boundary")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_admitted_output_row(cursor))
    assert_eq(cursor.workspace.live, 0)
  }
  // Recheck visits a node and a container frame separately (259 polls for
  // this array). Poll 132 is inside recheck; poll 300 is inside measurement.
  for barrier in [132, 300] {
    let output = prepare_admitted_output(
      owner,
      Step(0),
      1,
      stream_value_limits(),
    ).unwrap()
    let cursor = start_admitted_presence_output_row(output, 5, read).unwrap()
    for _ in 0..<barrier {
      assert_eq(advance_admitted_output_row(cursor), Ok(false))
    }
    if barrier == 132 {
      assert_true(cursor.recheck is Some(_))
    }
    if barrier == 300 {
      assert_true(cursor.charge is Some(_))
    }
    assert_true(output.buffer.presence_rows.is_empty())
    assert_true(cleanup_admitted_output_row(cursor))
    assert_eq(cursor.workspace.live, 0)
    assert_true(cursor.presence_cells is None)
    assert_false(cleanup_admitted_output_row(cursor))
  }
}
