///|
pub(all) suberror SalesforceDeclarationBridgeIssue {
  UnknownRevision
  Declaration(@catalog.DeclarationIssue)
  DeclaredUse(@catalog.DeclarationUseIssue)
  OutputLimit
}

///|
/// The installed revision's implementation, from the revision string the
/// Site profile fixes. There is no way to supply capability flags.
#export_name("salesforceImplementation")
pub fn salesforce_implementation(
  connector_revision : String,
) -> @catalog.SalesforceImplementation raise SalesforceDeclarationBridgeIssue {
  match @catalog.salesforce_implementation(connector_revision) {
    Some(value) => value
    None => raise UnknownRevision
  }
}

///|
#export_name("salesforceGenerateStaticDeclaration")
pub fn salesforce_generate_static_declaration(
  observation : @catalog.CatalogObservation,
  tenant : String,
  principal : String,
  environment : String,
  connection_revision : String,
  org_id : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
  sync_occurrence : String,
  implementation : @catalog.SalesforceImplementation,
  connector_id : String,
  resource_names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.StaticDeclaration raise SalesforceDeclarationBridgeIssue {
  let current : @catalog.CatalogObservationBinding = {
    tenant,
    principal,
    environment,
    connection_revision,
    org_id,
    site_key,
    site_generation,
    connector_registration,
    connector_revision,
    resource_origin,
    run_invocation_cid,
    dispatch_request_cid,
    sync_occurrence,
  }
  match
    @catalog.generate_static_declaration(
      observation,
      current,
      implementation,
      connector_id,
      resource_names,
      { max_bytes, max_nodes, max_depth, },
    ) {
    Ok(value) => value
    Err(issue) => raise Declaration(issue)
  }
}

///|
#export_name("salesforceStaticDeclarationJson")
pub fn salesforce_static_declaration_json(
  declaration : @catalog.StaticDeclaration,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise SalesforceDeclarationBridgeIssue {
  match
    @catalog.static_declaration_json(declaration, {
      max_bytes,
      max_nodes,
      max_depth,
    }) {
    Some(text) => text
    None => raise OutputLimit
  }
}

///|
#export_name("salesforceCheckDeclaredSingleWrite")
pub fn salesforce_check_declared_single_write(
  declaration : @catalog.StaticDeclaration,
  request : @catalog.SingleWriteRequest,
) -> Unit raise SalesforceDeclarationBridgeIssue {
  match @catalog.check_declared_single_write(declaration, request) {
    Ok(_) => ()
    Err(issue) => raise DeclaredUse(issue)
  }
}

///|
#export_name("salesforceCheckDeclaredCollectionWrite")
pub fn salesforce_check_declared_collection_write(
  declaration : @catalog.StaticDeclaration,
  request : @catalog.WriteCollectionRequest,
) -> Unit raise SalesforceDeclarationBridgeIssue {
  match @catalog.check_declared_collection_write(declaration, request) {
    Ok(_) => ()
    Err(issue) => raise DeclaredUse(issue)
  }
}

///|
#export_name("salesforceCheckDeclaredRead")
pub fn salesforce_check_declared_read(
  declaration : @catalog.StaticDeclaration,
  plan : @catalog.ReadProjection,
  source_view_cid : String,
) -> Unit raise SalesforceDeclarationBridgeIssue {
  match @catalog.check_declared_read(declaration, plan, source_view_cid) {
    Ok(_) => ()
    Err(issue) => raise DeclaredUse(issue)
  }
}
