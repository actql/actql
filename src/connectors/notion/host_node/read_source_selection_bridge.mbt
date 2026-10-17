///|
#export_name("notionReadDatabaseDeclarationSourceCid")
pub fn notion_read_database_declaration_source_cid(
  declaration : @catalog.NotionDatabaseReadDeclaration,
) -> String {
  @catalog.notion_database_read_declaration_source_cid(declaration)
}

///|
#export_name("notionReadDatabaseDeclarationSourceBytes")
pub fn notion_read_database_declaration_source_bytes(
  declaration : @catalog.NotionDatabaseReadDeclaration,
) -> Int {
  @catalog.notion_database_read_declaration_source_bytes(declaration)
}

///|
#export_name("notionSelectReadSource")
pub fn notion_select_read_source(
  declaration : @catalog.NotionDatabaseReadDeclaration,
  database : @catalog.NotionDatabaseCatalog,
  max_work : Int,
) -> Result[
  @catalog.NotionReadSourceSelection,
  @catalog.NotionReadContractIssue,
] {
  @catalog.select_notion_read_source(declaration, database, max_work)
}

///|
#export_name("notionReadSourceSelectionMatches")
pub fn notion_read_source_selection_matches(
  selection : @catalog.NotionReadSourceSelection,
  declaration : @catalog.NotionDatabaseReadDeclaration,
  database : @catalog.NotionDatabaseCatalog,
) -> Bool {
  @catalog.notion_read_source_selection_matches(
    selection, declaration, database,
  )
}

///|
#export_name("notionReadSourceSelectionId")
pub fn notion_read_source_selection_id(
  selection : @catalog.NotionReadSourceSelection,
) -> String {
  @catalog.notion_read_source_selection_id(selection)
}

///|
#export_name("notionProjectSelectedReadSource")
pub fn notion_project_selected_read_source(
  selection : @catalog.NotionReadSourceSelection,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
) -> Result[@catalog.NotionDataSourceCatalog, @catalog.NotionReadContractIssue] {
  @catalog.project_notion_selected_read_source(selection, bytes, {
    max_bytes,
    max_nodes,
    max_depth,
    max_data_sources,
    max_properties,
    max_identity_bytes,
    max_name_bytes,
  })
}

///|
#export_name("notionBindSelectedReadContracts")
pub fn notion_bind_selected_read_contracts(
  selection : @catalog.NotionReadSourceSelection,
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
  @catalog.bind_notion_selected_read_contracts(selection, source, {
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
