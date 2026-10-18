///|
#export_name("notionDatabaseReadSnapshotRelationSpecification")
pub fn notion_database_read_snapshot_relation_specification(
  snapshot : @catalog.NotionDatabaseReadSnapshot,
  resource : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionReadSnapshotIssue] {
  @catalog.notion_database_read_snapshot_relation_specification(
    snapshot,
    resource,
    { max_bytes, max_nodes, max_depth, },
  )
}

///|
#export_name("notionDatabaseReadSnapshotsRelationSpecification")
pub fn notion_database_read_snapshots_relation_specification(
  views : Array[(String, @catalog.NotionDatabaseReadSnapshot)],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_views : Int,
  max_alias_work : Int,
) -> Result[String, @catalog.NotionReadSnapshotIssue] {
  @catalog.notion_database_read_snapshots_relation_specification(
    views,
    { max_bytes, max_nodes, max_depth, },
    max_views,
    max_alias_work,
  )
}
