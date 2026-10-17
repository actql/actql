///|
#export_name("notionProjectDatabase")
pub fn notion_project_database(
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
) -> Result[@catalog.NotionDatabaseCatalog, @catalog.NotionDatabaseIssue] {
  @catalog.project_notion_database(bytes, {
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
#export_name("notionProjectDataSource")
pub fn notion_project_data_source(
  database : @catalog.NotionDatabaseCatalog,
  index : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
) -> Result[@catalog.NotionDataSourceCatalog, @catalog.NotionDatabaseIssue] {
  @catalog.project_notion_data_source(database, index, bytes, {
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
#export_name("notionDatabaseMetadataJson")
pub fn notion_database_metadata_json(
  database : @catalog.NotionDatabaseCatalog,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionDatabaseIssue] {
  @catalog.notion_database_metadata_wire(
    database, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("notionDataSourceMetadataJson")
pub fn notion_data_source_metadata_json(
  source : @catalog.NotionDataSourceCatalog,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionDatabaseIssue] {
  @catalog.notion_data_source_metadata_wire(
    source, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("notionDataSourceMatchesDatabase")
pub fn notion_data_source_matches_database(
  source : @catalog.NotionDataSourceCatalog,
  database : @catalog.NotionDatabaseCatalog,
) -> Bool {
  @catalog.notion_data_source_matches_database(source, database)
}
