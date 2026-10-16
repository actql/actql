///|
fn client_create_values_prepared(
  value : String,
  parameter? : Bool = false,
) -> PreparedClientEffectComputation {
  let (document, environment, limits) = client_effect_fixture()
  let document = document.replace(
    old="\"from\":{\"result\":\"out\"}",
    new="\"from\":{\"result\":\"out\"},\"values\":{\"Name\":" + value + "}",
  )
  let document = if parameter {
    document.replace(
      old="\"id\":\"client-effect\"",
      new="\"id\":\"client-effect\",\"params\":{\"n\":{\"type\":\"number\"}}",
    )
  } else {
    document
  }
  let supplied = if parameter {
    Some(
      @decode.admit(
        @source.parse_json("{\"n\":9}", {
          max_input_bytes: 100,
          max_nodes: 10,
          max_depth: 3,
        }).unwrap(),
        {
          max_nodes: 10,
          max_depth: 3,
          max_string_bytes: 100,
          max_total_string_bytes: 100,
        },
      ).unwrap(),
    )
  } else {
    None
  }
  prepare_client_effect_computation(
    document,
    Json,
    environment,
    supplied,
    [],
    limits,
  ).unwrap()
}

///|
fn client_create_values_projection(
  prepared : PreparedClientEffectComputation,
  literal_owner : PreparedClientEffectComputation,
) -> Result[String, @stage_results.EffectCreateRowIssue] {
  let original = @checked.effect_program_static_effects(
    prepared_client_effect_computation_candidate(prepared),
  )
  let rule = @stage_results.effect_static_candidate_mapping_rules(original)
  let terminal = @stage_results.effect_create_row_terminal_for_member(
      rule, 0, 1, 1000,
    )
    .unwrap()
    .unwrap()
  let literals = @stage_results.effect_static_candidate_mapping_literals(
    @checked.effect_program_static_effects(
      prepared_client_effect_computation_candidate(literal_owner),
    ),
  )
  let row = @canonical.from_source(
    @source.parse_json("{\"value\":1}", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 3,
    }).unwrap(),
    10,
    3,
    100,
  ) catch {
    _ => abort("Expected canonical captured-row fixture")
  }
  @stage_results.effect_create_row_intended_changes_wire(
    terminal, literals, row, 1, 1000, 1000, 100, 10,
  )
}

///|
test "Client create values preserve the same checked preparation at proposal" {
  for
    (value, expected) in [
      ("{\"field\":\"value\"}", "1"),
      ("{\"literal\":9}", "9"),
    ] {
    let prepared = client_create_values_prepared(value)
    assert_eq(
      client_create_values_projection(prepared, prepared).unwrap(),
      "{\"state\":\"present\",\"value\":{\"Name\":" + expected + "}}",
    )
    let equal_but_foreign = client_create_values_prepared(value)
    assert_eq(
      client_create_values_projection(prepared, equal_but_foreign).unwrap_err(),
      @stage_results.ForeignLiterals,
    )
  }
}

///|
test "Client create literal Parameter uses the original bound value once" {
  let prepared = client_create_values_prepared(
    "{\"literal\":{\"$param\":\"n\"}}",
    parameter=true,
  )
  assert_eq(
    client_create_values_projection(prepared, prepared).unwrap(),
    "{\"state\":\"present\",\"value\":{\"Name\":9}}",
  )
  let literal = client_create_values_prepared("{\"literal\":9}")
  assert_eq(
    client_create_values_projection(prepared, literal).unwrap_err(),
    @stage_results.ForeignLiterals,
  )
}
