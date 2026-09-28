///|
pub(all) suberror SalesforceDeclarationBridgeIssue {
  UnknownRevision
  Declaration(@catalog.DeclarationIssue)
  DeclaredUse(@catalog.DeclarationUseIssue)
  ExecutionMapping(@catalog.ExecutionMappingIssue)
  InvalidWrite
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
/// One Effect's executable Mapping from the Site's declaration. `kind` is
/// 0 create with payload `fields`, 1 create from a Result through
/// `targets`/`sources`/`null_behaviors`, 2 update by Id of `fields`, 3 upsert
/// on `key` of `fields`.
#export_name("salesforcePrepareExecutionMapping")
pub fn salesforce_prepare_execution_mapping(
  declaration : @catalog.StaticDeclaration,
  resource : String,
  kind : Int,
  fields : Array[String],
  key : String,
  targets : Array[String],
  sources : Array[String],
  null_behaviors : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.ExecutionMapping raise SalesforceDeclarationBridgeIssue {
  let write : @catalog.ExecutionWrite = match kind {
    0 => CreatePayload(fields)
    1 => {
      if targets.length() != sources.length() ||
        targets.length() != null_behaviors.length() {
        raise InvalidWrite
      }
      CreateFromResult(
        targets.mapi((index, target) => {
          target,
          source: sources[index],
          null_behavior: null_behaviors[index],
        }),
      )
    }
    2 => UpdateById(fields)
    3 => UpsertByExternalId(key, fields)
    _ => raise InvalidWrite
  }
  match
    @catalog.prepare_execution_mapping(declaration, resource, write, {
      max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(issue) => raise ExecutionMapping(issue)
  }
}

///|
#export_name("salesforceExecutionMappingRef")
pub fn salesforce_execution_mapping_ref(
  mapping : @catalog.ExecutionMapping,
) -> String {
  mapping.mapping_ref
}

///|
#export_name("salesforceExecutionMappingCid")
pub fn salesforce_execution_mapping_cid(
  mapping : @catalog.ExecutionMapping,
) -> String {
  mapping.mapping_cid
}

///|
#export_name("salesforceExecutionMappingBody")
pub fn salesforce_execution_mapping_body(
  mapping : @catalog.ExecutionMapping,
) -> String {
  mapping.body
}

///|
#export_name("salesforceCheckExecutionSingleWrite")
pub fn salesforce_check_execution_single_write(
  mapping : @catalog.ExecutionMapping,
  request : @catalog.SingleWriteRequest,
) -> Unit raise SalesforceDeclarationBridgeIssue {
  match @catalog.check_execution_single_write(mapping, request) {
    Ok(_) => ()
    Err(issue) => raise DeclaredUse(issue)
  }
}

///|
#export_name("salesforceCheckExecutionCollectionWrite")
pub fn salesforce_check_execution_collection_write(
  mapping : @catalog.ExecutionMapping,
  request : @catalog.WriteCollectionRequest,
) -> Unit raise SalesforceDeclarationBridgeIssue {
  match @catalog.check_execution_collection_write(mapping, request) {
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

///|
/// One Result row's body for an execution Mapping: only a field the Mapping
/// omits on a null source may be absent.
#export_name("salesforcePrepareExecutionWriteBody")
pub fn salesforce_prepare_execution_write_body(
  mapping : @catalog.ExecutionMapping,
  projection : @catalog.WriteProjection,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.WriteBody raise SalesforceCatalogBridgeIssue {
  match
    @catalog.prepare_execution_write_body(mapping, projection, bytes, {
      max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(issue) => raise WriteBody(issue)
  }
}

///|
/// The written value a failed row body refused, as canonical JSON, or none
/// for any other failure. `issue` is the failure of
/// `salesforcePrepareExecutionWriteBody` for `projection`.
#export_name("salesforceWriteValueRefusal")
pub fn salesforce_write_value_refusal(
  projection : @catalog.WriteProjection,
  issue : SalesforceCatalogBridgeIssue,
) -> String? {
  guard issue is WriteBody(body) else { return None }
  @catalog.write_body_value_refusal_json(body, projection)
}

///|
/// The declaration's Check Environment source evidence members, as
/// `[schema snapshots, connector capabilities]` canonical texts.
#export_name("salesforceSourceEvidenceMembers")
pub fn salesforce_source_evidence_members(
  declaration : @catalog.StaticDeclaration,
) -> Array[Array[String]] raise SalesforceDeclarationBridgeIssue {
  let (schemas, capabilities) = @salesforce_host.salesforce_source_evidence_members(
    declaration,
  ) catch {
    _ => raise OutputLimit
  }
  [schemas, capabilities]
}
