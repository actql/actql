///|
test "Node declared-file profile bridge binds original declaration and forwards actual geometry" {
  let schema =
    #|{"body":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"},"mime":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"version":{"nullable":false,"type":"string"}}
  let logical =
    #|{"content":{"nullable":false,"type":"content_ref"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}}
  let request =
    #|{"additional_properties":false,"fields":{"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}
  let acquisition =
    #|{"authority":"read_content","correlation":{"cardinality":"one","identity":["resource","version"],"request_fields":["resource","version"],"response_fields":["resource","version"]},"kind":"fetch"}
  let views : Array[@client_row_source_host.RowRelationViewSpec] = []
  for (resource, body) in [("records", schema), ("contents", logical)] {
    let original = @identity.from_json(@json.parse(body), 1024, 20, 16384)
    views.push({
      resource,
      resource_kind: "file",
      schema_wire: body,
      schema_cid: @identity.cid_value(original, 16384, 1024, 20),
      request_schema_wire: if resource == "contents" {
        Some(request)
      } else {
        None
      },
      facts_wire: None,
      acquisition_wire: if resource == "contents" {
        Some(acquisition)
      } else {
        None
      },
    })
  }
  let original = @client_row_source_host.generate_relation_row_declaration(
    "bridge-file",
    "fixture",
    "fixture/0.1",
    views,
    {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 32,
      max_views: 2,
      max_fields: 10,
    },
  ).unwrap()
  let quote = client_program_row_source_file_read_profile_construction_capacity(
    original,
    original,
    "id",
    "name",
    "version",
    "mime",
    "body",
    None,
    ["files"],
    ["id"],
    0,
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(quote) > 0L)
  let bound = client_program_row_source_bind_file_read_profile(
    original,
    "contents",
    original,
    "records",
    "id",
    "name",
    "version",
    "mime",
    "body",
    None,
    ["files"],
    ["id"],
  ).unwrap()
  let view = bound.views
    .iter()
    .find_first(view => view.resource == "contents")
    .unwrap()
  let profile = client_program_row_source_file_read_profile(
    bound,
    view.source_ref,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_name(profile),
    "declared_file_content_read",
  )
  assert_true(
    client_program_row_source_file_read_profile_matches(
      bound,
      view.source_ref,
      original,
      "records",
      "id",
      "name",
      "version",
      "mime",
      "body",
      None,
      ["files"],
      ["id"],
    ),
  )
  assert_false(
    client_program_row_source_file_read_profile_matches(
      bound,
      view.source_ref,
      original,
      "records",
      "id",
      "name",
      "version",
      "mime",
      "changed",
      None,
      ["files"],
      ["id"],
    ),
  )
}
