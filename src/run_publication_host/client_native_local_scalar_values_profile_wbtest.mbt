///|
fn scalar_profile_cursor(wire : String) -> @decode.Cursor {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap()
  @decode.admit(source, {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 65536,
    max_total_string_bytes: 65536,
  }).unwrap()
}

///|
fn scalar_profile_prepared(
  document : String,
  bindings? : @decode.Cursor? = None,
) -> PreparedClientProgram raise {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let result = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    bindings,
    client_standard_program_preparation_limits(),
  )
  match result {
    Ok(value) => value
    Err(Check(issue)) => raise @checked.diagnostic_cause(issue)
    Err(_) => abort("fixture preparation outside checked boundary")
  }
}

///|
fn scalar_profile_operations(
  profile : ClientNativeLocalScalarValuesProfile,
) -> Array[String] {
  Array::makei(
    client_native_local_scalar_values_profile_operation_count(profile),
    i => {
      client_native_local_scalar_values_profile_operation_at(profile, i).unwrap()
    },
  )
}

///|
fn scalar_profile_expressions(
  profile : ClientNativeLocalScalarValuesProfile,
) -> Array[String] {
  Array::makei(
    client_native_local_scalar_values_profile_expression_count(profile),
    i => {
      client_native_local_scalar_values_profile_expression_at(profile, i).unwrap()
    },
  )
}

///|
test "scalar profile reads original scalar cells and every ordinary arithmetic root" {
  let document = run_materials_document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"raw\"},{\"derive\":{\"value\":\"id + 1\"},\"as\":\"derived\"},{\"filter\":\"value > 1\",\"as\":\"selected\"}],",
  )
  let prepared = scalar_profile_prepared(document)
  let profile = inspect_client_native_local_scalar_values_profile(
    prepared, 1000,
  ).unwrap()
  assert_eq(scalar_profile_operations(profile), [
    "REL.values", "REL.derive", "REL.where",
  ])
  assert_eq(scalar_profile_expressions(profile), [
    "add", "field", "literal", "gt", "field", "literal",
  ])
  assert_eq(
    validate_client_native_local_scalar_values_preparation(profile, prepared),
    Ok(()),
  )
  assert_eq(
    validate_client_native_local_scalar_values_preparation(
      profile,
      scalar_profile_prepared(document),
    ),
    Err(ForeignPreparation),
  )
}

///|
test "scalar profile refuses empty or dropped non-scalar declared Values columns" {
  for rows in ["[]", "[{\"id\":1,\"hidden\":[]}]"] {
    let document = "{\"version\":\"actql/0.1\",\"id\":\"hidden\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"hidden\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":" +
      rows +
      "},\"as\":\"raw\"},{\"select\":[\"id\"],\"as\":\"selected\"}],\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}"
    assert_eq(
      inspect_client_native_local_scalar_values_profile(
        scalar_profile_prepared(document),
        1000,
      ).map(_ => 0),
      Err(NonScalar),
    )
  }
}

///|
test "scalar profile excludes reference Json and container shapes independently of current values" {
  let content = @contract.content_reference_contract(
    None,
    nullable=true,
    max_name_bytes=100,
  ).unwrap()
  let resource = @contract.read_checked(
    scalar_profile_cursor(
      "{\"nullable\":true,\"resource_kind\":\"fixture\",\"type\":\"resource_ref\"}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for
    contract in [
      content,
      resource,
      @contract.primitive(@contract.JsonType, nullable=true),
      @contract.array_contract(
        @contract.primitive(@contract.NumberType, nullable=false),
        nullable=true,
      ).unwrap(),
    ] {
    assert_false(scalar_values_contract(contract))
  }
}

///|
test "scalar profile maintains an explicit finite scan budget and Source refusal" {
  let prepared = scalar_profile_prepared(run_materials_document)
  assert_eq(
    inspect_client_native_local_scalar_values_profile(prepared, 0).map(_ => 0),
    Err(InvalidLimit),
  )
  assert_eq(
    inspect_client_native_local_scalar_values_profile(prepared, 1).map(_ => 0),
    Err(BudgetExceeded),
  )
  assert_eq(
    inspect_client_native_local_scalar_values_profile(
      local_normalization_fixture(),
      1000,
    ).map(_ => 0),
    Err(UnsupportedProfile),
  )
}

///|
test "scalar profile checks unused declarations while public preparation retains its earlier refusal" {
  let declarations = @parameter.read_declarations(
    Some(
      scalar_profile_cursor(
        "{\"unused\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let values = @parameter.bind(
    declarations,
    Some(scalar_profile_cursor("{\"unused\":[]}")),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  guard values is @parameter.Ready(values) else { fail("actual bound owner") }
  assert_eq(
    scalar_values_parameters(Some(values), { remaining: 1000, expressions: [], }),
    Err(NonScalar),
  )
  let document = run_materials_document.replace(
    old="\"stages\":[",
    new="\"params\":{\"unused\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}},\"stages\":[",
  )
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let result = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    Some(scalar_profile_cursor("{\"unused\":[]}")),
    client_standard_program_preparation_limits(),
  )
  guard result is Err(Check(diagnostic)) else { fail("original refusal") }
  guard @checked.diagnostic_cause(diagnostic)
    is @checked.Source(
      @checked.Identity(
        @context.References(
          @context.Usage(@program_refs.UnusedParameter(declaration))
        )
      )
    ) else {
    fail("retain original unused parameter cause")
  }
  assert_eq(declaration.name, "unused")
  assert_false(scalar_values_contract(declaration.parameter_type.contract))
}

///|
test "scalar profile includes nonselected CASE types even when its result is Boolean" {
  let document = run_materials_document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"raw\"},{\"derive\":{\"ok\":\"(CASE WHEN TRUE THEN NULL ELSE [1] END) IS NULL\"},\"as\":\"selected\"}],",
  )
  let prepared = scalar_profile_prepared(document)
  assert_eq(
    inspect_client_native_local_scalar_values_profile(prepared, 1000).map(_ => 0),
    Err(NonScalar),
  )
}

///|
test "scalar profile does not silently generalize an unproven expression or row operation" {
  let expression = run_materials_document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"raw\"},{\"derive\":{\"value\":\"abs(id)\"},\"as\":\"selected\"}],",
  )
  assert_eq(
    inspect_client_native_local_scalar_values_profile(
      scalar_profile_prepared(expression),
      1000,
    ).map(_ => 0),
    Err(UnprovenExpression),
  )
  let row_operation = run_materials_document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"raw\"},{\"take\":1,\"as\":\"selected\"}],",
  )
  assert_eq(
    inspect_client_native_local_scalar_values_profile(
      scalar_profile_prepared(row_operation),
      1000,
    ).map(_ => 0),
    Err(UnsupportedProfile),
  )
}

///|
test "scalar profile keeps bound scalar parameter types nullability and exact Unicode cell values" {
  let document = run_materials_document
    .replace(
      old="\"stages\":[",
      new="\"params\":{\"bump\":{\"type\":\"number\"},\"note\":{\"type\":\"string\",\"nullable\":true}},\"stages\":[",
    )
    .replace(
      old="\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]",
      new="\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"note\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"id\":1,\"note\":{\"$param\":\"note\"}},{\"id\":2,\"note\":null}]",
    )
    .replace(
      old="\"as\":\"selected\"}],",
      new="\"as\":\"raw\"},{\"derive\":{\"value\":\"id + $bump\"},\"as\":\"selected\"}],",
    )
  let prepared = scalar_profile_prepared(
    document,
    bindings=Some(
      scalar_profile_cursor("{\"bump\":2,\"note\":\"é\\r\\n é\"}"),
    ),
  )
  let profile = inspect_client_native_local_scalar_values_profile(
    prepared, 1000,
  ).unwrap()
  assert_eq(scalar_profile_operations(profile), ["REL.values", "REL.derive"])
  assert_eq(scalar_profile_expressions(profile), ["add", "field", "$param"])
  let owner = @strategy.graph_task_owner(prepared_client_graph(prepared), 0).unwrap()
  let cell = @lower.bound_values_cell(owner, 0, 0, 1).unwrap()
  guard cell.value is @values.Text(text) else { fail("original text cell") }
  assert_eq(text, "é\r\n é")
  assert_true(cell.contract.nullable)
  assert_true(
    @lower.bound_values_cell(owner, 0, 1, 1).unwrap().value is @values.Null,
  )
}

///|
test "scalar profile Rename and Drop facts use the original AoA Select operation" {
  let document = run_materials_document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"raw\"},{\"derive\":{\"scratch\":\"id + 1\"},\"as\":\"derived\"},{\"rename\":{\"scratch\":\"temporary\"},\"as\":\"renamed\"},{\"drop\":[\"temporary\"],\"as\":\"selected\"}],",
  )
  let profile = inspect_client_native_local_scalar_values_profile(
    scalar_profile_prepared(document),
    1000,
  ).unwrap()
  // Both source operations lower through the existing Select owner. These
  // independent expected names are the registered AoA operations, not aliases.
  assert_eq(scalar_profile_operations(profile), [
    "REL.values", "REL.derive", "REL.select", "REL.select",
  ])
  assert_eq(scalar_profile_expressions(profile), ["add", "field", "literal"])
}

///|
test "scalar profile indexed views preserve exact counts and refuse invalid indices" {
  let prepared = scalar_profile_prepared(run_materials_document)
  let profile = inspect_client_native_local_scalar_values_profile(
    prepared, 1000,
  ).unwrap()
  assert_eq(
    client_native_local_scalar_values_profile_operation_count(profile),
    1,
  )
  assert_eq(
    client_native_local_scalar_values_profile_operation_at(profile, 0),
    Some("REL.values"),
  )
  assert_eq(
    client_native_local_scalar_values_profile_expression_count(profile),
    0,
  )
  for index in [-1, 1, 2147483647] {
    assert_eq(
      client_native_local_scalar_values_profile_operation_at(profile, index),
      None,
    )
  }
  for index in [-1, 0, 2147483647] {
    assert_eq(
      client_native_local_scalar_values_profile_expression_at(profile, index),
      None,
    )
  }
  let inspected = client_native_local_scalar_values_profile_inspected_entries(
    profile,
  )
  assert_true(inspected > 0 && inspected <= 1000)
  assert_eq(scalar_profile_operations(profile), ["REL.values"])
  assert_eq(
    validate_client_native_local_scalar_values_preparation(profile, prepared),
    Ok(()),
  )
}
