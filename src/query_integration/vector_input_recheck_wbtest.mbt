///|
fn vector_input_recheck_owner(
  id : Int,
  pooling? : Bool = false,
  object_names? : Bool = false,
  unused_items? : Int = 257,
  group_name? : String = "group",
  unused_name? : String = "zz_unused",
) -> @lower.BoundPrepared {
  let name = String::make(130, 'x')
  let unused_schema = if object_names {
    let object = "{\"type\":\"object\",\"nullable\":false," +
      "\"fields\":{\"" +
      name +
      "\":{\"type\":\"number\",\"nullable\":false}}}"
    "\"aa_unused\":{\"type\":\"array\",\"nullable\":false,\"max_items\":112," +
    "\"items\":{\"type\":\"number\",\"nullable\":false}},\"zz_unused\":" +
    object
  } else {
    "\"" +
    unused_name +
    "\":{\"type\":\"array\",\"nullable\":false,\"max_items\":" +
    unused_items.to_string() +
    "," +
    "\"items\":{\"type\":\"number\",\"nullable\":false}}"
  }
  let unused_values = if object_names {
    "\"aa_unused\":[" +
    Array::make(112, "1").join(",") +
    "],\"zz_unused\":{\"" +
    name +
    "\":2}"
  } else {
    "\"" + unused_name + "\":[" + Array::make(unused_items, "1").join(",") + "]"
  }
  let group_schema = if pooling {
    "\"" + group_name + "\":{\"type\":\"number\",\"nullable\":false},"
  } else {
    ""
  }
  let group_value = if pooling { "\"" + group_name + "\":1," } else { "" }
  let keyed = if pooling {
    ",{\"from\":\"rows\",\"assert_rows\":{\"unique_by\":[\"id\"]}}"
  } else {
    ""
  }
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{" +
        group_schema +
        "\"id\":{\"type\":\"number\",\"nullable\":false}," +
        "\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}," +
        unused_schema +
        "},\"rows\":[{" +
        group_value +
        "\"id\":" +
        id.to_string() +
        ",\"embedding\":[1,2]," +
        unused_values +
        "}]},\"as\":\"rows\"}" +
        keyed +
        "]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
test "nearest Relation admission yields within unused arrays before stop" {
  let candidates = vector_input_recheck_owner(1)
  let queries = vector_input_recheck_owner(10)
  let owner = direct_nearest_owner(
    candidates,
    queries,
    candidate_relation=true,
    query_relation=true,
  )
  let inputs = [
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(
        owner,
        0,
        candidates,
        direct_nearest_relation_output(candidates),
      ).unwrap(),
      10,
      1000,
    ).unwrap(),
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(
        owner,
        1,
        queries,
        direct_nearest_relation_output(queries),
      ).unwrap(),
      10,
      1000,
    ).unwrap(),
  ]
  let generated = task_test_generated(owner)
  // Existing one-record-per-side nearest: 52. Two extra field/match pairs:
  // 4. Each side adds scalar 2, Vector 5 and Array 2*257+3=517 polls.
  // Total 52+4+2*(2+5+517)=1104, independent of a measured execution.
  // Existing structural 32 plus eight cursor slots and depth-two frames
  // (2+2) gives 44. Values remain subject to the 258-node Array limit.
  assert_true(
    @local_veca.start_nearest_inputs_with_control_work_limit(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(inputs[0]),
      @local_veca.nearest_relation_producer(inputs[1]),
      10,
      { max_nodes: 258, max_text_bytes: 1000, max_depth: 2, max_work: 1000, },
      43,
      1000,
      1000,
      1104,
    )
    is Err(@local_veca.NearestWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    for (limit, success) in [(1104, true), (1103, false)] {
      let active = @local_veca.start_nearest_inputs_with_control_work_limit(
        @bounded.control(),
        @execution.generated_completion_preparation(generated),
        @execution.generated_prepared_sequence(generated),
        0,
        @local_veca.nearest_relation_producer(inputs[0]),
        @local_veca.nearest_relation_producer(inputs[1]),
        10,
        { max_nodes: 258, max_text_bytes: 1000, max_depth: 2, max_work: 1000, },
        44,
        1000,
        1000,
        limit,
      ).unwrap()
      let mut terminal = false
      for _ in 0..<1120 {
        if !terminal {
          match @local_veca.advance_nearest(active, quantum).unwrap() {
            @local_veca.NearestContinue(..) => ()
            @local_veca.NearestComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 1104L)
              assert_eq(@execution.completed_row_count(output), 1)
              assert_true(
                @execution.completed_cell(output, 0, 0) is Some(Number(1.0)),
              )
              assert_true(
                @execution.completed_cell(output, 0, 1) is Some(Number(10.0)),
              )
              assert_true(
                @execution.completed_cell(output, 0, 2) is Some(Number(1.0)),
              )
              assert_true(
                @execution.completed_cell(output, 0, 3) is Some(Number(5.0)),
              )
              terminal = true
            }
            @local_veca.NearestFailed(@local_veca.NearestWorkLimit, work~, ..) => {
              assert_false(success)
              assert_eq(work, 1103L)
              terminal = true
            }
            _ => fail("nearest nested input has an unrelated failure")
          }
        }
      }
      assert_true(terminal)
      assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
      assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
      assert_true(@execution.producer_read_available(inputs[0]))
      assert_true(@execution.producer_read_available(inputs[1]))
    }
  }
  let control = @bounded.control()
  let active = @local_veca.start_nearest_inputs_with_control_work_limit(
    control,
    @execution.generated_completion_preparation(generated),
    @execution.generated_prepared_sequence(generated),
    0,
    @local_veca.nearest_relation_producer(inputs[0]),
    @local_veca.nearest_relation_producer(inputs[1]),
    10,
    { max_nodes: 258, max_text_bytes: 1000, max_depth: 2, max_work: 1000, },
    44,
    1000,
    1000,
    1104,
  ).unwrap()
  assert_true(
    @local_veca.advance_nearest(active, 256).unwrap()
    is @local_veca.NearestContinue(work=256L, progress=0L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    @local_veca.cleanup_nearest(active),
    Err(@local_veca.NearestExecutionIssue(@bounded.NotStopped)),
  )
  assert_true(@execution.producer_read_available(inputs[0]))
  assert_true(@execution.producer_read_available(inputs[1]))
  let short_nodes = @local_veca.start_nearest_inputs_with_control_work_limit(
    @bounded.control(),
    @execution.generated_completion_preparation(generated),
    @execution.generated_prepared_sequence(generated),
    0,
    @local_veca.nearest_relation_producer(inputs[0]),
    @local_veca.nearest_relation_producer(inputs[1]),
    10,
    { max_nodes: 257, max_text_bytes: 1000, max_depth: 2, max_work: 1000, },
    44,
    1000,
    1000,
    1104,
  ).unwrap()
  let mut rejected = false
  for _ in 0..<1120 {
    if !rejected {
      match @local_veca.advance_nearest(short_nodes, 1).unwrap() {
        @local_veca.NearestContinue(..) => ()
        @local_veca.NearestFailed(issue, ..) => {
          assert_eq(issue, @local_veca.InvalidNearestRecord(false, 0))
          rejected = true
        }
        _ => fail("short input-node allowance must not complete nearest")
      }
    }
  }
  assert_true(rejected)
  assert_eq(@local_veca.cleanup_nearest(short_nodes), Ok(true))
  assert_true(@execution.producer_read_available(inputs[0]))
  assert_true(@execution.producer_read_available(inputs[1]))
  assert_true(
    @local_veca.advance_nearest(active, 1).unwrap()
    is @local_veca.NearestStopped(@bounded.Cancelled, work=256L, progress=0L),
  )
  assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
  assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
  assert_true(@execution.producer_read_available(inputs[0]))
  assert_true(@execution.producer_read_available(inputs[1]))
}

///|
test "Relation Pool admission yields within unused arrays before stop" {
  let source = vector_input_recheck_owner(1, pooling=true)
  let owner = direct_relation_pool_owner(source)
  let completed = match
    @execution.execute_generated_sequence(
      task_test_generated(source),
      [],
      compute_test_limits(),
    ) {
    Ok(completed) => completed
    Err(@execution.UnsupportedRowComparison(step, name)) =>
      fail(
        "Pool source row comparison at " +
        step.to_string() +
        ": " +
        @schema.reference_name(name),
      )
    Err(@execution.Rows(step, _)) =>
      fail("Pool source Rows at " + step.to_string())
    Err(@execution.Capture(step, _)) =>
      fail("Pool source Capture at " + step.to_string())
    Err(@execution.MissingFragmentContext(step)) =>
      fail("Pool source fragment at " + step.to_string())
    Err(_) => fail("Pool source construction rejected before input admission")
  }
  let read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(
      owner,
      0,
      source,
      @execution.completed_output(completed, @pipeline.Step(1)).unwrap(),
    ).unwrap(),
    14,
    1000,
  ).unwrap()
  // Original 32 plus one extra field/group/identity scan (3), two scalar
  // rechecks (4), Vector (5), Array (517): 561. Append polls add 31: 592.
  // Workspace 18+8+3+2=31 plus append 16+9+1+3*3=35 and name offset: 67.
  // Depth three also admits the existing stored-record outer array,
  // field tuple and Vector envelope; depth two fails Store encoding.
  assert_true(
    @local_veca.start_relation_pool(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      read,
      {
        ..direct_relation_pool_limits(66, 592),
        max_value_depth: 3,
        max_value_nodes: 258,
      },
      4096L,
      fn() { true },
    )
    is Err(@local_veca.PoolWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    for (limit, success) in [(592, true), (591, false)] {
      let active = @local_veca.start_relation_pool(
        @bounded.control(),
        prepared_sequence(owner),
        0,
        read,
        {
          ..direct_relation_pool_limits(67, limit),
          max_value_depth: 3,
          max_value_nodes: 258,
        },
        4096L,
        fn() { true },
      ).unwrap()
      let mut terminal = false
      for _ in 0..<610 {
        if !terminal {
          match @local_veca.advance_pool(active, quantum).unwrap() {
            @local_veca.PoolContinue(..) => ()
            @local_veca.PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 592L)
              let storage = @records.completed_storage(output).unwrap()
              assert_eq(@record_storage.record_count(storage), 1)
              let field = @record_storage.record_field_at(storage, 0, 0).unwrap()
              assert_eq(@schema.reference_name(field.0), "embedding")
              guard field.1.value is @admitted.Vector(vector) else {
                fail("Pool output must retain the typed vector")
              }
              assert_eq(@admitted.element_count(vector), 2)
              assert_eq(@admitted.element_at(vector, 0), Some(1.0))
              assert_eq(@admitted.element_at(vector, 1), Some(2.0))
              terminal = true
            }
            @local_veca.PoolFailed(issue, work~, ..) => {
              assert_eq(issue, @local_veca.PoolWorkLimit)
              assert_false(success)
              assert_eq(work, 591L)
              terminal = true
            }
            _ => fail("Pool nested input has an unrelated failure")
          }
        }
      }
      assert_true(terminal)
      assert_eq(@local_veca.cleanup_pool(active), Ok(true))
      assert_eq(@local_veca.cleanup_pool(active), Ok(false))
      assert_true(@execution.producer_read_available(read))
    }
  }
  let control = @bounded.control()
  let active = @local_veca.start_relation_pool(
    control,
    prepared_sequence(owner),
    0,
    read,
    {
      ..direct_relation_pool_limits(67, 592),
      max_value_depth: 3,
      max_value_nodes: 258,
    },
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    @local_veca.advance_pool(active, 256).unwrap()
    is @local_veca.PoolContinue(work=256L, progress=0L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    @local_veca.cleanup_pool(active),
    Err(@local_veca.PoolExecutionIssue(@bounded.NotStopped)),
  )
  assert_true(@execution.producer_read_available(read))
  let short_nodes = @local_veca.start_relation_pool(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    read,
    {
      ..direct_relation_pool_limits(67, 592),
      max_value_depth: 3,
      max_value_nodes: 257,
    },
    4096L,
    fn() { true },
  ).unwrap()
  let mut rejected = false
  for _ in 0..<610 {
    if !rejected {
      match @local_veca.advance_pool(short_nodes, 1).unwrap() {
        @local_veca.PoolContinue(..) => ()
        @local_veca.PoolFailed(issue, ..) => {
          assert_eq(issue, @local_veca.InvalidPoolRecord(0))
          rejected = true
        }
        _ => fail("short input-node allowance must not complete Pool")
      }
    }
  }
  assert_true(rejected)
  assert_eq(@local_veca.cleanup_pool(short_nodes), Ok(true))
  assert_true(@execution.producer_read_available(read))
  assert_true(
    @local_veca.advance_pool(active, 1).unwrap()
    is @local_veca.PoolStopped(@bounded.Cancelled, work=256L, progress=0L),
  )
  assert_eq(@local_veca.cleanup_pool(active), Ok(true))
  assert_eq(@local_veca.cleanup_pool(active), Ok(false))
  assert_true(@execution.producer_read_available(read))
}
