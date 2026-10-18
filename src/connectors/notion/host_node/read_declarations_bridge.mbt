///|
#export_name("notionReadDatabaseDeclarations")
pub fn notion_read_database_declarations(
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
  max_databases : Int,
) -> Result[
  @catalog.NotionDatabaseReadDeclarations,
  @catalog.NotionReadContractIssue,
] {
  @catalog.read_notion_database_read_declarations(
    bytes,
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
        max_nodes: contract_nodes,
        max_depth: contract_depth,
        max_text_bytes: contract_text_bytes,
      },
      max_columns,
      max_work,
    },
    max_databases,
  )
}

///|
#export_name("notionDatabaseReadDeclarationsCount")
pub fn notion_database_read_declarations_count(
  declarations : @catalog.NotionDatabaseReadDeclarations,
) -> Result[Int, @catalog.NotionReadContractIssue] {
  match @catalog.notion_database_read_declarations_count(declarations) {
    Some(value) => Ok(value)
    None => Err(@catalog.ForeignOriginal)
  }
}

///|
#export_name("notionDatabaseReadDeclarationsAliasAt")
pub fn notion_database_read_declarations_alias_at(
  declarations : @catalog.NotionDatabaseReadDeclarations,
  index : Int,
) -> Result[String, @catalog.NotionReadContractIssue] {
  if @catalog.notion_database_read_declarations_count(declarations) is None {
    return Err(@catalog.ForeignOriginal)
  }
  match
    @catalog.notion_database_read_declarations_alias_at(declarations, index) {
    Some(value) => Ok(value)
    None => Err(@catalog.InvalidSelection)
  }
}

///|
#export_name("notionDatabaseReadDeclarationsAt")
pub fn notion_database_read_declarations_at(
  declarations : @catalog.NotionDatabaseReadDeclarations,
  index : Int,
) -> Result[
  @catalog.NotionDatabaseReadDeclaration,
  @catalog.NotionReadContractIssue,
] {
  if @catalog.notion_database_read_declarations_count(declarations) is None {
    return Err(@catalog.ForeignOriginal)
  }
  match @catalog.notion_database_read_declarations_at(declarations, index) {
    Some(value) => Ok(value)
    None => Err(@catalog.InvalidSelection)
  }
}

///|
#export_name("notionDatabaseReadDeclarationsMatches")
pub fn notion_database_read_declarations_matches(
  declarations : @catalog.NotionDatabaseReadDeclarations,
  index : Int,
  declaration : @catalog.NotionDatabaseReadDeclaration,
) -> Bool {
  @catalog.notion_database_read_declarations_matches(
    declarations, index, declaration,
  )
}

///|
#export_name("notionDatabaseReadDeclarationsSourceCid")
pub fn notion_database_read_declarations_source_cid(
  declarations : @catalog.NotionDatabaseReadDeclarations,
) -> Result[String, @catalog.NotionReadContractIssue] {
  match @catalog.notion_database_read_declarations_source_cid(declarations) {
    Some(value) => Ok(value)
    None => Err(@catalog.ForeignOriginal)
  }
}
