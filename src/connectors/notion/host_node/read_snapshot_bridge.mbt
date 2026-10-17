///|
#export_name("notionCaptureDatabaseReadSnapshot")
pub fn notion_capture_database_read_snapshot(
  selection : @catalog.NotionReadSourceSelection,
  source : @catalog.NotionDataSourceCatalog,
  read_contracts : @catalog.NotionDataSourceReadContracts,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @catalog.NotionDatabaseReadSnapshot,
  @catalog.NotionReadSnapshotIssue,
] {
  @catalog.capture_notion_database_read_snapshot(
    selection,
    source,
    read_contracts,
    { max_bytes, max_nodes, max_depth, },
  )
}

///|
#export_name("notionReadDatabaseReadSnapshot")
pub fn notion_read_database_read_snapshot(
  bytes : Bytes,
  expected_source_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
  max_contract_nodes : Int,
  max_contract_depth : Int,
  max_contract_text_bytes : Int,
  max_columns : Int,
  max_work : Int,
  max_snapshot_bytes : Int,
  max_snapshot_nodes : Int,
  max_snapshot_depth : Int,
) -> Result[
  @catalog.NotionDatabaseReadSnapshot,
  @catalog.NotionReadSnapshotIssue,
] {
  @catalog.read_notion_database_read_snapshot(
    bytes,
    expected_source_cid,
    {
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
        max_nodes: max_contract_nodes,
        max_depth: max_contract_depth,
        max_text_bytes: max_contract_text_bytes,
      },
      max_columns,
      max_work,
    },
    {
      max_bytes: max_snapshot_bytes,
      max_nodes: max_snapshot_nodes,
      max_depth: max_snapshot_depth,
    },
  )
}

///|
#export_name("notionDatabaseReadSnapshotMatches")
pub fn notion_database_read_snapshot_matches(
  snapshot : @catalog.NotionDatabaseReadSnapshot,
  selection : @catalog.NotionReadSourceSelection,
  source : @catalog.NotionDataSourceCatalog,
  read_contracts : @catalog.NotionDataSourceReadContracts,
) -> Bool {
  @catalog.notion_database_read_snapshot_matches(
    snapshot, selection, source, read_contracts,
  )
}

///|
#export_name("notionDatabaseReadSnapshotWire")
pub fn notion_database_read_snapshot_wire(
  snapshot : @catalog.NotionDatabaseReadSnapshot,
) -> Result[String, @catalog.NotionReadSnapshotIssue] {
  @catalog.notion_database_read_snapshot_wire(snapshot)
}

///|
#export_name("notionDatabaseReadSnapshotSourceCid")
pub fn notion_database_read_snapshot_source_cid(
  snapshot : @catalog.NotionDatabaseReadSnapshot,
) -> Result[String, @catalog.NotionReadSnapshotIssue] {
  @catalog.notion_database_read_snapshot_source_cid(snapshot)
}

///|
#export_name("notionDatabaseReadSnapshotDeclaration")
pub fn notion_database_read_snapshot_declaration(
  snapshot : @catalog.NotionDatabaseReadSnapshot,
) -> Result[
  @catalog.NotionDatabaseReadDeclaration,
  @catalog.NotionReadSnapshotIssue,
] {
  @catalog.notion_database_read_snapshot_declaration(snapshot)
}

///|
#export_name("notionDatabaseReadSnapshotSource")
pub fn notion_database_read_snapshot_source(
  snapshot : @catalog.NotionDatabaseReadSnapshot,
) -> Result[@catalog.NotionDataSourceCatalog, @catalog.NotionReadSnapshotIssue] {
  @catalog.notion_database_read_snapshot_source(snapshot)
}

///|
#export_name("notionDatabaseReadSnapshotContracts")
pub fn notion_database_read_snapshot_contracts(
  snapshot : @catalog.NotionDatabaseReadSnapshot,
) -> Result[
  @catalog.NotionDataSourceReadContracts,
  @catalog.NotionReadSnapshotIssue,
] {
  @catalog.notion_database_read_snapshot_contracts(snapshot)
}
