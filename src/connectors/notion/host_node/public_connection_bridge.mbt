///|
#export_name("notionReadPublicConnection")
pub fn notion_read_public_connection(
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
  max_reference_bytes : Int,
) -> Result[@catalog.NotionPublicConnection, @catalog.NotionReadContractIssue] {
  @catalog.read_notion_public_connection(
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
    max_reference_bytes,
  )
}

///|
#export_name("notionPublicConnectionHasDatabases")
pub fn notion_public_connection_has_databases(
  value : @catalog.NotionPublicConnection,
) -> Result[Bool, @catalog.NotionReadContractIssue] {
  @catalog.notion_public_connection_databases(value).map(databases => {
    databases is Some(_)
  })
}

///|
#export_name("notionPublicConnectionDatabases")
pub fn notion_public_connection_databases(
  value : @catalog.NotionPublicConnection,
) -> Result[
  @catalog.NotionDatabaseReadDeclarations,
  @catalog.NotionReadContractIssue,
] {
  match @catalog.notion_public_connection_databases(value) {
    Ok(Some(databases)) => Ok(databases)
    Ok(None) => Err(@catalog.InvalidSelection)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("notionPublicConnectionCredentialKind")
pub fn notion_public_connection_credential_kind(
  value : @catalog.NotionPublicConnection,
) -> Result[String, @catalog.NotionReadContractIssue] {
  @catalog.notion_public_connection_credential_kind(value)
}

///|
#export_name("notionPublicConnectionCredentialReference")
pub fn notion_public_connection_credential_reference(
  value : @catalog.NotionPublicConnection,
) -> Result[String, @catalog.NotionReadContractIssue] {
  @catalog.notion_public_connection_credential_reference(value)
}

///|
#export_name("notionPublicConnectionSourceCid")
pub fn notion_public_connection_source_cid(
  value : @catalog.NotionPublicConnection,
) -> Result[String, @catalog.NotionReadContractIssue] {
  @catalog.notion_public_connection_source_cid(value)
}

///|
#export_name("notionPublicConnectionOriginalJson")
pub fn notion_public_connection_original_json(
  value : @catalog.NotionPublicConnection,
  max_bytes : Int,
) -> Result[String, @catalog.NotionReadContractIssue] {
  @catalog.notion_public_connection_original_json(value, max_bytes)
}
