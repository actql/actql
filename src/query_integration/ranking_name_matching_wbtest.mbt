///|
fn ranking_name_bind(
  checked : @pipeline.CheckedPipeline,
) -> @lower.BoundPrepared {
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn ranking_name_source(
  names : Array[String],
  unused? : Int? = None,
  scored? : Bool = false,
) -> @lower.BoundPrepared {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let fields = names.map(name => (@schema.Unqualified(name), Some(number)))
  let selected = names.copy()
  if unused is Some(count) {
    selected.push("aa_unused")
    fields.push(
      (
        @schema.Unqualified("aa_unused"),
        Some(
          @value_contract.array_contract(
            number,
            nullable=false,
            max_items=Some(count.to_int64()),
          ).unwrap(),
        ),
      ),
    )
  }
  let carrier = @carrier_contract.relation(
    @carrier_contract.rows(
      fields,
      field_set=@carrier_contract.Closed,
      max_fields=selected.length(),
      max_name_bytes=10000,
    ).unwrap(),
  )
  let ranking = if scored {
    @vector.declare_ranking_score(
      input_cursor(
        "{\"domain\":\"unit.v1\",\"normalization\":\"unit.v1\",\"range\":[0,1]}",
      ),
      carrier,
      @schema.Unqualified("rank"),
      { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
    ).unwrap()
  } else {
    @vector.ranking_relation(carrier)
  }
  ranking_name_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"select\":[" +
        selected.map(name => "\"" + name + "\"").join(",") +
        "]}]",
      ),
      [("rows", @pipeline.RankingInput(ranking))],
      None,
      Some(input_cursor("\"rows\"")),
      {
        max_steps: 10,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn ranking_name_owner(
  source : @lower.BoundPrepared,
  groups : Array[String],
  candidate : String,
  rank : String,
  tie? : String? = None,
) -> @lower.BoundPrepared {
  let produced = @pipeline.ProducedInput(
    @pipeline.produced_input(
      @lower.pipeline(@lower.bound_preparation(source)),
      @pipeline.Step(0),
    ).unwrap(),
  )
  ranking_name_bind(
    @pipeline.check_with_evidence(
      input_cursor(
        "[{\"merge_rankings\":{\"with\":\"right\",\"by\":[" +
        groups.map(name => "\"" + name + "\"").join(",") +
        "],\"candidate\":\"" +
        candidate +
        (if tie is Some(_) { "\",\"score\":\"" } else { "\",\"rank\":\"" }) +
        rank +
        "\",\"k\":2," +
        (match tie {
          Some(name) => "\"tie_break\":[\"" + name + "\"],"
          None => ""
        }) +
        (if tie is Some(_) {
          "\"score_policy\":{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}," +
          "\"score_contract\":{\"domain\":\"unit.v1\",\"normalization\":\"unit.v1\",\"range\":[0,1]}}}]"
        } else {
          "\"score_policy\":{\"rrf\":{\"rank_constant\":1," +
          "\"weights\":[1,1],\"rank_window\":2}}}}]"
        }),
      ),
      [("left", produced), ("right", produced)],
      None,
      Some(input_cursor("\"left\"")),
      {
        max_steps: 10,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn ranking_name_output(
  source : @lower.BoundPrepared,
  candidate : String,
  rank : String,
  empty : Bool,
  unused? : Int? = None,
) -> @execution.CompletedOutput raise {
  let output = @execution.prepare_admitted_output(
    source,
    @pipeline.Step(0),
    10,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
  ).unwrap()
  if !empty {
    let schema = @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(source)),
      @pipeline.Step(0),
    ).unwrap()
    let values = Array::makei(@schema.field_count(schema), column => {
      let name = @schema.reference_name(
        @schema.field_at(schema, column).unwrap().name,
      )
      if name == "aa_unused" {
        let raw = @admitted.array_value(
          Array::make(unused.unwrap(), @admitted.number_value(1.0).unwrap()),
        )
        return @admitted.recheck_runtime_value(
          raw,
          @schema.field_at(schema, column).unwrap().contract,
          { max_nodes: 1000, max_text_bytes: 10000, max_depth: 10, },
        ).unwrap()
      }
      direct_ranking_number(
        source,
        column,
        if name == candidate || name == rank {
          1.0
        } else {
          7.0
        },
      )
    })
    @execution.append_admitted_output(output, values).unwrap()
  }
  let rows = @execution.finish_admitted_output(output).unwrap()
  let port = @execution.prepare_trusted_output_port(
    task_test_completion(source),
    @pipeline.Step(0),
    1000,
    10000,
    (proof : @execution.AdmittedOutputRows) => {
      if physical_equal(proof, rows) {
        Some(rows)
      } else {
        None
      }
    },
  ).unwrap()
  @execution.complete_trusted_output(port, rows).unwrap()
}

///|
test "ranking reference matching bounds wide and overlapping role lists" {
  for overlapping in [false, true] {
    let groups = if overlapping {
      [String::make(513, 'z')]
    } else {
      Array::makei(9, index => "g" + index.to_string())
    }
    let source = ranking_name_source(
      groups + ["id", "rank"],
      scored=overlapping,
    )
    let owner = ranking_name_owner(
      source,
      groups,
      "id",
      "rank",
      tie=if overlapping { Some(groups[0]) } else { None },
    )
    let populated = ranking_name_output(source, "id", "rank", false)
    let empty = ranking_name_output(source, "id", "rank", true)
    let inputs = [populated, empty].mapi((index, output) => {
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(owner, index, source, output).unwrap(),
        1000,
        10000,
      ).unwrap()
    })
    // Nine groups: initialization 9 + eleven (read/recheck + extra role-list
    // poll) = 44 + validation/store 12 + scratch/validation/fusion 12 +
    // output/finalization 122 (including 1+...+9 group probes) = 199.
    // Weighted overlap removes one RRF scratch poll and two rank validations
    // from 56, adds tie initialization/validation 2, then 16 continued input
    // fragments + 8 output fragments + 9 name-measurement polls = 88.
    let work = if overlapping { 88 } else { 199 }
    // Records/scratch, outputs/scratch, ports, fixed, row scope, depth scope.
    let slots = if overlapping {
      11 + 8 + 6 + 50 + 6 + 12
    } else {
      18 + 15 + 6 + 57 + 14 + 12
    }
    for (quantum, limit) in [(1, work), (7, work), (256, work), (1, work - 1)] {
      let active = @local_veca.start_ranking(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        inputs,
        10,
        {
          max_nodes: 1000,
          max_text_bytes: 10000,
          max_depth: 10,
          max_work: 10000,
        },
        slots,
        1000,
        10000,
        control_work_limit=Some(limit),
      ).unwrap()
      let mut done = false
      for _ in 0..<1000 {
        if done {
          break
        }
        match @local_veca.advance_ranking(active, quantum).unwrap() {
          @local_veca.RankingContinue(..) => ()
          @local_veca.RankingComplete(output, work=charged, ..) => {
            assert_eq(limit, work)
            assert_eq(charged, work.to_int64())
            assert_eq(@execution.completed_row_count(output), 1)
            let schema = @pipeline.schema_at(
              @lower.pipeline(@lower.bound_preparation(owner)),
              @pipeline.Step(0),
            ).unwrap()
            for column in 0..<@schema.field_count(schema) {
              let name = @schema.reference_name(
                @schema.field_at(schema, column).unwrap().name,
              )
              let expected = if groups.contains(name) {
                7.0
              } else if name == "score" {
                0.5
              } else {
                1.0
              }
              assert_true(
                @execution.completed_cell(output, 0, column)
                is Some(Number(actual)) &&
                actual == expected,
              )
            }
            done = true
          }
          @local_veca.RankingFailed(
            @local_veca.RankingWorkLimit,
            work=charged,
            ..
          ) => {
            assert_eq(limit, work - 1)
            assert_eq(charged, limit.to_int64())
            done = true
          }
          _ => fail("wide or overlapping reference matching")
        }
      }
      assert_true(done)
      assert_eq(@local_veca.cleanup_ranking(active), Ok(true))
    }
    assert_true(
      @local_veca.start_ranking(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        inputs,
        10,
        {
          max_nodes: 1000,
          max_text_bytes: 10000,
          max_depth: 10,
          max_work: 10000,
        },
        slots - 1,
        1000,
        10000,
      )
      is Err(@local_veca.RankingWorkspaceLimit),
    )
  }
}

///|
test "ranking public name barrier has independent work workspace and stop custody" {
  let group = String::make(513, 'z')
  let source = ranking_name_source([group, "id", "rank"], unused=Some(118))
  let owner = ranking_name_owner(source, [group], "id", "rank")
  let populated = ranking_name_output(
    source,
    "id",
    "rank",
    false,
    unused=Some(118),
  )
  let empty = ranking_name_output(source, "id", "rank", true, unused=Some(118))
  let inputs = [populated, empty].mapi((index, output) => {
    @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, index, source, output).unwrap(),
      1000,
      10000,
    ).unwrap()
  })
  // Baseline 56 + unused read/recheck (1+2*118+3) + input/output fragments
  // 16 + shared long-name charge 9 = 321. Depth two changes 90 to 82 slots.
  for (quantum, work) in [(1, 321), (7, 321), (256, 321), (1, 320)] {
    let active = @local_veca.start_ranking(
      @bounded.control(),
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      inputs,
      10,
      { max_nodes: 1000, max_text_bytes: 10000, max_depth: 2, max_work: 10000, },
      82,
      1000,
      10000,
      control_work_limit=Some(work),
    ).unwrap()
    let mut done = false
    for _ in 0..<1000 {
      if done {
        break
      }
      match @local_veca.advance_ranking(active, quantum).unwrap() {
        @local_veca.RankingContinue(..) => ()
        @local_veca.RankingComplete(output, work=charged, ..) => {
          assert_eq(work, 321)
          assert_eq(charged, 321L)
          assert_eq(@execution.completed_row_count(output), 1)
          done = true
        }
        @local_veca.RankingFailed(
          @local_veca.RankingWorkLimit,
          work=charged,
          ..
        ) => {
          assert_eq(work, 320)
          assert_eq(charged, 320L)
          done = true
        }
        _ => fail("public name fixture boundary")
      }
    }
    assert_true(done)
    assert_eq(@local_veca.cleanup_ranking(active), Ok(true))
  }
  assert_true(
    @local_veca.start_ranking(
      @bounded.control(),
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      inputs,
      10,
      { max_nodes: 1000, max_text_bytes: 10000, max_depth: 2, max_work: 10000, },
      81,
      1000,
      10000,
    )
    is Err(@local_veca.RankingWorkspaceLimit),
  )
  let control = @bounded.control()
  let active = @local_veca.start_ranking(
    control,
    task_test_completion(owner),
    prepared_sequence(owner),
    0,
    inputs,
    10,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 2, max_work: 10000, },
    82,
    1000,
    10000,
  ).unwrap()
  // 1 initialization + 240 unused read/recheck + 6 id/rank + 3 group =
  // first match at 250. Seven fragments through poll 256 retain offset 448.
  assert_true(
    @local_veca.advance_ranking(active, 256).unwrap()
    is @local_veca.RankingContinue(progress=0L, work=256L),
  )
  assert_eq(@local_veca.ranking_name_offset(active), 448)
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    @local_veca.cleanup_ranking(active),
    Err(@local_veca.RankingExecutionIssue(@bounded.NotStopped)),
  )
  assert_eq(@local_veca.ranking_name_offset(active), 448)
  assert_true(inputs.all(@execution.producer_read_available))
  assert_true(
    @local_veca.advance_ranking(active, 1).unwrap()
    is @local_veca.RankingStopped(@bounded.Cancelled, work=256L, ..),
  )
  assert_eq(@local_veca.cleanup_ranking(active), Ok(true))
  assert_eq(@local_veca.ranking_name_offset(active), 0)
  assert_eq(@local_veca.cleanup_ranking(active), Ok(false))
  assert_true(inputs.all(@execution.producer_read_available))
}

///|
test "ranking reference matching retains input and output scan custody" {
  let long = String::make(513, 'z')
  for role in 0..<3 {
    let group = if role == 0 { long } else { "q" }
    let candidate = if role == 1 { long } else { "id" }
    let rank = if role == 2 { long } else { "rank" }
    let source = ranking_name_source([group, candidate, rank])
    let owner = ranking_name_owner(source, [group], candidate, rank)
    let populated = ranking_name_output(source, candidate, rank, false)
    let empty = ranking_name_output(source, candidate, rank, true)
    let inputs = [populated, empty].mapi((index, output) => {
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(owner, index, source, output).unwrap(),
        1000,
        10000,
      ).unwrap()
    })
    // Each matching 513-unit spelling needs nine fragments. Input and output
    // matching each add eight polls; renamed input rank is not an output role.
    // Input 14 + scratch 3 + validation 4 + fusion 4 + fused scratch 1 +
    // output/finalization 30 = 56. A long output name also adds nine shared
    // charge-measurement polls, giving 81 (group/candidate) or 64 (rank).
    // Workspace: 9+1+6+1 + 6 ports + 49 fixed + 6 row + 12 depth = 90.
    let exact_work = if role == 2 { 64 } else { 81 }
    for
      (quantum, work) in [
        (1, exact_work),
        (7, exact_work),
        (256, exact_work),
        (1, exact_work - 1),
      ] {
      let active = @local_veca.start_ranking(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        inputs,
        10,
        {
          max_nodes: 1000,
          max_text_bytes: 10000,
          max_depth: 10,
          max_work: 10000,
        },
        90,
        1000,
        10000,
        control_work_limit=Some(work),
      ).unwrap()
      let mut terminal = false
      for _ in 0..<1000 {
        if terminal {
          break
        }
        match @local_veca.advance_ranking(active, quantum).unwrap() {
          @local_veca.RankingContinue(..) => ()
          @local_veca.RankingComplete(output, work=charged, ..) => {
            assert_eq(work, exact_work)
            assert_eq(charged, exact_work.to_int64())
            assert_eq(@execution.completed_row_count(output), 1)
            let schema = @pipeline.schema_at(
              @lower.pipeline(@lower.bound_preparation(owner)),
              @pipeline.Step(0),
            ).unwrap()
            for column in 0..<@schema.field_count(schema) {
              let name = @schema.reference_name(
                @schema.field_at(schema, column).unwrap().name,
              )
              let expected = if name == group {
                7.0
              } else if name == "score" {
                0.5
              } else {
                1.0
              }
              assert_true(
                @execution.completed_cell(output, 0, column)
                is Some(Number(actual)) &&
                actual == expected,
              )
            }
            terminal = true
          }
          @local_veca.RankingFailed(
            @local_veca.RankingWorkLimit,
            work=charged,
            ..
          ) => {
            assert_eq(work, exact_work - 1)
            assert_eq(charged, work.to_int64())
            terminal = true
          }
          _ => fail("reference matching missed its independent boundary")
        }
      }
      assert_true(terminal)
      assert_eq(@local_veca.cleanup_ranking(active), Ok(true))
    }
    assert_true(
      @local_veca.start_ranking(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        inputs,
        10,
        {
          max_nodes: 1000,
          max_text_bytes: 10000,
          max_depth: 10,
          max_work: 10000,
        },
        89,
        1000,
        10000,
      )
      is Err(@local_veca.RankingWorkspaceLimit),
    )
    for scan in 1..<(if role == 2 { 2 } else { 3 }) {
      let control = @bounded.control()
      let active = @local_veca.start_ranking(
        control,
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        inputs,
        10,
        {
          max_nodes: 1000,
          max_text_bytes: 10000,
          max_depth: 10,
          max_work: 10000,
        },
        90,
        1000,
        10000,
      ).unwrap()
      let mut seen = 0
      let mut found = false
      let mut stopped_work = 0L
      for _ in 0..<1000 {
        guard @local_veca.advance_ranking(active, 1).unwrap()
          is @local_veca.RankingContinue(work~, ..) else {
          fail("reference matching drained before its scan boundary")
        }
        if @local_veca.ranking_name_offset(active) == 64 {
          seen += 1
          if seen == scan {
            found = true
            stopped_work = work
            break
          }
        }
      }
      assert_true(found)
      assert_true(@bounded.request_cancel(control))
      assert_false(@local_veca.ranking_stopped(active))
      assert_eq(
        @local_veca.cleanup_ranking(active),
        Err(@local_veca.RankingExecutionIssue(@bounded.NotStopped)),
      )
      assert_eq(@local_veca.ranking_name_offset(active), 64)
      assert_true(inputs.all(@execution.producer_read_available))
      assert_true(
        @local_veca.advance_ranking(active, 1).unwrap()
        is @local_veca.RankingStopped(@bounded.Cancelled, work~, ..) &&
        work == stopped_work,
      )
      assert_eq(@local_veca.ranking_name_offset(active), 64)
      assert_eq(@local_veca.cleanup_ranking(active), Ok(true))
      assert_eq(@local_veca.ranking_name_offset(active), 0)
      assert_eq(@local_veca.cleanup_ranking(active), Ok(false))
      assert_true(inputs.all(@execution.producer_read_available))
    }
  }
}
