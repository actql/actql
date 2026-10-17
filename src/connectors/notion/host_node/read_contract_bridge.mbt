///|
#export_name("notionReadDatabaseDeclaration")
pub fn notion_read_database_declaration(
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text_bytes : Int,
  max_columns : Int,
  max_work : Int,
) -> Result[
  @catalog.NotionDatabaseReadDeclaration,
  @catalog.NotionReadContractIssue,
] {
  @catalog.read_notion_database_read_declaration(bytes, {
    metadata: {
      max_bytes,
      max_nodes,
      max_depth,
      max_data_sources,
      max_properties,
      max_identity_bytes,
      max_name_bytes,
    },
    contracts: {
      max_nodes: contract_nodes,
      max_depth: contract_depth,
      max_text_bytes: contract_text_bytes,
    },
    max_columns,
    max_work,
  })
}

///|
#export_name("notionReadDatabaseId")
pub fn notion_read_database_id(
  declaration : @catalog.NotionDatabaseReadDeclaration,
) -> String {
  declaration.database_id
}

///|
#export_name("notionReadSourceIndex")
pub fn notion_read_source_index(
  declaration : @catalog.NotionDatabaseReadDeclaration,
  database : @catalog.NotionDatabaseCatalog,
) -> Result[Int, @catalog.NotionReadContractIssue] {
  @catalog.notion_database_read_source_index(declaration, database)
}

///|
#export_name("notionBindDataSourceReadContracts")
pub fn notion_bind_data_source_read_contracts(
  declaration : @catalog.NotionDatabaseReadDeclaration,
  source : @catalog.NotionDataSourceCatalog,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text_bytes : Int,
  max_columns : Int,
  max_work : Int,
) -> Result[
  @catalog.NotionDataSourceReadContracts,
  @catalog.NotionReadContractIssue,
] {
  @catalog.bind_notion_data_source_read_contracts(declaration, source, {
    metadata: {
      max_bytes,
      max_nodes,
      max_depth,
      max_data_sources,
      max_properties,
      max_identity_bytes,
      max_name_bytes,
    },
    contracts: {
      max_nodes: contract_nodes,
      max_depth: contract_depth,
      max_text_bytes: contract_text_bytes,
    },
    max_columns,
    max_work,
  })
}

///|
#export_name("notionDataSourceReadMatches")
pub fn notion_data_source_read_matches(
  binding : @catalog.NotionDataSourceReadContracts,
  declaration : @catalog.NotionDatabaseReadDeclaration,
  source : @catalog.NotionDataSourceCatalog,
) -> Bool {
  @catalog.notion_data_source_read_matches(binding, declaration, source)
}

///|
#export_name("notionDataSourceReadSchemaJson")
pub fn notion_data_source_read_schema_json(
  binding : @catalog.NotionDataSourceReadContracts,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionReadContractIssue] {
  @catalog.notion_data_source_read_schema_wire(
    binding, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("notionPropertyReadCellJson")
pub fn notion_property_read_cell_json(
  binding : @catalog.NotionDataSourceReadContracts,
  page : @catalog.OriginalNotionQueryPage,
  row : Int,
  column : Int,
  admission_nodes : Int,
  admission_depth : Int,
  admission_text_bytes : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionReadCellIssue] {
  guard @catalog.notion_query_page_row_at(page, row) is Some(original) else {
    return Err(@catalog.InvalidColumn)
  }
  @catalog.notion_property_read_cell_wire(
    binding,
    original,
    column,
    {
      max_nodes: admission_nodes,
      max_depth: admission_depth,
      max_text_bytes: admission_text_bytes,
    },
    max_work,
    max_bytes,
    max_nodes,
    max_depth,
  )
}
