///|
fn nearest_long_role(prefix : String) -> String {
  // 513 raw UTF-16 units, including a supplementary character at the end.
  prefix.repeat(511) + "😀"
}

///|
fn nearest_named_source(
  id : Int,
  carrier : Bool,
  unused? : Bool = false,
) -> @lower.BoundPrepared {
  let identity = nearest_long_role("m")
  let component = nearest_long_role("z")
  let unused_schema = if unused {
    "\"aa_unused\":{\"type\":\"array\",\"nullable\":false,\"max_items\":115," +
    "\"items\":{\"type\":\"number\",\"nullable\":false}},"
  } else {
    ""
  }
  let unused_value = if unused {
    "\"aa_unused\":[" + Array::make(115, "1").join(",") + "],"
  } else {
    ""
  }
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{" +
        unused_schema +
        "\"" +
        identity +
        "\":{\"type\":\"number\",\"nullable\":false}," +
        "\"" +
        component +
        "\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}," +
        "\"rows\":[{" +
        unused_value +
        "\"" +
        identity +
        "\":" +
        id.to_string() +
        ",\"" +
        component +
        "\":[1,2]}]},\"as\":\"rows\"}" +
        (if carrier {
          ",{\"from\":\"rows\",\"to_vectors\":{\"id\":\"" +
          identity +
          "\",\"vector\":\"" +
          component +
          "\"}}"
        } else {
          ""
        }) +
        "]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 20000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn nearest_named_owner(
  candidates : @lower.BoundPrepared,
  queries : @lower.BoundPrepared,
  carrier : Bool,
) -> @lower.BoundPrepared {
  let roles = if carrier {
    ""
  } else {
    ",\"candidate_id\":\"" +
    nearest_long_role("m") +
    "\",\"query_id\":\"" +
    nearest_long_role("m") +
    "\",\"candidate_vector\":\"" +
    nearest_long_role("z") +
    "\",\"query_vector\":\"" +
    nearest_long_role("z") +
    "\""
  }
  let step = if carrier { 1 } else { 0 }
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"candidates\",\"nearest\":{\"queries\":\"queries\"," +
        "\"metric\":\"dot\",\"k\":1" +
        roles +
        "}}]",
      ),
      [
        (
          "candidates",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(candidates)),
              @pipeline.Step(step),
            ).unwrap(),
          ),
        ),
        (
          "queries",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(queries)),
              @pipeline.Step(step),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(input_cursor("\"candidates\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 20000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn nearest_named_carrier(
  source : @lower.BoundPrepared,
  id : Int,
) -> @carrier_runtime.Material {
  let output = @records.prepare_output(
    source,
    @pipeline.Step(1),
    {
      ..carrier_vectors_storage_limits(),
      max_value_bytes: 4096,
      max_work: 20000,
      max_contract_work: 20000,
    },
    20000L,
    fn() { true },
  ).unwrap()
  let value = @admitted.checked_number_value(
    id.to_double(),
    @value_contract.primitive(@value_contract.NumberType, nullable=false),
  ).unwrap()
  @records.append_record(output, [
    (@schema.Unqualified(nearest_long_role("m")), value),
    (
      @schema.Unqualified(nearest_long_role("z")),
      direct_nearest_vector("[1,2]"),
    ),
  ]).unwrap()
  @records.completed_material(@records.finish_output(output).unwrap()).unwrap()
}

///|
test "nearest borrowed names keep independent Carrier and Relation limits" {
  // 513-unit names need nine 64-unit fragments. The component's first
  // fragment shares the original field poll; each of two roles on each
  // side adds eight polls. Carrier 52+32=84, Relation 66+32=98.
  // Workspace: 6 records + 4 scores + 3 scratch + 2 identities + 17 fixed
  // =32; a depth-two Relation cursor adds 8+2+2=12, hence 44.
  for carrier in [true, false] {
    let candidates = nearest_named_source(1, carrier)
    let queries = nearest_named_source(10, carrier)
    let owner = nearest_named_owner(candidates, queries, carrier)
    let generated = task_test_generated(owner)
    let candidate_material = if carrier {
      Some(nearest_named_carrier(candidates, 1))
    } else {
      None
    }
    let query_material = if carrier {
      Some(nearest_named_carrier(queries, 10))
    } else {
      None
    }
    let inputs = if carrier {
      [
        @local_veca.nearest_carrier_producer(
          @carrier_runtime.material_prepare_view(
            candidate_material.unwrap(),
            owner,
            0,
            candidates,
          ).unwrap(),
        ),
        @local_veca.nearest_carrier_producer(
          @carrier_runtime.material_prepare_view(
            query_material.unwrap(),
            owner,
            1,
            queries,
          ).unwrap(),
        ),
      ]
    } else {
      [candidates, queries].mapi((port, source) => {
        @local_veca.nearest_relation_producer(
          @execution.prepare_producer_read(
            owner,
            @execution.bind_completed_input(
              owner,
              port,
              source,
              direct_nearest_relation_output(source),
            ).unwrap(),
            10,
            4000,
          ).unwrap(),
        )
      })
    }
    let workspace = if carrier { 32 } else { 44 }
    let required = if carrier { 84 } else { 98 }
    let start = fn(control, work, slots) {
      @local_veca.start_nearest_inputs_with_control_work_limit(
        control,
        @execution.generated_completion_preparation(generated),
        @execution.generated_prepared_sequence(generated),
        0,
        inputs[0],
        inputs[1],
        10,
        { max_nodes: 100, max_text_bytes: 1000, max_depth: 2, max_work: 1000, },
        slots,
        1000,
        2000,
        work,
      )
    }
    assert_true(
      start(@bounded.control(), required, workspace - 1)
      is Err(@local_veca.NearestWorkspaceLimit),
    )
    for quantum in [1, 7, 256] {
      for (limit, success) in [(required, true), (required - 1, false)] {
        let active = start(@bounded.control(), limit, workspace).unwrap()
        let mut terminal = false
        let mut previous = 0L
        for _ in 0..<120 {
          if !terminal {
            match @local_veca.advance_nearest(active, quantum).unwrap() {
              @local_veca.NearestContinue(work~, ..) => {
                assert_true(
                  work > previous && work - previous <= quantum.to_int64(),
                )
                previous = work
              }
              @local_veca.NearestComplete(output, work~, ..) => {
                assert_true(success)
                assert_eq(work, required.to_int64())
                assert_eq(@execution.completed_row_count(output), 1)
                for column, expected in [1.0, 10.0, 1.0, 5.0] {
                  assert_true(
                    @execution.completed_cell(output, 0, column)
                    is Some(Number(actual)) &&
                    actual == expected,
                  )
                }
                terminal = true
              }
              @local_veca.NearestFailed(@local_veca.NearestWorkLimit, work~, ..) => {
                assert_false(success)
                assert_eq(work, limit.to_int64())
                terminal = true
              }
              _ => fail("name scan produced an unrelated terminal state")
            }
          }
        }
        assert_true(terminal)
        assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
        assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
      }
    }
    // One identity slot plus the first read; Relation additionally rechecks
    // its scalar twice. After nine identity fragments, the Vector field
    // starts its component scan (plus five Relation Vector rechecks).
    for barrier in (if carrier { [3, 12] } else { [5, 19] }) {
      let control = @bounded.control()
      let active = start(control, required, workspace).unwrap()
      for _ in 0..<barrier {
        assert_true(
          @local_veca.advance_nearest(active, 1).unwrap()
          is @local_veca.NearestContinue(progress=0L, ..),
        )
      }
      assert_eq(@local_veca.nearest_name_offset(active), 64)
      assert_eq(
        @local_veca.cleanup_nearest(active),
        Err(@local_veca.NearestExecutionIssue(@bounded.NotStopped)),
      )
      assert_true(@bounded.request_cancel(control))
      assert_false(@local_veca.nearest_stopped(active))
      assert_true(
        @local_veca.advance_nearest(active, 1).unwrap()
        is @local_veca.NearestStopped(@bounded.Cancelled, work~, progress=0L) &&
        work == barrier.to_int64(),
      )
      assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
      assert_eq(@local_veca.nearest_name_offset(active), 0)
      assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
    }
    if candidate_material is Some(material) {
      assert_true(@carrier_runtime.material_available(material))
      assert_true(@carrier_runtime.reclaim_material(material))
    }
    if query_material is Some(material) {
      assert_true(@carrier_runtime.material_available(material))
      assert_true(@carrier_runtime.reclaim_material(material))
    }
  }
}

///|
test "nearest public name barrier retains Relation inputs until confirmed stop" {
  let candidates = nearest_named_source(2, false, unused=true)
  let queries = nearest_named_source(1, false, unused=true)
  let owner = nearest_named_owner(candidates, queries, false)
  let inputs = [candidates, queries].mapi((port, source) => {
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(
        owner,
        port,
        source,
        direct_nearest_relation_output(source),
      ).unwrap(),
      10,
      4000,
    ).unwrap()
  })
  let generated = task_test_generated(owner)
  let control = @bounded.control()
  // Array: 2*115+3=233; init/read/match add 3 ->236. Identity read,
  // scalar recheck and nine name fragments add 12 ->248. Component read
  // and five Vector rechecks reach 254 at offset64; poll256 is offset192.
  let active = @local_veca.start_nearest_inputs_with_control_work_limit(
    control,
    @execution.generated_completion_preparation(generated),
    @execution.generated_prepared_sequence(generated),
    0,
    @local_veca.nearest_relation_producer(inputs[0]),
    @local_veca.nearest_relation_producer(inputs[1]),
    10,
    { max_nodes: 116, max_text_bytes: 1000, max_depth: 2, max_work: 1000, },
    44,
    1000,
    2000,
    1000,
  ).unwrap()
  assert_true(
    @local_veca.advance_nearest(active, 256).unwrap()
    is @local_veca.NearestContinue(work=256L, progress=0L),
  )
  assert_eq(@local_veca.nearest_name_offset(active), 192)
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    @local_veca.cleanup_nearest(active),
    Err(@local_veca.NearestExecutionIssue(@bounded.NotStopped)),
  )
  for input in inputs {
    assert_true(@execution.producer_read_available(input))
  }
  assert_true(
    @local_veca.advance_nearest(active, 256).unwrap()
    is @local_veca.NearestStopped(@bounded.Cancelled, work=256L, progress=0L),
  )
  assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
  assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
  for input in inputs {
    assert_true(@execution.producer_read_available(input))
  }
}
