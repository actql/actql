///|
pub(all) enum CatalogIssue {
  InvalidLimits
  BudgetExceeded
  InvalidCatalog(Int)
  IdentityMismatch(Int)
  OwnershipMismatch(Int)
  DuplicateConnector(String)
  DuplicateSelector(String)
  UnsortedContents(Int, Section)
  DerivedMismatch(Section)
  Contract(ContractIssue)
  OutsideCatalog(String, String)
} derive(Eq, Debug)

///|
struct CatalogContents {
  registry : ContractRegistry
  entries : Array[Catalog]
  bytes : Int
  nodes : Int
  items : Int
}

///|
struct Catalog {
  item : Member
  connector : String
  version : String
  cid : String
  contracts : Map[String, Bool]
  views : Array[Member]
  commands : Array[Member]
  registry : ContractRegistry
}

///|
priv suberror CatalogStop {
  CatalogStop(CatalogIssue)
}

///|
fn catalog_string(
  o : @decode.ObjectView,
  name : String,
  index : Int,
) -> String raise CatalogStop {
  let value = string(o, name) catch {
    _ => raise CatalogStop(InvalidCatalog(index))
  }
  if value == "" {
    raise CatalogStop(InvalidCatalog(index))
  }
  value
}

///|
fn catalog_hash(
  root : @decode.Cursor,
  self_field : String?,
  limits : Limits,
) -> (String, Int, Int) raise CatalogStop {
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_except(root, writer, self_field)
    let (digest, bytes, nodes) = @encode.finish_hash_usage(writer)
    ("sha256:" + digest, bytes, nodes)
  } catch {
    _ => raise CatalogStop(BudgetExceeded)
  }
}

///|
/// Integrity, ownership, selectors and exact derived membership only. SourceView
/// and Command shape/semantics and their role references still require admission.
pub fn check_catalog_contents(
  registry : ContractRegistry,
  limits : Limits,
) -> Result[CatalogContents, CatalogIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_members < 0 {
    return Err(InvalidLimits)
  }
  let environment = registry.environment
  let count = member_count(environment, ConnectorCatalogs)
  if count > limits.max_members {
    return Err(BudgetExceeded)
  }
  // Index each derived section once. No per-Catalog rebuilding or linear search.
  let indices : Array[Map[String, Member]] = []
  for section in [SourceViews, CommandContracts, ContractRegistry] {
    let map : Map[String, Member] = Map([])
    let length = member_count(environment, section)
    if length > limits.max_members {
      return Err(BudgetExceeded)
    }
    for i in 0..<length {
      let item = member_at(environment, section, i).unwrap()
      if map.contains(member_cid(item)) {
        return Err(DerivedMismatch(section))
      }
      map[member_cid(item)] = item
    }
    indices.push(map)
  }
  let used : Array[Map[String, Bool]] = [Map([]), Map([]), Map([])]
  let connectors : Map[String, Bool] = Map([])
  let views_seen : Map[(String, String, String), Bool] = Map([])
  let commands_seen : Map[String, Bool] = Map([])
  let entries = []
  let mut bytes = 0
  let mut nodes = 0
  let mut items = count
  try {
    for i in 0..<count {
      let item = member_at(environment, ConnectorCatalogs, i).unwrap()
      let root = member_body(item)
      let object = match
        @decode.closed_object(root, [
          "schema", "connector_id", "connector_version", "source_views", "commands",
          "contracts", "catalog_cid",
        ]) {
        Ok(v) => v
        Err(_) => raise CatalogStop(InvalidCatalog(i))
      }
      if catalog_string(object, "schema", i) != "actql.connector_catalog/0.1" {
        raise CatalogStop(InvalidCatalog(i))
      }
      let connector = catalog_string(object, "connector_id", i)
      let version = catalog_string(object, "connector_version", i)
      let cid = catalog_string(object, "catalog_cid", i)
      if connectors.contains(connector) {
        raise CatalogStop(DuplicateConnector(connector))
      }
      connectors[connector] = true
      let remaining = {
        ..limits,
        max_bytes: limits.max_bytes - bytes,
        max_nodes: limits.max_nodes - nodes,
      }
      let (_, size, n) = catalog_hash(root, None, remaining)
      let (expected, _, _) = catalog_hash(root, Some("catalog_cid"), remaining)
      if cid != expected {
        raise CatalogStop(IdentityMismatch(i))
      }
      bytes += size
      nodes += n
      let contracts : Map[String, Bool] = Map([])
      let views = []
      let commands = []
      for s in 0..<3 {
        let (name, section, self_field) = match s {
          0 => ("source_views", SourceViews, "contract_cid")
          1 => ("commands", CommandContracts, "contract_cid")
          _ => ("contracts", ContractRegistry, "cid")
        }
        let array = match @decode.lookup(object, name) {
          Some(v) => v
          None => raise CatalogStop(InvalidCatalog(i))
        }
        let length = match @decode.array_length(array) {
          Some(v) => v
          None => raise CatalogStop(InvalidCatalog(i))
        }
        if length > limits.max_members - items {
          raise CatalogStop(BudgetExceeded)
        }
        items += length
        let mut previous : String? = None
        for j in 0..<length {
          let child = @decode.element_at(array, j).unwrap()
          let obj = match @decode.open_object(child) {
            Ok(v) => v
            Err(_) => raise CatalogStop(InvalidCatalog(i))
          }
          let identity = catalog_string(obj, self_field, i)
          if previous is Some(p) && p >= identity {
            raise CatalogStop(UnsortedContents(i, section))
          }
          previous = Some(identity)
          let (full, _, _) = catalog_hash(child, None, limits)
          let matched = match indices[s].get(full) {
            Some(v) => v
            None => raise CatalogStop(DerivedMismatch(section))
          }
          if s == 2 {
            // Exact full-body equality with an already checked registry envelope
            // also proves shape and self-CID; do not reinterpret body contents.
            contracts[identity] = true
          } else {
            let (expected, _, _) = catalog_hash(child, Some(self_field), limits)
            if expected != identity {
              raise CatalogStop(IdentityMismatch(i))
            }
            if catalog_string(obj, "connector_id", i) != connector {
              raise CatalogStop(OwnershipMismatch(i))
            }
            if s == 0 {
              if catalog_string(obj, "schema", i) != "actql.source_view/0.1" {
                raise CatalogStop(InvalidCatalog(i))
              }
              if catalog_string(obj, "connector_version", i) != version {
                raise CatalogStop(OwnershipMismatch(i))
              }
              let resource = catalog_string(obj, "resource_kind", i)
              let view = catalog_string(obj, "view_id", i)
              ignore(catalog_string(obj, "view_version", i))
              let key = (connector, resource, view)
              if views_seen.contains(key) {
                raise CatalogStop(DuplicateSelector(view))
              }
              views_seen[key] = true
              views.push(matched)
            } else {
              if catalog_string(obj, "schema", i) !=
                "actql.command_contract/0.1" {
                raise CatalogStop(InvalidCatalog(i))
              }
              let command = catalog_string(obj, "command_id", i)
              ignore(catalog_string(obj, "version", i))
              if commands_seen.contains(command) {
                raise CatalogStop(DuplicateSelector(command))
              }
              commands_seen[command] = true
              commands.push(matched)
            }
          }
          used[s][full] = true
        }
      }
      entries.push({
        item,
        connector,
        version,
        cid,
        contracts,
        views,
        commands,
        registry,
      })
    }
    for s in 0..<3 {
      if used[s].length() != indices[s].length() {
        raise CatalogStop(
          DerivedMismatch(
            match s {
              0 => SourceViews
              1 => CommandContracts
              _ => ContractRegistry
            },
          ),
        )
      }
    }
    Ok({ registry, entries, bytes, nodes, items, })
  } catch {
    CatalogStop(issue) => Err(issue)
  }
}

///|
pub fn catalog_registry(v : CatalogContents) -> ContractRegistry {
  v.registry
}

///|
pub fn catalog_usage(v : CatalogContents) -> (Int, Int, Int) {
  (v.bytes, v.nodes, v.items)
}

///|
pub fn catalog_at(v : CatalogContents, i : Int) -> Catalog? {
  v.entries.get(i)
}

///|
pub fn catalog_member(v : Catalog) -> Member {
  v.item
}

///|
pub fn catalog_identity(v : Catalog) -> (String, String, String) {
  (v.connector, v.version, v.cid)
}

///|
pub fn catalog_view_at(v : Catalog, i : Int) -> Member? {
  v.views.get(i)
}

///|
pub fn catalog_command_at(v : Catalog, i : Int) -> Member? {
  v.commands.get(i)
}

///|
pub fn resolve_catalog_contract(
  v : Catalog,
  id : String,
  version : String,
  cid : String,
  kind : String,
) -> Result[ContractEnvelope, CatalogIssue] {
  let entry = match resolve_contract(v.registry, id, version, cid, kind) {
    Ok(v) => v
    Err(e) => return Err(Contract(e))
  }
  if !v.contracts.contains(cid) {
    return Err(OutsideCatalog(id, version))
  }
  Ok(entry)
}
