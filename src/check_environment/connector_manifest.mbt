///|
pub(all) enum ConnectorManifestIssue {
  InvalidManifest
  InvalidEntry(Int)
  UnsortedEntries
  DuplicateConnector(String)
  /// No Catalog of this connection id and version is in the environment.
  CatalogMismatch(String)
  BudgetExceeded
} derive(Eq, Debug)

///|
/// One admitted connector entry of the `actql-connectors/0.1` manifest. Its
/// CID is the canonical hash of the entry body alone, so adding another
/// connector or regenerating a Catalog does not change it.
pub struct ConnectorManifestEntry {
  cid : String
  connector : String
  connector_id : String
  connector_version : String
}

///|
pub struct ConnectorManifest {
  entries : Array[ConnectorManifestEntry]
}

///|
priv suberror ManifestStop {
  ManifestStop(ConnectorManifestIssue)
}

///|
fn manifest_text(
  object : @decode.ObjectView,
  name : String,
  issue : ConnectorManifestIssue,
) -> String raise ManifestStop {
  guard @decode.lookup(object, name) is Some(value) &&
    @decode.text(value) is Ok(text) &&
    text != "" else {
    raise ManifestStop(issue)
  }
  text
}

///|
/// Admit the environment's connector manifest. Every entry must name a
/// Connector Catalog of the same connection id and version in this
/// environment. An environment without a manifest has no entries. Admission
/// is neither an installed implementation nor current authority.
pub fn check_connector_manifest(
  environment : WireEnvironment,
  limits : Limits,
) -> Result[ConnectorManifest, ConnectorManifestIssue] {
  guard environment.manifest is Some(root) else { return Ok({ entries: [], }) }
  try {
    let object = match @decode.closed_object(root, ["version", "connectors"]) {
      Ok(value) => value
      Err(_) => raise ManifestStop(InvalidManifest)
    }
    if manifest_text(object, "version", InvalidManifest) !=
      "actql-connectors/0.1" {
      raise ManifestStop(InvalidManifest)
    }
    guard @decode.lookup(object, "connectors") is Some(list) &&
      @decode.array_length(list) is Some(count) else {
      raise ManifestStop(InvalidManifest)
    }
    if count > limits.max_members {
      raise ManifestStop(BudgetExceeded)
    }
    let catalogs : Map[String, String] = Map([])
    for index in 0..<member_count(environment, ConnectorCatalogs) {
      let catalog = member_body(
        member_at(environment, ConnectorCatalogs, index).unwrap(),
      )
      guard @decode.open_object(catalog) is Ok(view) &&
        @decode.lookup(view, "connector_id") is Some(id) &&
        @decode.text(id) is Ok(connector_id) &&
        @decode.lookup(view, "connector_version") is Some(version) &&
        @decode.text(version) is Ok(connector_version) else {
        raise ManifestStop(InvalidManifest)
      }
      catalogs[connector_id] = connector_version
    }
    let entries = []
    let seen : Map[String, Bool] = Map([])
    let mut previous : String? = None
    for index in 0..<count {
      let cursor = @decode.element_at(list, index).unwrap()
      let entry = match
        @decode.closed_object(cursor, [
          "connector", "connector_id", "connector_version",
        ]) {
        Ok(value) => value
        Err(_) => raise ManifestStop(InvalidEntry(index))
      }
      let connector = manifest_text(entry, "connector", InvalidEntry(index))
      let connector_id = manifest_text(
        entry,
        "connector_id",
        InvalidEntry(index),
      )
      let connector_version = manifest_text(
        entry,
        "connector_version",
        InvalidEntry(index),
      )
      let cid = hash(cursor, limits, false).0 catch {
          _ => raise ManifestStop(BudgetExceeded)
        }
      if previous is Some(before) && !(before < cid) {
        raise ManifestStop(UnsortedEntries)
      }
      previous = Some(cid)
      if seen.contains(connector_id) {
        raise ManifestStop(DuplicateConnector(connector_id))
      }
      seen[connector_id] = true
      if catalogs.get(connector_id) != Some(connector_version) {
        raise ManifestStop(CatalogMismatch(connector_id))
      }
      entries.push({ cid, connector, connector_id, connector_version, })
    }
    Ok({ entries, })
  } catch {
    ManifestStop(issue) => Err(issue)
  }
}

///|
pub fn connector_manifest_entry(
  manifest : ConnectorManifest,
  cid : String,
) -> ConnectorManifestEntry? {
  match manifest.entries.search_by(entry => entry.cid == cid) {
    Some(index) => Some(manifest.entries[index])
    None => None
  }
}

///|
pub fn connector_manifest_entry_identity(
  entry : ConnectorManifestEntry,
) -> (String, String, String, String) {
  (entry.cid, entry.connector, entry.connector_id, entry.connector_version)
}
