///|
test "input geometry counts original fields without copying or rereading Catalog" {
  let environment = prepared_publication_source_environment()
  let reads = Ref(0)
  let prepared = prepare_published_query_environment_with_readers(
    environment,
    prepared_publication_source_wire(environment),
    source_publication_cursor,
    (original, limits, contents) => {
      reads.val += 1
      publication_read_catalog(original, limits, contents)
    },
  ).unwrap()
  let inputs = prepared.context.inputs
  let fields = inputs[0].visible_fields
  for _ in 0..<2 {
    assert_eq(
      prepared_published_query_input_field_geometry(prepared, environment).unwrap(),
      (1L, 2L),
    )
  }
  assert_eq(reads.val, 1)
  assert_true(physical_equal(inputs, prepared.context.inputs))
  assert_true(physical_equal(fields, prepared.context.inputs[0].visible_fields))
  assert_eq(fields, ["id"])
}

///|
test "input geometry preserves equal-CID foreign Environment refusal" {
  let environment = prepared_publication_source_environment()
  let prepared = prepare_published_query_environment(
    environment,
    prepared_publication_source_wire(environment),
  ).unwrap()
  let foreign = @program_check.checking_environment(
    @program_check.checking_environment_wire(environment),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  assert_eq(
    @program_check.checking_environment_cid(environment),
    @program_check.checking_environment_cid(foreign),
  )
  assert_true(
    prepared_published_query_input_field_geometry(prepared, foreign)
    is Err(ForeignEnvironment),
  )
}

///|
test "input geometry sums all alias field inventories including an empty Context" {
  let environment = prepared_publication_source_environment()
  let empty = prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  assert_eq(
    prepared_published_query_input_field_geometry(empty, environment).unwrap(),
    (0L, 0L),
  )
  let extra =
    #|{"name":"more","sourceRef":"connector://crm/main/records#v","sourceViewContractCid":"sha256:78cffc445d46c9bcd0d7d5b7223332587fab9fedbc69f85c88cb6588ff554143","schemaContractCid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759"}
  let two = prepare_published_query_environment(
    environment,
    prepared_publication_source_wire(environment).replace(
      old="\"aliases\":[",
      new="\"aliases\":[" + extra + ",",
    ),
  ).unwrap()
  assert_eq(
    prepared_published_query_input_field_geometry(two, environment).unwrap(),
    (2L, 4L),
  )
}
