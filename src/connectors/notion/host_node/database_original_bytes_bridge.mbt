///|
#export_name("notionDatabaseOriginalJson")
pub fn notion_database_original_json(
  database : @catalog.NotionDatabaseCatalog,
  max_bytes : Int,
) -> Result[String, @catalog.NotionDatabaseIssue] {
  @catalog.notion_database_original_json(database, max_bytes)
}

///|
#export_name("notionDataSourceOriginalJson")
pub fn notion_data_source_original_json(
  source : @catalog.NotionDataSourceCatalog,
  max_bytes : Int,
) -> Result[String, @catalog.NotionDatabaseIssue] {
  @catalog.notion_data_source_original_json(source, max_bytes)
}

///|
#export_name("notionDatabaseReadDeclarationOriginalJson")
pub fn notion_database_read_declaration_original_json(
  declaration : @catalog.NotionDatabaseReadDeclaration,
  max_bytes : Int,
) -> Result[String, @catalog.NotionReadContractIssue] {
  @catalog.notion_database_read_declaration_original_json(
    declaration, max_bytes,
  )
}
