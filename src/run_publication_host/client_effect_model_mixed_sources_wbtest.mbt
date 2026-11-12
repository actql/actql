///|
// Real checked mixed ports and original captures. Synthetic observation DATA
// and explicit read ports do not establish a Host, Model call or Store ACK.
fn mixed_model_source_fixture(
  following? : Bool = false,
) -> (
  PreparedClientEffectComputation,
  ClientInferOccurrence,
  Array[
    (
      @query.CapturedInputSource,
      @query.CapturedSourceRelationIdentity,
      @acquisition.SourceAcquisition,
      @publication.RunEvidenceValue,
      @publication.RunEvidenceValue,
    ),
  ],
) raise {
  let base = admit_client_check_environment(
    bound_effect_source_environment,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let environment = client_composed_effect_test_environment(base)
  let document =
    #|{"version":"actql/0.1","id":"mixed-model-ports","stages":[{"id":"source","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"from":"remote","steps":[{"select":["id","amount"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","amount"]}}},{"id":"model","inputs":{"rows":{"result":{"stage":"source","result":"out"}},"inline":{"connector":"crm/right","resource":"r"}},"from":"rows","steps":[{"join":{"with":"inline","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":4,"select":{"value":"left.id"}},"as":"joined"},{"derive":{"text":{"literal":"hello"},"model_key":{"literal":"original-key"}},"as":"keyed"},{"assert_rows":{"unique_by":["model_key"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"model_key","input":{"text":{"field":"text"}}},"as":"inferred"},{"join":{"with":"keyed","kind":"inner","on":[{"left":"model_key","right":"model_key"}],"max_output_rows":4,"select":{"value":"right.value","outcome":"left.outcome"}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value","outcome"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"model","result":"out"}}}}
  let document = if following {
    guard @json.parse(document) is Object(program) &&
      program["stages"] is Array(stages) &&
      stages[1] is Object(first) else {
      fail("original mixed Program")
    }
    let effects = first["effects"]
    first.remove("effects") |> ignore
    let next = @json.parse(
      "{\"id\":\"following\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"model\",\"result\":\"out\"}}},\"steps\":[{\"derive\":{\"text\":{\"literal\":\"later\"},\"model_key\":{\"literal\":\"later-key\"}},\"as\":\"keyed\"},{\"assert_rows\":{\"unique_by\":[\"model_key\"]}},{\"infer\":{\"contract\":\"model-task:risk-score.v1\",\"key\":\"model_key\",\"input\":{\"text\":{\"field\":\"text\"}}},\"as\":\"inferred\"},{\"join\":{\"with\":\"keyed\",\"kind\":\"inner\",\"on\":[{\"left\":\"model_key\",\"right\":\"model_key\"}],\"max_output_rows\":4,\"select\":{\"value\":\"right.value\",\"outcome\":\"left.outcome\"}},\"as\":\"selected\"}],\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"value\",\"outcome\"]}}}",
    )
    guard next is Object(next_fields) else { fail("next original Model") }
    next_fields["effects"] = effects
    stages.push(next)
    program["results"] = @json.parse(
      "{\"published\":{\"from\":{\"stage\":\"following\",\"result\":\"out\"}}}",
    )
    Json::object(program).stringify()
  } else {
    document
  }
  let prepared = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(Syntax(issue)) =>
      fail("mixed fixture syntax: " + @debug.to_string(issue))
    Err(Candidate(@checked.Computation(issue))) => {
      let diagnostic = @checked.construction_failure_diagnostic(issue)
      fail(
        "mixed fixture computation " +
        (match issue {
          @checked.LocalConstructionFailure::Source(_) => "Source"
          @checked.LocalConstructionFailure::Closure(_) => "Closure"
          @checked.LocalConstructionFailure::Units(_) => "Units"
          _ => "Other"
        }) +
        " " +
        @debug.to_string(@checked.diagnostic_category(diagnostic)) +
        " " +
        @checked.diagnostic_location(diagnostic)
        .map(@checked.diagnostic_location_source_path)
        .unwrap_or("no-location") +
        " " +
        @debug.to_string(
          @checked.diagnostic_location(diagnostic).bind(
            @checked.diagnostic_location_path,
          ),
        ),
      )
    }
    Err(Candidate(_)) => fail("mixed fixture other Candidate")
    Err(Static(issue)) => {
      let label = match issue {
        @stage_results.Results(_) => "Results"
        @stage_results.MappingShapes(_) => "MappingShapes"
        @stage_results.MappingRules(_) => "MappingRules"
        @stage_results.MappingLiterals(_) => "MappingLiterals"
        _ => "Other"
      }
      fail("mixed fixture Static " + label)
    }
    Err(Graph(issue)) => fail("mixed fixture Graph: " + @debug.to_string(issue))
    Err(_) => fail("mixed fixture other preparation")
  }
  let occurrence = prepared_client_effect_infer_occurrences(prepared).unwrap()[0]
  let imported = combined_unit_whole_capture(prepared, Ref(true), 0)
  let inline = combined_unit_whole_capture(prepared, Ref(true), 0, stage=1)
  (prepared, occurrence, [imported, inline])
}

///|
test "one original Result import and one inline Source retain both Model source ports" {
  let (_, occurrence, originals) = mixed_model_source_fixture()
  let admit = fn(
    values : Array[
      (
        @query.CapturedInputSource,
        @query.CapturedSourceRelationIdentity,
        @acquisition.SourceAcquisition,
        @publication.RunEvidenceValue,
        @publication.RunEvidenceValue,
      ),
    ],
  ) {
    admit_client_infer_composed_whole_sources(
      occurrence,
      values.map(value => value.0),
      values.map(value => value.1),
      values.map(value => value.2),
      values.map(value => value.4),
      values.map(value => value.3),
      "sha256:" + "a".repeat(64),
      "2026-11-11T00:00:01.000Z",
      "2026-11-11T00:00:02.000Z",
    )
  }
  assert_eq(
    infer_scope_expected_whole_sources(occurrence)
    .unwrap()
    .unwrap()
    .map(value => value.0),
    ["rows", "inline"],
  )
  let accepted = admit(originals)
  assert_true(accepted is Ok(_))
  assert_eq(
    client_infer_composed_source_observations(accepted.unwrap()).length(),
    2,
  )
  assert_true(admit([originals[1], originals[0]]) is Err(_))
  assert_true(admit([originals[0], originals[0]]) is Err(_))
  let (_, _, foreign) = mixed_model_source_fixture()
  assert_true(admit([originals[0], foreign[1]]) is Err(_))
}

///|
test "inline Source and original import closure survives the following Model boundary" {
  let (_, occurrence, originals) = mixed_model_source_fixture(
    following=true,
  )
  let accepted = admit_client_infer_composed_whole_sources(
    occurrence,
    originals.map(value => value.0),
    originals.map(value => value.1),
    originals.map(value => value.2),
    originals.map(value => value.4),
    originals.map(value => value.3),
    "sha256:" + "a".repeat(64),
    "2026-11-11T00:00:01.000Z",
    "2026-11-11T00:00:02.000Z",
  ).unwrap()
  let second = prepared_client_composed_infer_occurrences(occurrence.owner).unwrap()[1]
  assert_true(
    occurrence.stage < second.stage,
    msg="checked Model stages: " +
      @debug.to_string(
        (
          client_infer_occurrence_coordinates(occurrence),
          client_infer_occurrence_coordinates(second),
        ),
      ),
  )
  let program = @strategy.graph_program(occurrence.owner.graph)
  assert_true(
    @checked.unit_result_import_count(program, second.stage) == Some(1),
    msg="checked second Model imports: " +
      @debug.to_string(
        (
          @checked.unit_count(program),
          @checked.unit_result_import_count(program, second.stage),
        ),
      ),
  )
  assert_true(
    client_infer_composed_source_boundary(occurrence),
    msg="original mixed Source boundary",
  )
  assert_false(
    client_infer_composed_source_boundary(second),
    msg="following Model preserves the original boundary",
  )
  assert_true(
    client_infer_composed_source_precedes(occurrence, second),
    msg="original checked Model edge",
  )
  assert_true(
    client_infer_composed_source_origin(second) is Some(_),
    msg="following Model has its original Source boundary",
  )
  assert_true(client_infer_composed_sources_matches(accepted, second))
  assert_eq(
    infer_scope_expected_whole_sources(second)
    .unwrap()
    .unwrap()
    .map(value => value.0),
    ["rows", "inline"],
  )
}
