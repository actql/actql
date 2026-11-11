///|
/// Project the complete canonical parts of an existing Common declaration
/// producer without regenerating its Catalog or View identities. This is a
/// typed metadata port, not a JSON decoder, canonical admission or authority.
/// The producer supplies its own verified parts and original declared views;
/// there is deliberately no JavaScript wire entry for this constructor.
///
/// Keep the same view objects in this projection: acquisition provenance still
/// requires this exact view and the original checked QueryRequirement through
/// `check_row_acquisition_original`, not equality of their bodies or CIDs.
pub fn project_row_declaration(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  catalog : String,
  catalog_cid : String,
  contracts : Array[String],
  views : Array[RowDeclaredView],
  view_bodies : Array[String],
  manifest_entry : String,
  manifest_entry_cid : String,
) -> Result[RowDeclaration, RowDeclarationIssue] {
  if connector_id.is_empty() {
    return Err(InvalidConnectorId)
  }
  if connector_registration.is_empty() || connector_version.is_empty() {
    return Err(InvalidRegistration)
  }
  if catalog.is_empty() ||
    catalog_cid.is_empty() ||
    manifest_entry.is_empty() ||
    manifest_entry_cid.is_empty() ||
    views.length() != view_bodies.length() {
    return Err(InvalidView)
  }
  let sources : Map[String, Bool] = Map([])
  let identities : Map[String, Bool] = Map([])
  for view in views {
    if sources.contains(view.source_ref) || identities.contains(view.view_cid) {
      return Err(DuplicateName(view.source_ref))
    }
    sources[view.source_ref] = true
    identities[view.view_cid] = true
  }
  Ok({
    connector_id,
    connector_registration,
    connector_version,
    catalog,
    catalog_cid,
    contracts: contracts.copy(),
    views: views.copy(),
    view_bodies: view_bodies.copy(),
    manifest_entry,
    manifest_entry_cid,
    file_read_profiles: None,
  })
}
