///|
// This uses admitted Catalog/Host-policy fixture DATA and starts no physical
// Source. Publication interpretation is not an installation or read grant.
fn unfiltered_join_requirement_program() -> @publication_host.PreparedClientProgram {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:4ea01561b9ac9815baaf04a81cff8260c8a47c56f19828b5889cf45ec1436e78",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication =
    #|{"environmentCid":"sha256:4ea01561b9ac9815baaf04a81cff8260c8a47c56f19828b5889cf45ec1436e78","aliases":[{"name":"left_records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"},{"name":"right_records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"}]}
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
  @publication_host.prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn unfiltered_join_requirement(
  prepared : @publication_host.PreparedClientProgram,
  stage : Int,
) -> @planning.QueryRequirement raise {
  match
    prepare_local_query_requirement(
      prepared,
      stage,
      0,
      source_query_original_registry,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    ) {
    Ok(value) => value
    Err(Sequences) => fail("original JOIN Source.Query.Sequences")
    Err(MissingStage) => fail("original JOIN Source.Query.MissingStage")
    Err(Requirement(@publication_host.Acquisition(_))) =>
      fail("original JOIN Source.Query.Acquisition")
    Err(Requirement(@publication_host.Sequence(_))) =>
      fail("original JOIN Source.Query.Sequence")
    Err(Requirement(@publication_host.Material(_))) =>
      fail("original JOIN Source.Query.Material")
    Err(Requirement(@publication_host.Requirement(_))) =>
      fail("original JOIN Source.Query.Requirement")
  }
}

///|
test "public unfiltered JOIN derives both original Local QueryRequirements" {
  let prepared = unfiltered_join_requirement_program()
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 2)
  let left = unfiltered_join_requirement(prepared, 0)
  let right = unfiltered_join_requirement(prepared, 1)
  assert_true(
    physical_equal(
      @planning.query_requirement_program(left),
      @planning.query_requirement_program(right),
    ),
  )
  assert_eq(@planning.query_requirement_site(left), ("capture", "source_0"))
  assert_eq(@planning.query_requirement_site(right), ("capture_1", "source_1"))
  // Equal Source and schema facts do not collapse the original occurrences.
  assert_eq(
    @planning.query_requirement_source(left),
    @planning.query_requirement_source(right),
  )
  assert_not_eq(
    @planning.query_requirement_cid(left),
    @planning.query_requirement_cid(right),
  )
  let foreign = unfiltered_join_requirement(
    unfiltered_join_requirement_program(),
    0,
  )
  assert_false(
    physical_equal(
      @planning.query_requirement_program(left),
      @planning.query_requirement_program(foreign),
    ),
  )
}
