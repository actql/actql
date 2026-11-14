///|
test "Direct occurrence selection retains the original two captured tasks" {
  let prepared = multi_source_prepared(multi_source_program)
  let selected = select_client_direct_acquisition_occurrences(prepared, 1000000).unwrap()
  assert_eq(client_direct_acquisition_occurrence_count(selected), 2)
  assert_eq(
    client_direct_acquisition_occurrence_at(selected, 0),
    Some((0, 0, 0)),
  )
  assert_eq(
    client_direct_acquisition_occurrence_at(selected, 1),
    Some((1, 0, 1)),
  )
  assert_eq(client_direct_acquisition_occurrence_at(selected, -1), None)
  assert_eq(client_direct_acquisition_occurrence_at(selected, 2), None)
  assert_true(
    client_direct_acquisition_occurrences_match_program(selected, prepared),
  )
  let foreign = multi_source_prepared(multi_source_program)
  assert_false(
    client_direct_acquisition_occurrences_match_program(selected, foreign),
  )
  assert_true(
    select_client_direct_acquisition_occurrences(prepared, -1)
    is Err(InvalidLimits),
  )
  assert_true(
    select_client_direct_acquisition_occurrences(prepared, 0) is Err(WorkLimit),
  )
  assert_true(
    select_client_direct_acquisition_occurrences(
      prepared,
      @checked.source_execution_count(@strategy.graph_program(prepared.graph)),
    )
    is Err(WorkLimit),
  )
}

///|
test "Direct occurrence selection preserves Effect ownership without granting Pure identity" {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let prepared = prepare_client_effect_computation(
    bound_effect_source_document,
    Json,
    source_input_program_environment(),
    None,
    [],
    limits,
  ).unwrap()
  let selected = select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).unwrap()
  assert_eq(client_direct_acquisition_occurrence_count(selected), 1)
  assert_eq(
    client_direct_acquisition_occurrence_at(selected, 0),
    Some((0, 0, 0)),
  )
  assert_true(
    client_direct_acquisition_occurrences_match_effect_program(
      selected, prepared,
    ),
  )
  assert_false(
    client_direct_acquisition_occurrences_match_program(
      selected,
      client_effect_program_view(prepared),
    ),
  )
  let foreign = prepare_client_effect_computation(
    bound_effect_source_document,
    Json,
    source_input_program_environment(),
    None,
    [],
    limits,
  ).unwrap()
  assert_false(
    client_direct_acquisition_occurrences_match_effect_program(
      selected, foreign,
    ),
  )
  assert_true(
    select_client_effect_direct_acquisition_occurrences(prepared, 0)
    is Err(WorkLimit),
  )
}

///|
test "Direct occurrence selection retains unfiltered Input without manufacturing a Query capture" {
  let prepared = source_input_unfiltered_program()
  let selected = select_client_direct_acquisition_occurrences(prepared, 1000000).unwrap()
  assert_eq(client_direct_acquisition_occurrence_count(selected), 1)
  assert_eq(
    client_direct_acquisition_occurrence_at(selected, 0),
    Some((0, 0, 0)),
  )
  let original = prepare_client_source_acquisition(prepared, 0, 0).unwrap()
  assert_eq(@acquisition.source_acquisition_input(original), @pipeline.Input(0))
  assert_true(
    prepare_client_query_acquisition(prepared, 0, 0)
    is Err(UnsupportedAcquisition(_)),
  )
}

///|
test "Direct occurrence mapping rejects foreign checked owner and wrong checked obligation" {
  let prepared = multi_source_prepared(multi_source_program)
  let foreign = multi_source_prepared(multi_source_program)
  let selected = select_client_direct_acquisition_occurrences(prepared, 1000000).unwrap()
  assert_true(
    client_direct_acquisition_occurrence_coordinate(
      foreign,
      selected.checks[0],
      Ref(1000000),
    )
    is Err(ForeignRequest),
  )
  let checked = @strategy.graph_program(prepared.graph)
  let mut tested = false
  for index in 0..<@checked.source_execution_count(checked) {
    let check = @checked.source_execution_at(checked, index).unwrap()
    if @checked.source_execution_kind(check) is @checked.HostCombination {
      assert_true(
        client_direct_acquisition_occurrence_coordinate(
          prepared,
          check,
          Ref(1000000),
        )
        is Err(UnsupportedShape),
      )
      tested = true
      break
    }
  }
  assert_true(tested)
  // Swapping selected checks cannot swap the original graph coordinates.
  assert_eq(
    client_direct_acquisition_occurrence_coordinate(
      prepared,
      selected.checks[1],
      Ref(1000000),
    ).unwrap(),
    (1, 0, 1, false),
  )
  assert_eq(
    client_direct_acquisition_occurrence_coordinate(
      prepared,
      selected.checks[0],
      Ref(1000000),
    ).unwrap(),
    (0, 0, 0, false),
  )
}

///|
test "Direct subject borrowing retains the filtered original across multiple obligations and foreign equal Programs" {
  let prepared = multi_source_prepared(multi_source_program)
  let selected = select_client_direct_acquisition_occurrences(prepared, 1000000).unwrap()
  let foreign_prepared = multi_source_prepared(multi_source_program)
  let foreign = select_client_direct_acquisition_occurrences(
    foreign_prepared, 1000000,
  ).unwrap()
  assert_true(
    client_direct_acquisition_occurrence_subject(selected, -1) is None,
  )
  assert_true(client_direct_acquisition_occurrence_subject(selected, 2) is None)
  let checked = @strategy.graph_program(prepared.graph)
  assert_true(@checked.source_execution_count(checked) > 2)
  for index in 0..<2 {
    let original = client_direct_acquisition_occurrence_subject(selected, index).unwrap()
    let coordinates = client_direct_acquisition_occurrence_at(selected, index).unwrap()
    assert_eq((original.stage, original.input), (coordinates.0, coordinates.1))
    assert_true(original.request is @acquisition.Direct(_, _))
    assert_true(
      physical_equal(original.owner, @checked.source_identity(checked)),
    )
    assert_true(
      physical_equal(
        original,
        @checked.source_execution_subject(selected.checks[index]),
      ),
    )
    assert_true(
      @checked.source_execution_kind(selected.checks[index])
      is @checked.CarrierResponse,
    )
    assert_false(
      physical_equal(
        original,
        client_direct_acquisition_occurrence_subject(foreign, index).unwrap(),
      ),
    )
  }
}

///|
// Actual checked two-Source producer plus correlated read and two Models.
// This is early coverage DATA only, not capture/lookup/Model completion.
test "preconsumer Direct coverage keeps original joined inputs while later keyed obligations remain open" {
  let (first, _, _) = client_keyed_plan_test_inputs(
    plural=true,
    declared=true,
    joined_producer=true,
  )
  let prepared = first.owner
  let selected = select_client_direct_acquisition_occurrences(prepared, 1000000).unwrap()
  assert_eq(client_direct_acquisition_occurrence_count(selected), 2)
  assert_true(client_direct_source_input_coverage(prepared, selected, 2, true))
  assert_false(
    client_direct_source_input_coverage(prepared, selected, 2, false),
  )
  for count in [0, 1, 3] {
    assert_false(
      client_direct_source_input_coverage(prepared, selected, count, true),
    )
  }
  let (other, _, _) = client_keyed_plan_test_inputs(
    plural=true,
    declared=true,
    joined_producer=true,
  )
  assert_false(
    client_direct_source_input_coverage(other.owner, selected, 2, true),
  )
  assert_eq(
    prepared_client_composed_infer_occurrences(prepared).unwrap().length(),
    2,
  )
}
