///|
priv enum BinaryOutputFixture {
  Append(BoundedAppendExecution)
  Set(BoundedSetExecution)
  Cross(BoundedCrossJoinExecution)
}

///|
priv enum BinaryOutputFixturePoll {
  Continue
  Complete(CompletedOutput)
  Stopped
  OutputLimit
  WorkspaceLimit
}

///|
fn binary_output_fixture(
  kind : Int,
  output_values : ValueLimits,
  max_entries? : Int = 100,
) -> (@bounded.Control, BinaryOutputFixture, Array[ProducerRead]) raise {
  let text = "x".repeat(4096)
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}}"
  let rows = "[{\"id\":1,\"tag\":\"" + text + "\"}]"
  match kind {
    0 => {
      let (control, started, reads) = bounded_append_fixture(
        left_schema=schema,
        right_schema=schema,
        left_rows=rows,
        right_rows="[]",
        output_values~,
        max_entries~,
        max_work=100000,
      )
      (control, Append(started.unwrap()), reads)
    }
    1 | 3 | 4 | 5 => {
      let (control, started, reads) = bounded_set_fixture(
        operation=if kind == 3 || kind == 5 { "intersect" } else { "except" },
        duplicates=if kind >= 4 { "distinct" } else { "all" },
        left_schema=schema,
        right_schema=schema,
        left_rows=rows,
        right_rows=if kind == 3 || kind == 5 { rows } else { "[]" },
        output_values~,
        max_entries~,
        max_work=100000,
      )
      (control, Set(started.unwrap()), reads)
    }
    _ => {
      let (control, started, reads) = bounded_cross_fixture(
        left_rows="[{\"id\":1}]",
        right_rows="[{\"tag\":\"" + text + "\"}]",
        output_values~,
        max_entries~,
        max_work=100000,
      )
      (control, Cross(started.unwrap()), reads)
    }
  }
}

///|
fn advance_binary_output_fixture(
  value : BinaryOutputFixture,
) -> BinaryOutputFixturePoll raise {
  match value {
    Append(value) =>
      match advance_bounded_append(value, 1).unwrap() {
        BoundedAppendContinue(..) => Continue
        BoundedAppendComplete(output, ..) => Complete(output)
        BoundedAppendStopped(_, ..) => Stopped
        BoundedAppendFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedAppendFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("append output failed for an unexpected cause")
      }
    Set(value) =>
      match advance_bounded_set(value, 1).unwrap() {
        BoundedSetContinue(..) => Continue
        BoundedSetComplete(output, ..) => Complete(output)
        BoundedSetStopped(_, ..) => Stopped
        BoundedSetFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedSetFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("set output failed for an unexpected cause")
      }
    Cross(value) =>
      match advance_bounded_cross_join(value, 1).unwrap() {
        BoundedCrossJoinContinue(..) => Continue
        BoundedCrossJoinComplete(output, ..) => Complete(output)
        BoundedCrossJoinStopped(_, ..) => Stopped
        BoundedCrossJoinFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedCrossJoinFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("cross output failed for an unexpected cause")
      }
  }
}

///|
fn binary_output_recheck(value : BinaryOutputFixture) -> Bool {
  match value {
    Append(value) => value.state.output_recheck is Some(_)
    Set(value) => value.state.output_recheck is Some(_)
    Cross(value) => value.state.output_recheck is Some(_)
  }
}

///|
fn binary_output_charge(value : BinaryOutputFixture) -> Bool {
  let cursor = match value {
    Append(value) => value.state.output_charge
    Set(value) => value.state.output_charge
    Cross(value) => value.state.output_charge
  }
  cursor is Some(cursor) && cursor.measure is Some(_)
}

///|
fn cleanup_binary_output_fixture(value : BinaryOutputFixture) -> Bool raise {
  match value {
    Append(value) => {
      let cleaned = cleanup_bounded_append(value).unwrap()
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output is None)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
      cleaned
    }
    Set(value) => {
      let cleaned = cleanup_bounded_set(value).unwrap()
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output is None)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
      cleaned
    }
    Cross(value) => {
      let cleaned = cleanup_bounded_cross_join(value).unwrap()
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output is None)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
      cleaned
    }
  }
}

///|
fn binary_output_limits() -> ValueLimits {
  // One row and two scalar nodes. Names `id` and `tag` plus 4096 Text
  // bytes consume 4101 bytes; all nodes and bytes consume 4104 work units.
  { max_nodes: 3, max_text_bytes: 4101, max_depth: 2, max_work: 4104, }
}

///|
test "binary output owners stop within raw text recheck and output charge" {
  for kind in 0..<6 {
    for stop_in_charge in [false, true] {
      let (control, execution, reads) = binary_output_fixture(
        kind,
        binary_output_limits(),
      )
      let mut reached = false
      // INTERSECT admits both 4096-byte rows and completes its charged
      // complete-row comparisons before entering the output phases.
      for _ in 0..<100000 {
        assert_true(advance_binary_output_fixture(execution) is Continue)
        if (stop_in_charge && binary_output_charge(execution)) ||
          (!stop_in_charge && binary_output_recheck(execution)) {
          reached = true
          break
        }
      }
      assert_true(reached)
      assert_true(advance_binary_output_fixture(execution) is Continue)
      assert_true(
        if stop_in_charge {
          binary_output_charge(execution)
        } else {
          binary_output_recheck(execution)
        },
      )
      assert_true(@bounded.request_cancel(control))
      assert_true(advance_binary_output_fixture(execution) is Stopped)
      assert_true(reads.all(read => producer_read_available(read)))
      assert_true(cleanup_binary_output_fixture(execution))
      assert_true(reads.all(read => producer_read_available(read)))
    }
  }
}

///|
test "binary output owners retain independent exact and one short limits" {
  for kind in 0..<6 {
    for
      (nodes, bytes, work, succeed) in [
        (3, 4101, 4104, true),
        (2, 4101, 4104, false),
        (3, 4100, 4104, false),
        (3, 4101, 4103, false),
      ] {
      let (_, execution, reads) = binary_output_fixture(kind, {
        ..binary_output_limits(),
        max_nodes: nodes,
        max_text_bytes: bytes,
        max_work: work,
      })
      let mut terminal = false
      for _ in 0..<100000 {
        match advance_binary_output_fixture(execution) {
          Continue => ()
          Complete(output) => {
            assert_true(succeed)
            assert_eq(completed_row_count(output), 1)
            assert_eq(completed_column_count(output), 2)
            assert_eq(completed_column_name(output, 0), Some("id"))
            assert_eq(completed_column_name(output, 1), Some("tag"))
            assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
            guard completed_cell(output, 0, 1) is Some(Text(text)) else {
              fail("binary owner did not publish its expected Text")
            }
            assert_eq(text, "x".repeat(4096))
            terminal = true
            break
          }
          OutputLimit => {
            assert_false(succeed)
            terminal = true
            break
          }
          _ => fail("binary output budget failed at a different boundary")
        }
      }
      assert_true(terminal)
      assert_true(cleanup_binary_output_fixture(execution))
      assert_true(reads.all(read => producer_read_available(read)))
    }
  }
}

///|
test "binary output measurement reserves its traversal frame before use" {
  // Append: three field metadata slots per column, two retained row slots,
  // two copied cells and one measurement frame: 6 + 2 + 2 + 1 = 11.
  // Set: six metadata, three sort coordinates, one keep flag, two copied
  // cells and one measurement frame: 6 + 3 + 1 + 2 + 1 = 13.
  // Intersect adds three right sort coordinates: 16. ALL and DISTINCT
  // use the same retained coordinates for this one-survivor fixture.
  // Cross: two initial slots, six metadata, two pair slots, two copied cells
  // and one measurement frame: 2 + 6 + 2 + 2 + 1 = 13.
  for (kind, exact) in [(0, 11), (1, 13), (2, 13), (3, 16), (4, 13), (5, 16)] {
    for succeed in [true, false] {
      let (_, execution, reads) = binary_output_fixture(
        kind,
        binary_output_limits(),
        max_entries=if succeed { exact } else { exact - 1 },
      )
      let mut terminal = false
      for _ in 0..<100000 {
        match advance_binary_output_fixture(execution) {
          Continue => ()
          Complete(_) => {
            assert_true(succeed)
            terminal = true
            break
          }
          WorkspaceLimit => {
            assert_false(succeed)
            terminal = true
            break
          }
          _ => fail("binary output workspace failed at a different boundary")
        }
      }
      assert_true(terminal)
      assert_true(cleanup_binary_output_fixture(execution))
      assert_true(reads.all(read => producer_read_available(read)))
    }
  }
}

///|
test "binary output walks a copied nested array between child values" {
  let schema = "{\"id\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  let array = Array::makei(256, index => index.to_string()).join(",")
  let rows = "[{\"id\":[" + array + "]}]"
  // One row, one array and 256 numeric children; field `id` costs two
  // UTF-8 bytes. No copied child contains text or another container.
  let limits : ValueLimits = {
    max_nodes: 258,
    max_text_bytes: 2,
    max_depth: 3,
    max_work: 260,
  }
  for cancel in [true, false] {
    let (control, started, reads) = bounded_append_fixture(
      left_schema=schema,
      right_schema=schema,
      left_rows=rows,
      right_rows="[]",
      output_values=limits,
      max_work=100000,
    )
    let execution : BinaryOutputFixture = Append(started.unwrap())
    let mut terminal = false
    for _ in 0..<20000 {
      match advance_binary_output_fixture(execution) {
        Continue =>
          if cancel {
            guard execution is Append(value) else {
              fail("nested output fixture must use Append")
            }
            if value.state.output_charge is Some(cursor) &&
              cursor.measure is Some(_) &&
              cursor.output.buffer.budget.nodes >= 20 {
              assert_true(@bounded.request_cancel(control))
              assert_true(advance_binary_output_fixture(execution) is Stopped)
              terminal = true
              break
            }
          }
        Complete(output) => {
          assert_false(cancel)
          guard completed_cell(output, 0, 0)
            is Some(Captured(@admitted.Array(items))) else {
            fail("binary output lost its copied array")
          }
          assert_eq(@admitted.element_count(items), 256)
          assert_true(
            @admitted.element_at(items, 0) is Some(@admitted.Number(0.0)),
          )
          assert_true(
            @admitted.element_at(items, 255) is Some(@admitted.Number(255.0)),
          )
          terminal = true
          break
        }
        _ => fail("nested binary output failed unexpectedly")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_binary_output_fixture(execution))
    assert_true(reads.all(read => producer_read_available(read)))
  }
}
