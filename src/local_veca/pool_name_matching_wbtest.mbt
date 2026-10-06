///|
test "Pool input and output name matching yield with owned stop custody" {
  let long = String::make(513, 'z')
  for role in 0..<3 {
    let id_name = if role == 0 { long } else { "id" }
    let group_name = if role == 1 { long } else { "group" }
    let vector_name = if role == 2 { long } else { "embedding" }
    let producer = pool_producer_owner(id_name~, group_name~, vector_name~)
    let owner = pool_owner(producer, group_name~)
    let prepared = sequence(owner, name_bytes=100000)
    let builder = @records.prepare_output(
      producer,
      @pipeline.Step(0),
      limits(),
      8192L,
      fn() { true },
    ).unwrap()
    @records.append_record(builder, [
      (@schema.Unqualified(id_name), number(1.0)),
      (@schema.Unqualified(group_name), number(7.0)),
      (@schema.Unqualified(vector_name), vector("[1,2]")),
    ]).unwrap()
    let source = @records.finish_output(builder).unwrap()
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    // Cancellation covers input identity/group/component, plus group/component
    // output matching. Reuse the same Session and real completed-input binding.
    for output in [false, true] {
      if output && role == 0 {
        continue
      }
      let control = @bounded.control()
      let active = start_pool(control, prepared, 0, read, limits(), 8192L, fn() {
        true
      }).unwrap()
      let mut found = false
      let mut stopped_work = 0L
      for _ in 0..<500 {
        guard advance_pool(active, 1).unwrap() is PoolContinue(work~, ..) else {
          fail("name scan was drained atomically or selected no matching field")
        }
        let phase_matches = if output {
          active.state.phase is BuildOutput
        } else {
          match role {
            0 => active.state.phase is MatchIdentity
            1 => active.state.phase is MatchGroup
            _ => active.state.phase is MatchComponent
          }
        }
        if phase_matches && active.state.name_offset > 0 {
          assert_eq(active.state.name_offset, 64)
          assert_true(work > 0L)
          stopped_work = work
          found = true
          break
        }
      }
      assert_true(found)
      assert_true(active.state.output is Some(_))
      assert_true(@records.producer_read_available(read))
      assert_true(@bounded.request_cancel(control))
      assert_eq(
        cleanup_pool(active),
        Err(PoolExecutionIssue(@bounded.NotStopped)),
      )
      assert_eq(active.state.name_offset, 64)
      assert_true(@records.producer_read_available(read))
      assert_true(
        advance_pool(active, 1).unwrap()
        is PoolStopped(@bounded.Cancelled, work~, ..) &&
        work == stopped_work,
      )
      assert_eq(active.state.name_offset, 64)
      assert_eq(cleanup_pool(active), Ok(true))
      assert_eq(active.state.name_offset, 0)
      assert_true(active.state.current_field is None)
      assert_true(active.state.output is None)
      assert_eq(cleanup_pool(active), Ok(false))
      assert_true(@records.producer_read_available(read))
    }
    assert_true(@records.discard_completed(source))
  }
}

///|
test "Pool wide output name search yields before scanning every group" {
  let names = Array::makei(9, index => "g" + index.to_string())
  let number_contract = @contract.primitive(
    @contract.NumberType,
    nullable=false,
  )
  let fields = names.map(name => {
    (@schema.Unqualified(name), Some(number_contract))
  })
  fields.push((@schema.Unqualified("id"), Some(number_contract)))
  fields.push(
    (
      @schema.Unqualified("embedding"),
      Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
    ),
  )
  let carrier = @carrier.relation(
    @carrier.rows(
      fields,
      field_set=@carrier.Closed,
      max_fields=11,
      max_name_bytes=29,
    ).unwrap(),
  )
  let checker_limits : @pipeline.Limits = {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }
  let producer = bind(
    @pipeline.check_carriers(
      cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}]",
      ),
      [("rows", carrier)],
      None,
      None,
      checker_limits,
    ).unwrap(),
  )
  let owner = bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"pool_vectors\":{\"by\":[" +
        names.map(name => "\"" + name + "\"").join(",") +
        "],\"method\":\"sum\"}}]",
      ),
      [
        (
          "prior",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(producer)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"prior\"")),
      checker_limits,
    ).unwrap(),
  )
  let budgets = { ..limits(work=10000), max_fields_per_record: 20, }
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    budgets,
    8192L,
    fn() { true },
  ).unwrap()
  let values = names.mapi((index, name) => {
    (@schema.Unqualified(name), number(index.to_double()))
  })
  values.push((@schema.Unqualified("id"), number(1.0)))
  values.push((@schema.Unqualified("embedding"), vector("[1,2]")))
  @records.append_record(builder, values).unwrap()
  let source = @records.finish_output(builder).unwrap()
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  for cancel in [false, true] {
    let control = @bounded.control()
    let active = start_pool(control, sequence(owner), 0, read, budgets, 8192L, fn() {
      true
    }).unwrap()
    let mut yielded = false
    let mut terminal = false
    for _ in 0..<1000 {
      if terminal {
        break
      }
      match advance_pool(active, 1).unwrap() {
        PoolContinue(..) =>
          if active.state.phase is BuildOutput &&
            active.state.group_probe >= 6 &&
            @carrier.field_at(
              @carrier.vector_records(active.state.output_vectors),
              active.state.output_field,
            )
            is Some({ name: @schema.Unqualified("g8"), .. }) {
            yielded = true
            assert_eq(active.state.name_offset, 0)
            if cancel {
              assert_true(@bounded.request_cancel(control))
              assert_eq(
                cleanup_pool(active),
                Err(PoolExecutionIssue(@bounded.NotStopped)),
              )
              assert_true(
                advance_pool(active, 1).unwrap()
                is PoolStopped(@bounded.Cancelled, ..),
              )
              terminal = true
            }
          }
        PoolComplete(output, ..) => {
          assert_false(cancel)
          let stored = @records.completed_storage(output).unwrap()
          assert_eq(@storage.record_count(stored), 1)
          for index in 0..<names.length() {
            let name = names[index]
            assert_true(
              pool_field(stored, 0, name).value is @value.Number(value) &&
              value == index.to_double(),
            )
          }
          assert_true(
            pool_field(stored, 0, "member_count").value is @value.Number(1.0),
          )
          guard pool_field(stored, 0, "embedding").value
            is @value.Vector(elements) else {
            fail("pooled component")
          }
          assert_eq(@value.element_at(elements, 0), Some(1.0))
          assert_eq(@value.element_at(elements, 1), Some(2.0))
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        _ => fail("wide name fixture failed outside its selected boundary")
      }
    }
    assert_true(yielded)
    assert_true(terminal)
    assert_eq(cleanup_pool(active), Ok(true))
    assert_eq(cleanup_pool(active), Ok(false))
    assert_true(@records.producer_read_available(read))
  }
  assert_true(@records.discard_completed(source))
}
