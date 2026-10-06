///|
fn large_rows_events_bridge_input() -> (
  @execution.CompletedOutput,
  @lower.BoundPrepared,
  @execution.ProducerRead,
) raise {
  let source_text = "[{\"values\":{\"schema\":{" +
    "\"event_id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"occurred_at\":{\"type\":\"number\",\"nullable\":false}," +
    "\"payload\":{\"type\":\"string\",\"nullable\":false}," +
    "\"zz_unused\":{\"type\":\"array\",\"nullable\":false," +
    "\"max_items\":129,\"items\":{\"type\":\"number\",\"nullable\":false}}}," +
    "\"rows\":[{\"event_id\":1,\"occurred_at\":12,\"payload\":\"" +
    String::make(8193, 'p') +
    "\",\"zz_unused\":[" +
    Array::make(129, "1").join(",") +
    "]}]},\"as\":\"source\"}]"
  // Preparation is not the Bridge's 149-unit construction boundary.
  // The whole Values scan, literal scan and literal reservation each
  // charge the 8193-byte payload: 24579 before finite schema/name costs.
  let admission = @pipeline.check(input_cursor(source_text), [], None, None, {
    max_steps: 10,
    max_work: 100000,
    max_text_bytes: 30000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  })
  assert_eq(admission.map(_ => ()).map_err(issue => issue.kind), Ok(()))
  let checked = admission.unwrap()
  let source_owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_output_owner(source_owner)
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  (source, owner, input)
}

///|
fn large_rows_events_bridge_limits(
  work : Int,
  slots : Int,
) -> @record_storage.Limits {
  {
    ..carrier_events_storage_limits(),
    max_value_bytes: 10000,
    max_value_nodes: 1000,
    max_work: work,
    max_workspace_slots: slots,
  }
}

///|
test "rows to Events keeps logical limits while yielding inside large values" {
  let (source, owner, input) = large_rows_events_bridge_input()
  // Load: two numbers cost 3 each; Text costs Read+Node+129 fragments+
  // Complete = 132; Array costs Read+Node+129*(Next+Node)+End+Complete
  // = 262. Load total 400. Append start is one. Shared append uses 423
  // polls, including 130 Text and 260 Array wire polls: physical total 824.
  // Wire nodes: key 2 + record (outer 1 + field arrays/names 8 + values
  // 133) + copy 5 = 149. Names, punctuation and values need 8520 bytes.
  // Cursor workspace 16+3*4+1+3*10 = 59, caller fields/handles 6,
  // and committed row 6 overlap: peak 71. These are independent costs.
  for
    (work, slots, outcome, quantum) in [
      (149, 71, "complete", 1),
      (149, 71, "complete", 7),
      (149, 71, "complete", 256),
      (148, 71, "work", 1),
      (149, 70, "workspace", 1),
    ] {
    let active = @local_bridge.start_rows_to_events(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      input,
      large_rows_events_bridge_limits(work, slots),
      10000L,
      fn() { true },
    ).unwrap()
    let mut prior = 0L
    let mut terminal = false
    for _ in 0..<900 {
      match @local_bridge.advance_rows_to_events(active, quantum).unwrap() {
        @local_bridge.Continue(progress~, work~) => {
          assert_true(work > prior && work - prior <= quantum.to_int64())
          prior = work
          assert_true(progress == 0L || work == 824L)
        }
        @local_bridge.Complete(output, work~, ..) => {
          assert_eq(outcome, "complete")
          assert_eq(work, 824L)
          let evidence = @records.completed_evidence(output).unwrap()
          assert_eq(@records.evidence_construction_work(evidence), 149)
          assert_eq(@records.evidence_retained_value_bytes(evidence), 8520)
          assert_eq(@records.evidence_workspace_slots(evidence), 6)
          let storage = @records.completed_storage(output).unwrap()
          assert_eq(@record_storage.record_count(storage), 1)
          let values = @record_storage.record_field_count(storage, 0).unwrap()
          assert_eq(values, 4)
          for index in 0..<values {
            let (name, checked) = @record_storage.record_field_at(
              storage, 0, index,
            ).unwrap()
            match @schema.reference_name(name) {
              "payload" =>
                assert_true(
                  checked.value is @admitted.Text(text) &&
                  text == String::make(8193, 'p'),
                )
              "zz_unused" =>
                assert_true(
                  checked.value is @admitted.Array(items) &&
                  @admitted.element_count(items) == 129,
                )
              "event_id" => assert_true(checked.value is @admitted.Number(1.0))
              "occurred_at" =>
                assert_true(checked.value is @admitted.Number(12.0))
              _ => fail("unexpected bridge field")
            }
          }
          assert_true(@records.discard_completed(output))
          terminal = true
          break
        }
        @local_bridge.Failed(
          @local_bridge.Output(@records.Storage(@record_storage.WorkLimit)),
          ..
        ) => {
          assert_eq(outcome, "work")
          terminal = true
          break
        }
        @local_bridge.Failed(
          @local_bridge.Output(@records.Storage(@record_storage.WorkspaceLimit)),
          ..
        ) => {
          assert_eq(outcome, "workspace")
          terminal = true
          break
        }
        _ => fail("unexpected large Bridge terminal")
      }
    }
    assert_true(terminal)
    assert_true(@local_bridge.rows_to_events_cleanup_pending(active))
    assert_eq(@local_bridge.cleanup_rows_to_events(active), Ok(true))
    assert_eq(@local_bridge.cleanup_rows_to_events(active), Ok(false))
    assert_false(@local_bridge.rows_to_events_cleanup_pending(active))
    assert_true(@execution.completed_output_available(source))
    assert_true(@execution.producer_read_available(input))
  }
}

///|
test "rows to Events retains input through stopped recheck and append" {
  let (source, owner, input) = large_rows_events_bridge_input()
  // At poll 9 the borrowed Text has checked only its first 64 units.
  // At poll 256 the unused Array is still being checked. Poll 430 is
  // inside the Text emitter after all four cells have passed rechecking.
  for boundary in [9, 256, 430] {
    let control = @bounded.control()
    let active = @local_bridge.start_rows_to_events(
      control,
      prepared_sequence(owner),
      0,
      input,
      large_rows_events_bridge_limits(149, 71),
      10000L,
      fn() { true },
    ).unwrap()
    for _ in 0..<boundary {
      guard @local_bridge.advance_rows_to_events(active, 1).unwrap()
        is @local_bridge.Continue(progress~, work~) else {
        fail("bridge completed before its cancellation boundary")
      }
      assert_eq(progress, 0L)
      assert_true(work <= boundary.to_int64())
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(@execution.producer_read_available(input))
    guard @local_bridge.advance_rows_to_events(active, 1).unwrap()
      is @local_bridge.Stopped(_, progress~, work~) else {
      fail("bridge did not confirm stop")
    }
    assert_eq(progress, 0L)
    assert_eq(work, boundary.to_int64())
    assert_true(@local_bridge.rows_to_events_cleanup_pending(active))
    assert_true(@execution.producer_read_available(input))
    assert_eq(@local_bridge.cleanup_rows_to_events(active), Ok(true))
    assert_eq(@local_bridge.cleanup_rows_to_events(active), Ok(false))
    assert_false(@local_bridge.rows_to_events_cleanup_pending(active))
    assert_true(@execution.completed_output_available(source))
  }
}
