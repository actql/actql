///|
fn nearest_text_material(
  owner : @lower.BoundPrepared,
  prefix_length? : Int = 128,
) -> @carrier_runtime.Material {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    {
      ..carrier_vectors_storage_limits(),
      max_value_bytes: 10000,
      max_total_value_bytes: 20000,
      max_retained_value_bytes: 20000,
      max_contract_work: 10000,
      max_work: 20000,
    },
    20000L,
    fn() { true },
  ).unwrap()
  let contract = @value_contract.primitive(
    @value_contract.StringType,
    nullable=false,
  )
  for suffix in ["b", "a"] {
    let key = @admitted.checked_text_value(
      "x".repeat(prefix_length) + suffix,
      contract,
    ).unwrap()
    @records.append_record(output, [
      (@schema.Unqualified("id"), key),
      (@schema.Unqualified("embedding"), direct_nearest_vector("[1,2]")),
    ]).unwrap()
  }
  @records.completed_material(@records.finish_output(output).unwrap()).unwrap()
}

///|
test "nearest public quantum stops inside long identity validation" {
  let candidates = direct_nearest_vector_owner(text_identity=true)
  let queries = direct_nearest_vector_owner(text_identity=true)
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = nearest_text_material(candidates, prefix_length=512)
  let query_material = nearest_text_material(queries, prefix_length=512)
  let control = @bounded.control()
  let active = nearest_text_start(
    control,
    task_test_generated(owner),
    owner,
    candidates,
    queries,
    candidate_material,
    query_material,
    work=10000,
  ).unwrap()
  // The first record consumes five field/control units before its identity
  // needs 513 comparison units. A 256-unit resume cannot finish that scan.
  assert_true(
    @local_veca.advance_nearest(active, 256).unwrap()
    is @local_veca.NearestContinue(work=256L, progress=0L),
  )
  assert_eq(
    @local_veca.cleanup_nearest(active),
    Err(@local_veca.NearestExecutionIssue(@bounded.NotStopped)),
  )
  assert_true(@bounded.request_cancel(control))
  assert_false(@local_veca.nearest_stopped(active))
  assert_true(
    @local_veca.advance_nearest(active, 256).unwrap()
    is @local_veca.NearestStopped(@bounded.Cancelled, work=256L, progress=0L),
  )
  assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
  assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
  assert_false(@local_veca.nearest_cleanup_pending(active))
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
fn nearest_text_start(
  control : @bounded.Control,
  generated : @execution.GeneratedSequence,
  owner : @lower.BoundPrepared,
  candidates : @lower.BoundPrepared,
  queries : @lower.BoundPrepared,
  candidate_material : @carrier_runtime.Material,
  query_material : @carrier_runtime.Material,
  work? : Int = 1517,
  workspace? : Int = 44,
) -> Result[@local_veca.NearestExecution, @local_veca.NearestIssue] {
  let candidate_view = @carrier_runtime.material_prepare_view(
    candidate_material, owner, 0, candidates,
  ).unwrap()
  let query_view = @carrier_runtime.material_prepare_view(
    query_material, owner, 1, queries,
  ).unwrap()
  @local_veca.start_nearest_inputs_with_control_work_limit(
    control,
    @execution.generated_completion_preparation(generated),
    @execution.generated_prepared_sequence(generated),
    0,
    @local_veca.nearest_carrier_producer(candidate_view),
    @local_veca.nearest_carrier_producer(query_view),
    10,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    workspace,
    1000,
    1000,
    work,
  )
}

///|
test "nearest public quantum stops inside output after a committed row" {
  let candidates = direct_nearest_vector_owner(text_identity=true)
  let queries = direct_nearest_vector_owner(text_identity=true)
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = nearest_text_material(candidates, prefix_length=660)
  let query_material = nearest_text_material(queries, prefix_length=660)
  let control = @bounded.control()
  let active = nearest_text_start(
    control,
    task_test_generated(owner),
    owner,
    candidates,
    queries,
    candidate_material,
    query_material,
    work=50000,
  ).unwrap()
  // Four records at 669; four scratch slots; two 665-unit sorts and two
  // 662-unit duplicate checks: 5334. Scoring/tie-sort add 673. Each output
  // takes 71 polls (11 Text chunks per identity). First row ends at 6078;
  // quantum 24 ends at 6144 inside the next row's logical Text charge.
  for index in 0..<24 {
    guard @local_veca.advance_nearest(active, 256).unwrap()
      is @local_veca.NearestContinue(work~, progress~) else {
      fail("public output barrier must precede completion")
    }
    assert_eq(work, ((index + 1) * 256).to_int64())
    assert_eq(progress, if index == 23 { 1L } else { 0L })
  }
  assert_eq(
    @local_veca.cleanup_nearest(active),
    Err(@local_veca.NearestExecutionIssue(@bounded.NotStopped)),
  )
  assert_true(@bounded.request_cancel(control))
  assert_false(@local_veca.nearest_stopped(active))
  assert_true(
    @local_veca.advance_nearest(active, 256).unwrap()
    is @local_veca.NearestStopped(@bounded.Cancelled, work=6144L, progress=1L),
  )
  assert_true(@carrier_runtime.material_available(candidate_material))
  assert_true(@carrier_runtime.material_available(query_material))
  assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
  assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
  assert_false(@local_veca.nearest_cleanup_pending(active))
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "nearest long identities preserve independent control limits and order" {
  let candidates = direct_nearest_vector_owner(text_identity=true)
  let queries = direct_nearest_vector_owner(text_identity=true)
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = nearest_text_material(candidates)
  let query_material = nearest_text_material(queries)
  let generated = task_test_generated(owner)
  // Four records: 4 * (1 identity slot + 4 field/match units +
  // 129 validation units + 3 component checks) = 548.
  // Four scratch slots; two input sorts at 133; two uniqueness scans at
  // 130: 548 + 4 + 266 + 260 = 1078.
  // Each query: 2 score slots + 6 fold units + 133 tie-sort units +
  // 2 output rows at 39 units each = 219. Final completion: 1. Total: 1517.
  // Each output: two identity picks + row start + 18 read/recheck units +
  // charge start + four names + two five-unit Text charges + two scalars +
  // commit = 39. The last Text chunk completes measurement in that poll.
  // Workspace: 12 input record slots + 8 score slots + 6 record scratch
  // slots + 2 identity slots + 16 fixed slots = 44.
  for quantum in [1, 7, 256] {
    let candidate_view = @carrier_runtime.material_prepare_view(
      candidate_material, owner, 0, candidates,
    ).unwrap()
    let query_view = @carrier_runtime.material_prepare_view(
      query_material, owner, 1, queries,
    ).unwrap()
    let active = @local_veca.start_nearest_inputs_with_control_work_limit(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_carrier_producer(candidate_view),
      @local_veca.nearest_carrier_producer(query_view),
      10,
      // Four rows: five nodes each; names use 29 bytes and the two
      // identities use 258 bytes. Logical work is 20 + 4 * 287 = 1168.
      { max_nodes: 20, max_text_bytes: 1148, max_depth: 2, max_work: 1168, },
      44,
      1000,
      1000,
      1517,
    ).unwrap()
    let mut finished = false
    let mut polls = 0
    while !finished && polls < 1600 {
      polls += 1
      match @local_veca.advance_nearest(active, quantum).unwrap() {
        @local_veca.NearestContinue(..) => ()
        @local_veca.NearestComplete(output, work~, ..) => {
          assert_eq(work, 1517L)
          assert_eq(@execution.completed_row_count(output), 4)
          for row in 0..<4 {
            for column, name in ["candidate_id", "query_id", "rank", "score"] {
              assert_eq(
                @execution.completed_column_name(output, column),
                Some(name),
              )
              let cell = @execution.completed_cell(output, row, column).unwrap()
              match name {
                "candidate_id" | "query_id" => {
                  let index = if name == "candidate_id" {
                    row % 2
                  } else {
                    row / 2
                  }
                  let suffix = if index == 0 { "a" } else { "b" }
                  assert_true(
                    cell is Text(text) && text == "x".repeat(128) + suffix,
                  )
                }
                "rank" =>
                  assert_true(
                    cell is Number(value) && value == (row % 2 + 1).to_double(),
                  )
                "score" => assert_true(cell is Number(5.0))
                _ => fail("unexpected nearest output")
              }
            }
          }
          finished = true
        }
        _ => fail("nearest must complete at its independent exact limit")
      }
    }
    assert_true(finished)
    assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
  }
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "nearest output yields during recheck and charge without premature release" {
  let candidates = direct_nearest_vector_owner(text_identity=true)
  let queries = direct_nearest_vector_owner(text_identity=true)
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = nearest_text_material(candidates)
  let query_material = nearest_text_material(queries)
  let generated = task_test_generated(owner)
  // Prelude 1078 + score setup/fold 8 + tie-sort 133 = 1219.
  // The first output occupies 39 polls, ending at 1258. These barriers
  // interrupt its Text recheck/measurement and the next row's recheck.
  for (barrier, expected_progress) in [(1232, 0L), (1250, 0L), (1270, 1L)] {
    let control = @bounded.control()
    let active = nearest_text_start(
      control, generated, owner, candidates, queries, candidate_material, query_material,
    ).unwrap()
    let mut progress = 0L
    for _ in 0..<barrier {
      guard @local_veca.advance_nearest(active, 1).unwrap()
        is @local_veca.NearestContinue(work~, progress=observed) else {
        fail("output barrier must precede whole-output completion")
      }
      assert_true(work <= barrier.to_int64())
      progress = observed
    }
    assert_eq(progress, expected_progress)
    assert_eq(
      @local_veca.cleanup_nearest(active),
      Err(@local_veca.NearestExecutionIssue(@bounded.NotStopped)),
    )
    assert_true(@bounded.request_cancel(control))
    assert_false(@local_veca.nearest_stopped(active))
    assert_true(@carrier_runtime.material_available(candidate_material))
    assert_true(@carrier_runtime.material_available(query_material))
    guard @local_veca.advance_nearest(active, 1).unwrap()
      is @local_veca.NearestStopped(
        @bounded.Cancelled,
        work~,
        progress=observed
      ) else {
      fail("partial row must not turn cancellation into completion")
    }
    assert_eq(work, barrier.to_int64())
    assert_eq(observed, expected_progress)
    assert_true(@local_veca.nearest_cleanup_pending(active))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
    assert_false(@local_veca.nearest_cleanup_pending(active))
    assert_true(@carrier_runtime.material_available(candidate_material))
    assert_true(@carrier_runtime.material_available(query_material))
  }
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "nearest long identities reject one-short control and workspace" {
  let candidates = direct_nearest_vector_owner(text_identity=true)
  let queries = direct_nearest_vector_owner(text_identity=true)
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = nearest_text_material(candidates)
  let query_material = nearest_text_material(queries)
  let generated = task_test_generated(owner)
  assert_true(
    nearest_text_start(
      @bounded.control(),
      generated,
      owner,
      candidates,
      queries,
      candidate_material,
      query_material,
      workspace=43,
    )
    is Err(@local_veca.NearestWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    let active = nearest_text_start(
      @bounded.control(),
      generated,
      owner,
      candidates,
      queries,
      candidate_material,
      query_material,
      work=1516,
    ).unwrap()
    let mut failed = false
    let mut polls = 0
    while !failed && polls < 1600 {
      polls += 1
      match @local_veca.advance_nearest(active, quantum).unwrap() {
        @local_veca.NearestContinue(..) => ()
        @local_veca.NearestFailed(@local_veca.NearestWorkLimit, work=1516L, ..) =>
          failed = true
        _ => fail("nearest one-short must preserve its typed failure")
      }
    }
    assert_true(failed)
    assert_true(@local_veca.nearest_stopped(active))
    assert_true(@local_veca.nearest_cleanup_pending(active))
    assert_true(@carrier_runtime.material_available(candidate_material))
    assert_true(@carrier_runtime.material_available(query_material))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
    assert_false(@local_veca.nearest_cleanup_pending(active))
  }
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}

///|
test "nearest long identity scans retain both inputs until confirmed stop" {
  let candidates = direct_nearest_vector_owner(text_identity=true)
  let queries = direct_nearest_vector_owner(text_identity=true)
  let owner = direct_nearest_owner(candidates, queries)
  let candidate_material = nearest_text_material(candidates)
  let query_material = nearest_text_material(queries)
  let generated = task_test_generated(owner)
  // Fixed phase totals place these barriers inside self-validation,
  // record sorting, duplicate checking and score tie comparison.
  for barrier in [40, 320, 450, 1120] {
    let control = @bounded.control()
    let active = nearest_text_start(
      control, generated, owner, candidates, queries, candidate_material, query_material,
    ).unwrap()
    for _ in 0..<barrier {
      assert_true(
        @local_veca.advance_nearest(active, 1).unwrap()
        is @local_veca.NearestContinue(progress=0L, ..),
      )
    }
    assert_eq(
      @local_veca.cleanup_nearest(active),
      Err(@local_veca.NearestExecutionIssue(@bounded.NotStopped)),
    )
    assert_true(@bounded.request_cancel(control))
    assert_false(@local_veca.nearest_stopped(active))
    assert_true(@carrier_runtime.material_available(candidate_material))
    assert_true(@carrier_runtime.material_available(query_material))
    guard @local_veca.advance_nearest(active, 1).unwrap()
      is @local_veca.NearestStopped(@bounded.Cancelled, work~, progress=0L) else {
      fail("scan must stop without completing output")
    }
    assert_eq(work, barrier.to_int64())
    assert_true(@local_veca.nearest_cleanup_pending(active))
    assert_true(@carrier_runtime.material_available(candidate_material))
    assert_true(@carrier_runtime.material_available(query_material))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
    assert_false(@local_veca.nearest_cleanup_pending(active))
    assert_true(@carrier_runtime.material_available(candidate_material))
    assert_true(@carrier_runtime.material_available(query_material))
  }
  assert_true(@carrier_runtime.reclaim_material(candidate_material))
  assert_true(@carrier_runtime.reclaim_material(query_material))
}
