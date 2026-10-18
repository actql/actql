///|
test "query Job material quotes original identifier spelling without SQL syntax injection" {
  let selected = table_target("acme-project", "d`x", "t\\q", 1024).unwrap()
  let name = "n`\\\n雪"
  let description = project_table_description(
    selected,
    body([field(name, "STRING")], dataset="d`x", table="t\\q"),
    limits(),
  ).unwrap()
  let projection = prepare_read_projection(description, [name], limits()).unwrap()
  assert_eq(
    read_projection_statement(projection),
    "SELECT `n\\`\\\\\\x0A雪` FROM `acme-project`.`d\\`x`.`t\\\\q`",
  )
  let material = prepare_query_job_material(
    projection,
    qjob(),
    9223372036854775807L,
    4096,
  ).unwrap()
  let raw = query_job_material_body(material)
  assert_true(raw.contains("\"maximumBytesBilled\":\"9223372036854775807\""))
  assert_true(raw.contains("\"useLegacySql\":false"))
  assert_eq(
    query_job_reference(qjob()),
    ("acme-project", "original_job-1", "EU"),
  )
}

///|
test "query Job material is bounded before it can become a request candidate" {
  let projection = qprojection([field("name", "STRING")])
  assert_true(
    prepare_query_job_material(projection, qjob(), -1L, 4096)
    is Err(InvalidQueryLimits),
  )
  assert_true(
    prepare_query_job_material(projection, qjob(), 0L, 1) is Err(QueryLimit),
  )
  assert_true(prepare_query_job_material(projection, qjob(), 0L, 4096) is Ok(_))
}
