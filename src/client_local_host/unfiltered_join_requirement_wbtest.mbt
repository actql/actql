///|
// This uses admitted Catalog/Host-policy fixture DATA and starts no physical
// Source. Publication interpretation is not an installation or read grant.
fn unfiltered_join_requirement_program() -> (
  @publication_host.PreparedClientProgram,
  @syntax.Program,
) raise {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication =
    #|{"environmentCid":"sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8","aliases":[{"name":"left_records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"},{"name":"right_records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"}]}
  let context = @source_publication.bind_published_query_context(
    environment,
    publication,
    None,
  ).unwrap()
  let lowered = @frontend.lower(
    "SELECT l.id AS id FROM left_records AS l JOIN right_records AS r ON l.id = r.id MAX_OUTPUT_ROWS 4",
    Sql,
    Some(context),
  ).unwrap()
  let program = lowered.program.unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @syntax.emit_metadata_stripped_program(program, writer)
  assert_false(@encode.finish(writer).contains("\"filter\":{\"literal\":true}"))
  (
    @publication_host.prepare_parsed_effect_free_client_program(
      program,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap(),
    program,
  )
}

///|
fn unfiltered_join_whole_input(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  stage : Int,
) -> @sourceviews.SourceAcquisition raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  // An absent predicate does not establish the narrower QueryRequirement.
  assert_true(
    prepare_local_query_requirement(
      prepared,
      stage,
      0,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Sequences),
  )
  guard select_installed_source_input(prepared, request, stage, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("unfiltered JOIN must retain its actual Whole input")
  }
  assert_true(
    @publication_host.client_source_acquisition_matches_program(
      prepared, stage, 0, original,
    ),
  )
  assert_eq(@sourceviews.source_acquisition_input(original), @pipeline.Input(0))
  let schema = @pipeline.schema_at(
    @sourceviews.source_acquisition_pipeline(original),
    @pipeline.Input(0),
  ).unwrap()
  assert_eq(@schema.field_count(schema), 2)
  for (index, name, nullable) in [(0, "amount", true), (1, "id", false)] {
    let field = @schema.field_at(schema, index).unwrap()
    assert_eq(field.name, @schema.Unqualified(name))
    assert_true(
      @contract.type_equal(
        field.contract,
        @contract.primitive(@contract.NumberType, nullable~),
        100,
      ),
    )
  }
  original
}

///|
test "public unfiltered JOIN selects both original Whole inputs and refuses QueryRequirements" {
  let (prepared, program) = unfiltered_join_requirement_program()
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 2)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "unfiltered-join-original",
  ).unwrap()
  let left = unfiltered_join_whole_input(prepared, request, 0)
  let right = unfiltered_join_whole_input(prepared, request, 1)
  let checked = @strategy.graph_program(
    @publication_host.prepared_client_graph(prepared),
  )
  assert_true(
    physical_equal(
      @sourceviews.source_acquisition_pipeline(left),
      @checked.unit_pipeline(checked, 0).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      @sourceviews.source_acquisition_pipeline(right),
      @checked.unit_pipeline(checked, 1).unwrap(),
    ),
  )
  let stages = @syntax.stages(program)
  assert_eq(
    (stages[0].id, @syntax.result_names(stages[0])[0]),
    ("capture", "source"),
  )
  assert_eq(
    (stages[1].id, @syntax.result_names(stages[1])[0]),
    ("capture_1", "source"),
  )
  let left_source = @sourceviews.declaration(
    @sourceviews.mode_input(@sourceviews.source_acquisition_mode(left)),
  )
  let right_source = @sourceviews.declaration(
    @sourceviews.mode_input(@sourceviews.source_acquisition_mode(right)),
  )
  assert_eq(
    (left_source.connector, left_source.resource, left_source.view),
    ("crm/main", "r", Some("v")),
  )
  assert_eq(
    (right_source.connector, right_source.resource, right_source.view),
    (left_source.connector, left_source.resource, left_source.view),
  )
  // Equal Source facts retain distinct original occurrences, not a fabricated
  // Query CID. Both belong to the same checked Program above.
  assert_false(
    physical_equal(
      @sourceviews.source_acquisition_owner(left),
      @sourceviews.source_acquisition_owner(right),
    ),
  )
  let identity = @checked.source_identity(checked)
  assert_not_eq(
    @context.stage_identity_definition_cid(
      @context.program_identity_stage_at(identity, 0).unwrap(),
    ),
    @context.stage_identity_definition_cid(
      @context.program_identity_stage_at(identity, 1).unwrap(),
    ),
  )
  let (foreign_prepared, _) = unfiltered_join_requirement_program()
  let foreign_request = @publication_host.prepare_source_free_client_request_identity(
    foreign_prepared,
    "sha256:" + "a".repeat(64),
    "unfiltered-join-original",
  ).unwrap()
  let foreign = unfiltered_join_whole_input(
    foreign_prepared, foreign_request, 0,
  )
  assert_false(
    @publication_host.client_source_acquisition_matches_program(
      prepared, 0, 0, foreign,
    ),
  )
}

///|
test "plural Whole Plan binds checked Source order and refuses equal foreign or swapped inputs" {
  let (prepared, _) = unfiltered_join_requirement_program()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "plural-whole-plan",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let limits = installed_row_input_policy(4, 4096, 256, 16, 4)
  let sources = [0, 1].map(stage => {
    prepare_installed_catalog_whole_source_capacity(
      prepared,
      unfiltered_join_whole_input(prepared, request, stage),
      contracts,
      limits,
    ).unwrap()
  })
  let construct = sources => {
    prepare_installed_managed_whole_sources_plan(
      prepared,
      request,
      sources,
      [4096L, 4096L],
      [4096L, 4096L],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      retained_output=true,
      provider_factory=_ => [],
      runtime_admission=true,
    )
  }
  let plan = construct(sources).unwrap()
  assert_eq(@strategy.graph_captured_prefix(plan.graph), 0)
  assert_eq(plan.captures.length(), 0)
  assert_eq(plan.whole_sources.length(), 2)
  let direct = plan.direct_occurrences.unwrap()
  for slot in 0..<2 {
    assert_true(physical_equal(plan.whole_sources[slot], sources[slot]))
    assert_eq(
      @publication_host.client_direct_acquisition_occurrence_at(direct, slot),
      Some((slot, 0, slot)),
    )
  }
  assert_true(construct([sources[1], sources[0]]) is Err(ForeignOriginal))
  let (foreign, _) = unfiltered_join_requirement_program()
  let foreign_request = @publication_host.prepare_source_free_client_request_identity(
    foreign,
    "sha256:" + "a".repeat(64),
    "plural-whole-plan",
  ).unwrap()
  let copied = prepare_installed_catalog_whole_source_capacity(
    foreign,
    unfiltered_join_whole_input(foreign, foreign_request, 1),
    contracts,
    limits,
  ).unwrap()
  assert_true(construct([sources[0], copied]) is Err(ForeignOriginal))
}
