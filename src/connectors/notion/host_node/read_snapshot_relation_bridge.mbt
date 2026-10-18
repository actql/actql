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
  resources : Array[String],
  snapshots : Array[@catalog.NotionDatabaseReadSnapshot],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_views : Int,
  max_alias_work : Int,
) -> Result[String, @catalog.NotionReadSnapshotIssue] {
  if resources.length() != snapshots.length() {
    return Err(@catalog.InvalidSnapshot)
  }
  if max_views < 0 || max_alias_work < 0 {
    return Err(@catalog.InvalidLimits)
  }
  // Bound the temporary pair backing before constructing it. The Catalog
  // owner charges all alias occurrences and comparisons under the same cap.
  if resources.length() > max_views || resources.length() > max_alias_work {
    return Err(@catalog.BudgetExceeded)
  }
  let views = []
  for index in 0..<resources.length() {
    views.push((resources[index], snapshots[index]))
  }
  @catalog.notion_database_read_snapshots_relation_specification(
    views,
    { max_bytes, max_nodes, max_depth, },
    max_views,
    max_alias_work,
  )
}
