///|
fn registration_registry_fixture(
  route : Int,
  generated? : Bool = false,
  slots? : Int? = None,
) -> (@program_check.ParsedCheckRegistry, @syntax.Program, @stages.Source) {
  let (text, program, environment, evidence, limits) = public_input_fixture(
    generated~,
  )
  // The selected max_inputs restriction applies to Source occurrences, not
  // ordinary Local relation inputs. This distinct refusal fixture has one
  // actual connector declaration; zero slots rejects before Catalog lookup.
  let program = if slots is Some(_) {
    @syntax.parse(
      text.replace(
        old="\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]",
        new="\"connector\":\"crm/main\",\"resource\":\"records\",\"view\":\"v\"",
      ),
      limits.input,
      format=Json,
      source_path="registration-slot.actql",
    ).unwrap()
  } else {
    program
  }
  let limits = match slots {
    None => limits
    Some(slots) =>
      {
        ..limits,
        compilation: {
          ..limits.compilation,
          structure: { ..limits.compilation.structure, slots, },
        },
      }
  }
  let catalog = if route == 0 {
    None
  } else {
    Some(
      @program_check.prepare_source_catalog(environment, {
        max_work: 10000000,
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: if route == 2 {
          1000
        } else {
          limits.compilation.artifacts.depth
        },
      }).unwrap(),
    )
  }
  let input = @program_check.prepare_parsed_check_input(
    program,
    environment,
    None,
    evidence,
    limits,
    source_catalog=catalog,
  ).unwrap()
  let prelude = @program_check.observe_parsed_check_prelude(input).0.unwrap()
  let input = @program_check.prepare_parsed_catalog_input(prelude).unwrap()
  let original = @program_check.observe_parsed_check_registry(input).0.unwrap()
  @program_check.observe_parsed_check_contents(
    @program_check.prepare_parsed_contents_input(original).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_references(
    @program_check.prepare_parsed_references_input(original).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_policies(
    @program_check.prepare_parsed_policies_input(original).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_values(
    @program_check.prepare_parsed_values_input(original).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_views(
    @program_check.prepare_parsed_views_input(original).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_carriers(
    @program_check.prepare_parsed_carriers_input(original).unwrap(),
  ).0.unwrap()
  @program_check.observe_parsed_check_requests(
    @program_check.prepare_parsed_requests_input(original).unwrap(),
  ).0.unwrap()
  let source = @stages.prepare(program, {
    max_parameters: limits.compilation.structure.parameters,
    max_nodes: limits.compilation.traversal.nodes,
    max_depth: limits.compilation.traversal.depth,
    max_text_bytes: limits.compilation.traversal.text_bytes,
  }).unwrap()
  (original, program, source)
}

///|
fn complete_original_registration(
  read : @context.SourceRegistrationRead,
) -> Unit raise {
  // A bounded fixture driver, not a Resource funding implementation.
  for _ in 0..<20 {
    match @context.advance_source_registration(read) {
      RegistrationComplete | RegistrationFailed => return
      _ => ()
    }
  }
  fail("original registration did not reach a terminal phase")
}

///|
test "retained Context entrance feeds the original registered-source checker without repeating the entrance" {
  let (registry, program, source) = registration_registry_fixture(
    1,
    generated=true,
  )
  let original = @program_check.begin_parsed_source_registration(
    registry, source,
  ).unwrap()
  let read = @program_check.parsed_source_registration_read(original)
  complete_original_registration(read)
  let geometry = @program_check.observe_parsed_source_context_input_geometry(
    original,
  ).unwrap()
  assert_true(
    physical_equal(
      @program_check.observe_parsed_source_context_input_geometry(original).unwrap(),
      geometry,
    ),
  )
  let context = @program_check.prepare_parsed_source_context_input(original).unwrap()
  assert_true(
    physical_equal(
      @program_check.prepare_parsed_source_context_input(original).unwrap(),
      context,
    ),
  )
  assert_true(
    physical_equal(@context.sourceview_context_input_source(context), source),
  )
  let entry_work = @context.sourceview_context_input_work(context)
  assert_true(entry_work > 0)
  assert_eq(@context.source_registration_phase(read), RegistrationTransferred)
  let checked = public_checked(
    @program_check.finish_parsed_source_registration(original).unwrap(),
  )
  assert_true(
    physical_equal(@program_check.checked_source_program(checked), program),
  )
  assert_eq(@program_check.unit_count(checked), 2)
  assert_eq(
    @program_check.unit_result_import_at(checked, 1, 0).unwrap().producer_node_id,
    "producer",
  )
  let identity = @program_check.source_identity(checked)
  let values = @context.stage_identity_parameter_values(
    @context.program_identity_stage_at(identity, 0).unwrap(),
  )
  assert_eq(@parameter_refs.used_value_at(values, 0).unwrap().name, "n")
  assert_true(
    @parameter_refs.used_value_at(values, 0).unwrap().value.value is Number(1.0),
  )
  assert_eq(@context.sourceview_context_input_work(context), entry_work)
  assert_true(
    @program_check.finish_parsed_source_registration(original)
    is Err(Unavailable),
  )
  assert_true(
    @program_check.prepare_parsed_source_context_input(original)
    is Err(Unavailable),
  )
}

///|
test "retained Source registration reaches the original checker with Local and generated Result inputs" {
  for generated in [false, true] {
    for route in [0, 1, 2] {
      let (registry, program, source) = registration_registry_fixture(
        route,
        generated~,
      )
      let prepared = @program_check.begin_parsed_source_registration(
        registry, source,
      ).unwrap()
      let read = @program_check.parsed_source_registration_read(prepared)
      assert_true(
        physical_equal(
          read,
          @program_check.parsed_source_registration_read(prepared),
        ),
      )
      assert_true(
        @program_check.finish_parsed_check_registry(registry)
        is Err(AlreadyConsumed),
      )
      assert_true(
        @program_check.begin_parsed_source_registration(registry, source)
        is Err(RegistryUnavailable),
      )
      complete_original_registration(read)
      assert_eq(@context.source_registration_phase(read), RegistrationComplete)
      let spent = @context.source_registration_collection_work(read)
      assert_true(spent > 0)
      assert_true(
        @context.source_registration_collected_inputs(read) is Some(_),
      )
      let checked = public_checked(
        @program_check.finish_parsed_source_registration(prepared).unwrap(),
      )
      assert_true(
        physical_equal(@program_check.checked_source_program(checked), program),
      )
      assert_eq(@program_check.unit_count(checked), 2)
      assert_eq(
        @program_check.unit_result_import_at(checked, 1, 0).unwrap().producer_node_id,
        "producer",
      )
      let identity = @program_check.source_identity(checked)
      let values = @context.stage_identity_parameter_values(
        @context.program_identity_stage_at(identity, 0).unwrap(),
      )
      assert_eq(@parameter_refs.used_value_at(values, 0).unwrap().name, "n")
      assert_true(
        @parameter_refs.used_value_at(values, 0).unwrap().value.value
        is Number(1.0),
      )
      assert_eq(
        @context.advance_source_registration(read),
        RegistrationTransferred,
      )
      assert_eq(@context.source_registration_collection_work(read), spent)
      assert_true(
        @program_check.finish_parsed_source_registration(prepared)
        is Err(Unavailable),
      )
    }
  }
}

///|
test "pending Source registration and original cancellation cannot fall back to a fresh checker" {
  let (registry, _, source) = registration_registry_fixture(0)
  let prepared = @program_check.begin_parsed_source_registration(
    registry, source,
  ).unwrap()
  let read = @program_check.parsed_source_registration_read(prepared)
  assert_true(
    @program_check.finish_parsed_source_registration(prepared) is Err(Pending),
  )
  assert_eq(@context.advance_source_registration(read), RegistrationSelect)
  let spent = @context.source_registration_collection_work(read)
  assert_true(
    @program_check.finish_parsed_source_registration(prepared) is Err(Pending),
  )
  @context.clear_source_registration(read)
  assert_true(
    @program_check.finish_parsed_source_registration(prepared)
    is Err(Unavailable),
  )
  assert_true(
    @program_check.finish_parsed_check_registry(registry)
    is Err(AlreadyConsumed),
  )
  assert_eq(@context.advance_source_registration(read), RegistrationRetired)
  assert_eq(@context.source_registration_collection_work(read), spent)
}

///|
test "externally transferred original registration cannot be replaced or replayed" {
  let (registry, _, source) = registration_registry_fixture(1)
  let prepared = @program_check.begin_parsed_source_registration(
    registry, source,
  ).unwrap()
  let read = @program_check.parsed_source_registration_read(prepared)
  complete_original_registration(read)
  let original = @context.take_source_registration_result(read)
    .unwrap()
    .unwrap()
  assert_true(@sourceviews.pipeline_inputs_work(original.0) > 0)
  assert_true(
    @program_check.finish_parsed_source_registration(prepared)
    is Err(Unavailable),
  )
  assert_true(
    @program_check.finish_parsed_check_registry(registry)
    is Err(AlreadyConsumed),
  )
  @context.clear_source_registration(read)
  assert_eq(@context.source_registration_phase(read), RegistrationTransferred)
}

///|
test "original selected Source slot refusal remains a checker rejection rather than restarting registration" {
  let (registry, _, source) = registration_registry_fixture(0, slots=Some(0))
  let prepared = @program_check.begin_parsed_source_registration(
    registry, source,
  ).unwrap()
  let read = @program_check.parsed_source_registration_read(prepared)
  complete_original_registration(read)
  assert_eq(@context.source_registration_phase(read), RegistrationFailed)
  guard @program_check.finish_parsed_source_registration(prepared).unwrap()
    is Rejected(diagnostic) else {
    fail("original registration refusal was not retained")
  }
  assert_true(
    @program_check.diagnostic_cause(diagnostic)
    is Source(Registration(Selection({ kind: InputLimit, .. }))),
  )
  assert_eq(@context.source_registration_phase(read), RegistrationTransferred)
  assert_true(
    @program_check.finish_parsed_source_registration(prepared)
    is Err(Unavailable),
  )
}
