///|
fn distinct_pool_source(producer : @lower.BoundPrepared) -> @records.Completed {
  let output = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    limits(),
    8192L,
    fn() { true },
  ).unwrap()
  // Input order deliberately differs from semantic group order.
  for group in [4.0, 2.0, 3.0, 1.0] {
    @records.append_record(output, [
      (@schema.Unqualified("id"), number(group)),
      (@schema.Unqualified("group"), number(group)),
      (@schema.Unqualified("embedding"), vector("[1,2]")),
    ]).unwrap()
  }
  @records.finish_output(output).unwrap()
}

///|
test "Pool keeps caller workspace reserved while retained output grows" {
  let producer = pool_producer_owner()
  let source = distinct_pool_source(producer)
  let material = @records.completed_material(source).unwrap()
  let owner = pool_owner(producer)
  // Admission: two four-slot arrays per input record (32), output fields (3),
  // vector components (2), keys (2), name offset (1), fixed append (56): 96.
  // The existing conservative caller reservation is 40. Four output records
  // retain 4*(3+2)=20 additional slots at FinishRecord: exact peak 116.
  // Even omitting scratch and handles, records (16), fields (3), components
  // (2), append (56), and retained output (20) require 97, exceeding 96.
  for viewed in [false, true] {
    for (workspace, should_refuse) in [(96, true), (115, true), (116, false)] {
      let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
      let active = if viewed {
        let view = @carrier_runtime.material_prepare_view(
          material, owner, 0, producer,
        ).unwrap()
        start_pool_view(
          @bounded.control(),
          sequence(owner),
          0,
          view,
          limits(workspace~),
          8192L,
          fn() { true },
        ).unwrap()
      } else {
        start_pool(
          @bounded.control(),
          sequence(owner),
          0,
          read,
          limits(workspace~),
          8192L,
          fn() { true },
        ).unwrap()
      }
      let mut terminal = false
      let mut refused = false
      let mut saw_append = false
      for _ in 0..<1000 {
        if !terminal {
          match advance_pool(active, 1).unwrap() {
            PoolContinue(..) =>
              if active.state.output_append is Some(_) {
                saw_append = true
                assert_eq(
                  @records.output_workspace_slots(active.state.output.unwrap()),
                  96 + 5 * active.state.group_start,
                )
                assert_eq(active.state.records.length(), 4)
                for record in active.state.records {
                  assert_eq(record.groups.length(), 1)
                  assert_eq(record.identities.length(), 1)
                }
                assert_eq(active.state.scratch.length(), 4)
                for entry in active.state.scratch {
                  assert_true(entry is None)
                }
                assert_eq(active.state.output_fields.length(), 3)
                guard active.state.pooled_vector
                  is Some({ value: @value.Vector(components), .. }) else {
                  fail("caller vector must remain live during append")
                }
                assert_eq(@value.element_count(components), 2)
              }
            PoolFailed(issue, ..) => {
              assert_eq(
                issue,
                PoolOutput(@records.Storage(@storage.WorkspaceLimit)),
              )
              refused = true
              terminal = true
            }
            PoolComplete(output, ..) => {
              let stored = @records.completed_storage(output).unwrap()
              assert_eq(@storage.record_count(stored), 4)
              assert_eq(@storage.retained_workspace_slots(stored), 20)
              assert_eq(@storage.construction_work(stored), 72)
              for index in 0..<4 {
                assert_true(
                  pool_field(stored, index, "group").value
                  is @value.Number(value) &&
                  value == (index + 1).to_double(),
                )
                assert_true(
                  pool_field(stored, index, "member_count").value
                  is @value.Number(1.0),
                )
                guard pool_field(stored, index, "embedding").value
                  is @value.Vector(components) else {
                  fail("pooled output vector must survive completion")
                }
                assert_eq(@value.element_count(components), 2)
                assert_eq(@value.element_at(components, 0), Some(1.0))
                assert_eq(@value.element_at(components, 1), Some(2.0))
              }
              assert_true(@records.discard_completed(output))
              terminal = true
            }
            _ => fail("caller reservation selected an unrelated terminal")
          }
        }
      }
      assert_true(terminal)
      assert_true(saw_append)
      assert_eq(cleanup_pool(active), Ok(true))
      assert_eq(cleanup_pool(active), Ok(false))
      assert_true(@records.producer_read_available(read))
      assert_true(@carrier_runtime.material_available(material))
      assert_eq(refused, should_refuse)
    }
  }
  assert_true(@records.discard_completed(source))
}

///|
test "Pool caller reservation stays owned until confirmed append stop" {
  let producer = pool_producer_owner()
  let source = distinct_pool_source(producer)
  let material = @records.completed_material(source).unwrap()
  let owner = pool_owner(producer)
  for viewed in [false, true] {
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let control = @bounded.control()
    let active = if viewed {
      let view = @carrier_runtime.material_prepare_view(
        material, owner, 0, producer,
      ).unwrap()
      start_pool_view(
        control,
        sequence(owner),
        0,
        view,
        limits(workspace=116),
        8192L,
        fn() { true },
      ).unwrap()
    } else {
      start_pool(
        control,
        sequence(owner),
        0,
        read,
        limits(workspace=116),
        8192L,
        fn() { true },
      ).unwrap()
    }
    let output = active.state.output.unwrap()
    let mut reached = false
    for _ in 0..<1000 {
      assert_true(advance_pool(active, 1).unwrap() is PoolContinue(..))
      if active.state.group_start == 3 && active.state.output_append is Some(_) {
        reached = true
        break
      }
    }
    assert_true(reached)
    // Three accepted rows (15), append (56), existing caller reservation (40).
    assert_eq(@records.output_workspace_slots(output), 111)
    assert_true(@bounded.request_cancel(control))
    assert_eq(
      cleanup_pool(active),
      Err(PoolExecutionIssue(@bounded.NotStopped)),
    )
    assert_eq(@records.output_workspace_slots(output), 111)
    assert_eq(active.state.records.length(), 4)
    assert_eq(active.state.scratch.length(), 4)
    assert_eq(active.state.output_fields.length(), 3)
    assert_true(@records.producer_read_available(read))
    assert_true(@carrier_runtime.material_available(material))
    assert_true(
      advance_pool(active, 1).unwrap() is PoolStopped(@bounded.Cancelled, ..),
    )
    assert_eq(@records.output_workspace_slots(output), 111)
    assert_eq(cleanup_pool(active), Ok(true))
    assert_eq(cleanup_pool(active), Ok(false))
    assert_eq(@records.output_workspace_slots(output), 0)
    assert_true(active.state.records.is_empty())
    assert_true(active.state.scratch.is_empty())
    assert_true(active.state.output_fields.is_empty())
    assert_true(active.state.output_append is None)
    assert_true(active.state.pooled_vector is None)
    assert_true(@records.producer_read_available(read))
    assert_true(@carrier_runtime.material_available(material))
  }
  assert_true(@records.discard_completed(source))
}
