///|
fn composite_nearest_relation(rows : String) -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{" +
        "\"id\":{\"type\":\"number\",\"nullable\":false}," +
        "\"tenant\":{\"type\":\"string\",\"nullable\":false}," +
        "\"embedding\":{\"type\":\"vector\",\"dimensions\":2," +
        "\"nullable\":false}},\"rows\":" +
        rows +
        "}}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn composite_nearest_bridge(
  source : @lower.BoundPrepared,
  tenant_first : Bool,
) -> @lower.BoundPrepared {
  let roles = if tenant_first {
    "\"tenant\",\"id\""
  } else {
    "\"id\",\"tenant\""
  }
  direct_nearest_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{\"id\":[" +
        roles +
        "],\"vector\":\"embedding\"}}]",
      ),
      [
        (
          "rows",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(source)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn composite_nearest_bridge_output(
  source_owner : @lower.BoundPrepared,
  source : @execution.CompletedOutput,
  owner : @lower.BoundPrepared,
) -> @records.Completed raise {
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    10,
    1000,
  ).unwrap()
  let active = @local_bridge.start_rows_to_vectors(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    input,
    carrier_vectors_storage_limits(),
    4096L,
    () => @execution.completed_output_available(source),
  ).unwrap()
  let mut completed = None
  for _ in 0..<10000 {
    if completed is None {
      match @local_bridge.advance_rows_to_vectors(active, 1).unwrap() {
        @local_bridge.Continue(..) => ()
        @local_bridge.Complete(output, ..) => completed = Some(output)
        _ => fail("original Relation Bridge must complete")
      }
    }
  }
  assert_true(completed is Some(_))
  assert_eq(@local_bridge.cleanup_rows_to_vectors(active), Ok(true))
  assert_eq(@local_bridge.cleanup_rows_to_vectors(active), Ok(false))
  assert_true(@execution.completed_output_available(source))
  completed.unwrap()
}

///|
fn composite_nearest_assert_identity(
  output : @execution.CompletedOutput,
  row : Int,
  column : Int,
  id : Double,
  tenant : String,
  tenant_first : Bool,
) -> Unit raise {
  guard @execution.completed_cell(output, row, column)
    is Some(Captured(@admitted.Object(fields))) else {
    fail("composite identity must keep its original typed tuple")
  }
  assert_true(@admitted.element_at(fields, 2) is None)
  for index in 0..<2 {
    guard @admitted.element_at(fields, index) is Some((name, value)) else {
      fail("missing original identity component")
    }
    assert_eq(name, index.to_string())
    if (index == 0) == tenant_first {
      assert_true(value is @admitted.Text(actual) && actual == tenant)
    } else {
      assert_true(value is @admitted.Number(actual) && actual == id)
    }
  }
}

///|
test "Relation composite Bridge reaches nearest with complete typed identities and ties" {
  let candidates = composite_nearest_relation(
    "[{\"id\":1,\"tenant\":\"z\",\"embedding\":[1,0]}," +
    "{\"id\":1,\"tenant\":\"a\",\"embedding\":[1,0]}," +
    "{\"id\":2,\"tenant\":\"b\",\"embedding\":[0,1]}]",
  )
  let queries = composite_nearest_relation(
    "[{\"id\":10,\"tenant\":\"x\",\"embedding\":[1,0]}," +
    "{\"id\":10,\"tenant\":\"y\",\"embedding\":[0,1]}]",
  )
  let candidate_source = direct_nearest_relation_output(candidates)
  let query_source = direct_nearest_relation_output(queries)
  for tenant_first in [false, true] {
    let candidate_bridge = composite_nearest_bridge(candidates, tenant_first)
    let query_bridge = composite_nearest_bridge(queries, tenant_first)
    let candidate_records = composite_nearest_bridge_output(
      candidates, candidate_source, candidate_bridge,
    )
    let query_records = composite_nearest_bridge_output(
      queries, query_source, query_bridge,
    )
    let candidate_material = @records.completed_material(candidate_records).unwrap()
    let query_material = @records.completed_material(query_records).unwrap()
    let owner = direct_nearest_owner(candidate_bridge, query_bridge)
    let generated = task_test_generated(owner)
    let mut prior_work = None
    for quantum in [1, 7] {
      let active = nearest_text_start(
        @bounded.control(),
        generated,
        owner,
        candidate_bridge,
        query_bridge,
        candidate_material,
        query_material,
        work=10000,
        workspace=1000,
      ).unwrap()
      let mut complete = false
      for _ in 0..<10000 {
        if !complete {
          match @local_veca.advance_nearest(active, quantum).unwrap() {
            @local_veca.NearestContinue(..) => ()
            @local_veca.NearestComplete(output, work~, ..) => {
              assert_eq(@execution.completed_row_count(output), 4)
              for
                row, (id, tenant, query_tenant, rank, score) in [
                  (1.0, "a", "x", 1.0, 1.0),
                  (1.0, "z", "x", 2.0, 1.0),
                  (2.0, "b", "y", 1.0, 1.0),
                  (1.0, "a", "y", 2.0, 0.0),
                ] {
                composite_nearest_assert_identity(
                  output, row, 0, id, tenant, tenant_first,
                )
                composite_nearest_assert_identity(
                  output, row, 1, 10.0, query_tenant, tenant_first,
                )
                assert_true(
                  @execution.completed_cell(output, row, 2)
                  is Some(Number(actual)) &&
                  actual == rank,
                )
                assert_true(
                  @execution.completed_cell(output, row, 3)
                  is Some(Number(actual)) &&
                  actual == score,
                )
              }
              if prior_work is Some(prior) {
                assert_eq(work, prior)
              }
              prior_work = Some(work)
              complete = true
            }
            _ => fail("composite Relation nearest must complete")
          }
        }
      }
      assert_true(complete)
      assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
      assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
      assert_true(@records.completed_available(candidate_records))
      assert_true(@records.completed_available(query_records))
    }
    assert_true(@records.discard_completed(candidate_records))
    assert_true(@records.discard_completed(query_records))
  }
  assert_true(@execution.completed_output_available(candidate_source))
  assert_true(@execution.completed_output_available(query_source))
}

///|
test "Relation composite nearest retains originals through current refusal and stop" {
  let source_owner = composite_nearest_relation(
    "[{\"id\":1,\"tenant\":\"a\",\"embedding\":[1,0]}]",
  )
  let original = direct_nearest_relation_output(source_owner)
  for cancelled in [false, true] {
    let current = Ref(true)
    let source = @execution.restrict_completed_output(original, () => {
      current.val
    })
    let bridge = composite_nearest_bridge(source_owner, false)
    let records = composite_nearest_bridge_output(source_owner, source, bridge)
    let material = @records.completed_material(records).unwrap()
    let owner = direct_nearest_owner(bridge, bridge)
    let control = @bounded.control()
    let active = nearest_text_start(
      control,
      task_test_generated(owner),
      owner,
      bridge,
      bridge,
      material,
      material,
      work=10000,
      workspace=1000,
    ).unwrap()
    assert_true(
      @local_veca.advance_nearest(active, 1).unwrap()
      is @local_veca.NearestContinue(..),
    )
    if cancelled {
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_veca.advance_nearest(active, 1).unwrap()
        is @local_veca.NearestStopped(@bounded.Cancelled, ..),
      )
    } else {
      current.val = false
      assert_true(
        @local_veca.advance_nearest(active, 1).unwrap()
        is @local_veca.NearestFailed(@local_veca.NearestInputUnavailable, ..),
      )
    }
    assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
    assert_false(@local_veca.nearest_cleanup_pending(active))
    assert_true(@execution.completed_output_available(original))
    assert_true(@records.discard_completed(records))
  }
}
