///|
fn score_test_owner() -> @lower.BoundPrepared {
  let seed = capture_values(
    capture_fixture(),
    0,
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let ranking = @evidence.declare_ranking_scores(
      input_cursor(
        "{\"n\":{\"domain\":\"Relevance\",\"normalization\":\"Identity\",\"range\":[0,1]}}",
      ),
      @carrier.relation(@carrier.typed_rows(captured_schema(seed))),
      {
        max_work: 10000,
        max_nodes: 1000,
        max_text_bytes: 1000,
        max_depth: 100,
      },
    ).unwrap().input
  let checked = @pipeline.check_with_evidence(
    // The invalid second row would disappear if validation ran after filter.
    input_cursor("[{\"filter\":\"n <= 1\"},{\"select\":[\"s\"]}]"),
    [("rows", @pipeline.RankingInput(ranking))],
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
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
}

///|
fn score_test_read(second : String) -> SuppliedRelationRead {
  let owner = score_test_owner()
  let rows = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":0.5,\"s\":\"first\"}"),
      input_cursor("{\"n\":" + second + ",\"s\":\"second\"}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  prepare_supplied_relation_read(owner, 0, rows, fn() { true }).unwrap()
}

///|
test "supplied scores reject a filtered-out range violation before projection" {
  let input = score_test_read("2")
  assert_true(
    validate_captured_scores(
      input.rows,
      { remaining: 1000, max_frames: 100, },
      row_workspace(2),
    )
    is Err(InvalidScore(1)),
  )
  let validation = start_supplied_score_validation(
      @bounded.control(),
      input,
      1000,
      100,
      2,
    )
    .unwrap()
    .unwrap()
  let mut rejected = false
  for _ in 0..<1000 {
    match advance_supplied_score_validation(validation, 1).unwrap() {
      @bounded.ContinueWith(_, ..) => ()
      @bounded.FailedWith(InvalidScore(1), ..) => {
        rejected = true
        break
      }
      _ => fail("complete original captured input must reject the second score")
    }
  }
  assert_true(rejected)
  assert_true(cleanup_supplied_score_validation(validation) is Ok(true))
  assert_eq(validation.state.workspace.live, 0)
  assert_true(
    validation.state.input is None && validation.state.declarations is None,
  )
}

///|
test "supplied score cursor shares work across quanta and does not own borrowed rows" {
  let input = score_test_read("0.5")
  let remaining = []
  let totals = []
  for quantum in [1, 7] {
    let validation = start_supplied_score_validation(
        @bounded.control(),
        input,
        1000,
        100,
        2,
      )
      .unwrap()
      .unwrap()
    let mut completed = false
    for _ in 0..<1000 {
      match advance_supplied_score_validation(validation, quantum).unwrap() {
        @bounded.ContinueWith(_, ..) => ()
        @bounded.Completed(left, work~, ..) => {
          remaining.push(left)
          totals.push(work)
          completed = true
          break
        }
        _ => fail("valid score input")
      }
    }
    assert_true(completed)
    assert_true(cleanup_supplied_score_validation(validation) is Ok(true))
    assert_true(cleanup_supplied_score_validation(validation) is Ok(true))
    assert_eq(validation.state.workspace.live, 0)
  }
  assert_eq(remaining[0], remaining[1])
  assert_eq(totals[0], totals[1])
  assert_true(remaining[0] < 1000)
  assert_true(supplied_relation_read_available(input))
  assert_eq(supplied_relation_read_row_count(input), 2)
}

///|
test "supplied score validation honors cancellation custody and unavailable input" {
  let input = score_test_read("0.5")
  let control = @bounded.control()
  let validation = start_supplied_score_validation(control, input, 1000, 100, 2)
    .unwrap()
    .unwrap()
  assert_true(
    advance_supplied_score_validation(validation, 1)
    is Ok(@bounded.ContinueWith(_, ..)),
  )
  @bounded.request_cancel(control) |> ignore
  assert_true(
    advance_supplied_score_validation(validation, 1)
    is Ok(@bounded.StoppedWith(_, ..)),
  )
  assert_true(validation.state.input is Some(_))
  assert_true(cleanup_supplied_score_validation(validation) is Ok(true))
  assert_true(
    validation.state.input is None && validation.state.supplied is None,
  )
  let unavailable = restrict_supplied_relation_read(input, fn() { false })
  assert_true(
    start_supplied_score_validation(
      @bounded.control(),
      unavailable,
      1000,
      100,
      2,
    )
    is Err(WrongOrigin),
  )
}

///|
test "supplied score validation refuses short work and space with no resource grant" {
  let input = score_test_read("0.5")
  assert_true(
    start_supplied_score_validation(@bounded.control(), input, 1000, 100, 1)
    is Err(Limit),
  )
  let validation = start_supplied_score_validation(
      @bounded.control(),
      input,
      0,
      100,
      2,
    )
    .unwrap()
    .unwrap()
  assert_true(
    advance_supplied_score_validation(validation, 1)
    is Ok(@bounded.FailedWith(Limit, ..)),
  )
  assert_true(cleanup_supplied_score_validation(validation) is Ok(true))
  assert_eq(validation.state.workspace.live, 0)
}
