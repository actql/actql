///|
fn managed_whole_kintone_form() -> Bytes {
  b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\"}}}"
}

///|
fn managed_whole_kintone_declaration() -> @kintone_host.RecordDeclaration {
  let catalog = @kintone_catalog.project_form_fields(
    managed_whole_kintone_form(),
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
    ["Subject"],
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
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 1,
      max_fields: 16,
    },
  ).unwrap()
}

///|
// Native original/contract law only. No provider I/O or complete reader quote
// is claimed by this fixture's Common WholeInput preparation.
test "Kintone native managed protocol adopts genuine WholeInput and its exact contracts" {
  let original = managed_whole_kintone_declaration()
  let declaration = @kintone_host.record_declaration(original)
  let document =
    #|{"version":"actql/0.1","id":"kintone-whole-native","stages":[{"id":"read","inputs":{"remote":{"connector":"kintone","resource":"inquiries"}},"steps":[{"select":["$id","Subject"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["$id","Subject"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(pure_provider_environment(declaration)),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("native Kintone WholeInput must check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  reserve_request_program_plan(parent, input).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "kintone-whole-native",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(source_original) else {
    fail("genuine WholeInput route")
  }
  let sequence = @publication_host.prepare_prepared_client_full_sequence(
    prepared,
    0,
    @publication_host.prepared_client_values_sequence_limits(prepared),
  ).unwrap()
  let acquisition = @row_source_host.prepare_row_input_acquisition(
    source_original,
    @checked.source_identity(
      @strategy.graph_program(@publication_host.prepared_client_graph(prepared)),
    ),
    sequence,
    contracts.original.value.contracts,
    declaration,
    {
      max_rows: 128,
      page: { max_bytes: 8192, max_nodes: 1000, max_depth: 20, max_rows: 128, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 2,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
  ).unwrap()
  @row_source_host.check_row_input_acquisition_original(
    acquisition, declaration, source_original,
  ).unwrap()
  @row_source_host.check_row_input_acquisition_declaration(
    acquisition, declaration,
  ).unwrap()
  let adopt = fn(original) {
    @kintone_host.adopt_managed_record_whole(
      original,
      acquisition,
      {
        max_bytes: 8192,
        max_nodes: 1000,
        max_depth: 16,
        max_rows: 4,
        max_columns: 8,
        max_cells: 32,
        max_table_rows: 16,
      },
      {
        max_columns: 8,
        max_name_bytes: 128,
        max_nodes: 1000,
        max_depth: 16,
        max_text_bytes: 8192,
      },
      100,
      2,
    )
  }
  let equal_declaration = managed_whole_kintone_declaration()
  assert_eq(
    @kintone_host.record_declaration(equal_declaration).catalog_cid,
    declaration.catalog_cid,
  )
  assert_true(adopt(equal_declaration) is Err(_))
  let read = adopt(original).unwrap()
  assert_true(@kintone_host.managed_record_whole_matches(read, acquisition))
  @kintone_host.managed_record_recheck_form(
    read,
    managed_whole_kintone_form(),
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
  let rows = @kintone_host.managed_record_project_page(
    read, b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"1\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original\"}}],\"totalCount\":null}",
  ).unwrap()
  assert_eq(rows.length(), 1)
  for index in 0..<rows[0].length() {
    assert_true(
      physical_equal(
        rows[0][index].contract,
        @row_source_host.row_input_acquisition_column_contract(
          acquisition, index,
        ).unwrap(),
      ),
    )
  }
  assert_true(
    @row_source_host.row_input_acquisition_column_contract(acquisition, -1)
    is None,
  )
  assert_false(@kintone_host.managed_record_complete(read))
  @kintone_host.managed_record_recheck_form(
    read,
    managed_whole_kintone_form(),
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
  assert_true(@kintone_host.managed_record_complete(read))
  @kintone_host.retire_managed_record(read)
  assert_false(@kintone_host.managed_record_whole_matches(read, acquisition))
}
