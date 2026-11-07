///|
extern "js" fn kintone_update_copy_mapping(
  mapping : @kintone_host.RecordUpdateMapping,
) -> @kintone_host.RecordUpdateMapping =
  #| mapping => ({...mapping})

///|
fn kintone_update_bridge_declaration() -> @kintone_host.RecordDeclaration {
  let catalog = @kintone_catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\"},\"Computed\":{\"code\":\"Computed\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"server\"}}}",
    "12",
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
  @kintone_host.declare_records(
    catalog,
    None,
    ["Subject", "Computed"],
    "kintone",
    "kintone/0.1",
    "inquiries",
    {
      max_columns: 8,
      max_name_bytes: 128,
      max_nodes: 1000,
      max_depth: 16,
      max_text_bytes: 8192,
    },
    kintone_update_bridge_limits(),
  ).unwrap()
}

///|
fn kintone_update_bridge_limits() -> @client_row_source_host.RowDeclarationLimits {
  {
    max_bytes: 65536,
    max_nodes: 8192,
    max_depth: 32,
    max_views: 4,
    max_fields: 16,
  }
}

///|
test "kintone UPDATE bridge keeps original declaration full Catalog and native mapping identity" {
  let original = kintone_update_bridge_declaration()
  let mapping = client_program_kintone_prepare_update_mapping(
    original,
    "inquiries",
    [{ target: "Subject", field: "subject", null_behavior: "reject", }],
    "required",
    kintone_update_bridge_limits(),
  ).unwrap()
  assert_true(
    client_program_kintone_update_mapping_matches_declaration(mapping, original),
  )
  assert_false(
    client_program_kintone_update_mapping_matches_declaration(
      mapping,
      kintone_update_bridge_declaration(),
    ),
  )
  let body = client_program_kintone_update_mapping_body(mapping).unwrap()
  assert_true(body.contains("\"primary_identity\":\"$id\""))
  assert_true(body.contains("\"permissions\":[\"kintone:records:update\"]"))
  assert_true(
    body.contains("\"Computed\":{\"nullable\":false,\"type\":\"string\"}"),
  )
  let native = @kintone_host.record_update_mapping(mapping)
  assert_eq(
    client_program_kintone_update_mapping_ref(mapping).unwrap(),
    native.mapping_ref,
  )
  assert_eq(
    client_program_kintone_update_mapping_cid(mapping).unwrap(),
    native.mapping_cid,
  )
  for field in ["Computed", "$id", "missing"] {
    assert_true(
      client_program_kintone_prepare_update_mapping(
        original,
        "inquiries",
        [{ target: field, field: "subject", null_behavior: "reject", }],
        "required",
        kintone_update_bridge_limits(),
      )
      is Err(FieldNotWritable(_)),
    )
  }
}

///|
test "kintone UPDATE Node bridge refuses a copied private Mapping before exposing material" {
  let original = kintone_update_bridge_declaration()
  let mapping = client_program_kintone_prepare_update_mapping(
    original,
    "inquiries",
    [{ target: "Subject", field: "subject", null_behavior: "reject", }],
    "required",
    kintone_update_bridge_limits(),
  ).unwrap()
  let copied = kintone_update_copy_mapping(mapping)
  assert_false(
    client_program_kintone_update_mapping_matches_declaration(copied, original),
  )
  assert_true(
    client_program_kintone_update_mapping_body(copied)
    is Err(InvalidSpecification),
  )
  assert_true(
    client_program_kintone_update_mapping_ref(copied)
    is Err(InvalidSpecification),
  )
  assert_true(
    client_program_kintone_update_mapping_cid(copied)
    is Err(InvalidSpecification),
  )
}
