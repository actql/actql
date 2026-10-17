///|
fn delete_preview_limits() -> @catalog.RecordMutationLimits {
  {
    max_records: 100,
    max_identity_bytes: 1000,
    max_comparison_work: 10000,
    max_output_bytes: 10000,
    max_output_nodes: 1000,
    max_output_depth: 16,
  }
}

///|
fn delete_preview_values() -> @catalog.RecordValueLimits {
  {
    max_columns: 8,
    max_name_bytes: 128,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
  }
}

///|
fn delete_preview_mapping(
  catalog : @catalog.FormFieldCatalog,
) -> RecordDeleteMapping {
  prepare_record_delete_mapping(
    delete_original_declaration(catalog),
    "inquiries",
    "required",
    delete_declaration_limits(),
  ).unwrap()
}

///|
test "kintone before projection retains the exact original API ID and revision guard" {
  let catalog = delete_mapping_form()
  let mapping = delete_preview_mapping(catalog)
  let request = delete_original_request(catalog)
  let target = @catalog.record_delete_request_targets(request)[0]
  let preview = prepare_record_delete_preview(
    mapping,
    target,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(record_delete_preview_identity(preview), "9007199254740993")
  assert_eq(
    record_delete_preview_version_cid(preview),
    "sha256:99944ac0d4a7f14be6fac31131cccd767d5149ae8e8c65daeb50bdeee0c087cd",
  )
  assert_eq(
    record_delete_preview_before_wire(preview),
    "{\"$id\":\"9007199254740993\",\"Subject\":\"original\"}",
  )
  assert_true(record_delete_preview_matches(preview, mapping, target))
  assert_true(
    !record_delete_preview_matches(
      preview,
      delete_preview_mapping(catalog),
      target,
    ),
  )
  let other = @catalog.record_delete_request_targets(
      delete_original_request(catalog),
    )[0]
  assert_true(!record_delete_preview_matches(preview, mapping, other))
}

///|
test "kintone before refuses equal foreign Form and incomplete original selection" {
  let catalog = delete_mapping_form()
  let mapping = delete_preview_mapping(catalog)
  let foreign = @catalog.record_delete_request_targets(
      delete_original_request(delete_mapping_form()),
    )[0]
  let incomplete = @catalog.record_delete_request_targets(
      delete_original_request(catalog, fields=[]),
    )[0]
  for target in [foreign, incomplete] {
    assert_true(
      prepare_record_delete_preview(
        mapping,
        target,
        delete_preview_values(),
        delete_preview_limits(),
      )
      is Err(ForeignDeclaration),
    )
  }
}

///|
test "kintone before output and comparison bounds refuse without partial preview" {
  let catalog = delete_mapping_form()
  let mapping = delete_preview_mapping(catalog)
  let target = @catalog.record_delete_request_targets(
      delete_original_request(catalog),
    )[0]
  let original = delete_preview_limits()
  for
    limits in [
      { ..original, max_output_bytes: 1, },
      { ..original, max_output_nodes: 1, },
      { ..original, max_comparison_work: 1, },
      { ..original, max_identity_bytes: 1, },
      { ..original, max_output_depth: 0, },
    ] {
    assert_true(
      prepare_record_delete_preview(
        mapping,
        target,
        delete_preview_values(),
        limits,
      )
      is Err(_),
    )
  }
}

///|
test "kintone before preserves checked array order duplicates and exact selected row" {
  let catalog = @catalog.project_form_fields(
    @utf8.encode(
      "{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\"},\"Tags\":{\"code\":\"Tags\",\"type\":\"MULTI_SELECT\",\"options\":{\"a\":{\"label\":\"a\"},\"b\":{\"label\":\"b\"}}}}}",
    ),
    "12",
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
  let original = declare_records(
    catalog,
    None,
    ["Tags", "Subject"],
    "kintone",
    "kintone/0.1",
    "inquiries",
    delete_preview_values(),
    delete_declaration_limits(),
  ).unwrap()
  let mapping = prepare_record_delete_mapping(
    original,
    "inquiries",
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let page = @catalog.project_record_page(
    @utf8.encode(
      "{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"1\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"2\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"first\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[]}},{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9007199254740994\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"second\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[\"b\",\"a\",\"b\"]}}],\"totalCount\":null}",
    ),
    catalog,
    ["Tags", "Subject"],
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_rows: 4,
      max_columns: 8,
      max_cells: 32,
      max_table_rows: 16,
    },
  ).unwrap()
  let first = @catalog.prepare_original_record_target(page, 0, 1000).unwrap()
  let second = @catalog.prepare_original_record_target(page, 1, 1000).unwrap()
  let view = prepare_record_delete_preview(
    mapping,
    second,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(
    record_delete_preview_before_wire(view),
    "{\"$id\":\"9007199254740993\",\"Tags\":[\"b\",\"a\",\"b\"],\"Subject\":\"second\"}",
  )
  let previous = prepare_record_delete_preview(
    mapping,
    first,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(
    record_delete_preview_before_wire(previous),
    "{\"$id\":\"1\",\"Tags\":[],\"Subject\":\"first\"}",
  )
  assert_true(
    record_delete_preview_version_cid(previous) !=
    record_delete_preview_version_cid(view),
  )
}

///|
test "kintone revision guard distinguishes exact wide revisions without changed before values" {
  let catalog = delete_mapping_form()
  let mapping = delete_preview_mapping(catalog)
  let first = @catalog.record_delete_request_targets(
      delete_original_request(catalog),
    )[0]
  let page = @catalog.project_record_page(
    @utf8.encode(
      "{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9007199254740995\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original\"}}],\"totalCount\":null}",
    ),
    catalog,
    ["Subject"],
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_rows: 4,
      max_columns: 8,
      max_cells: 32,
      max_table_rows: 16,
    },
  ).unwrap()
  let second = @catalog.prepare_original_record_target(page, 0, 1000).unwrap()
  let before = prepare_record_delete_preview(
    mapping,
    first,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  let after = prepare_record_delete_preview(
    mapping,
    second,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(
    record_delete_preview_before_wire(before),
    record_delete_preview_before_wire(after),
  )
  assert_eq(
    record_delete_preview_identity(before),
    record_delete_preview_identity(after),
  )
  assert_eq(
    record_delete_preview_version_cid(after),
    "sha256:7c1ea0d5a4f3329938d79f6d5157b2a5c3d489a418f95ac3c30cd36686bbf86c",
  )
  assert_true(
    record_delete_preview_version_cid(before) !=
    record_delete_preview_version_cid(after),
  )
}
