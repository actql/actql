///|
pub(all) enum ClientNativeProductCensusKind {
  ProductFile
  ProductDirectory
} derive(Eq, Debug)

///|
pub(all) struct ClientNativeProductCensusMember {
  name : String
  kind : ClientNativeProductCensusKind
} derive(Eq, Debug)

///|
/// Derived expected metadata only. No Root, physical observation, resource
/// claim, source compatibility or authority is constructed by this view.
struct ClientNativeProductCensus {
  members : Array[ClientNativeProductCensusMember]
}

///|
fn product_census_push(
  members : Array[ClientNativeProductCensusMember],
  name : String,
  kind : ClientNativeProductCensusKind,
) -> Result[Unit, ClientNativeLocalRuntimeIssue] {
  match members.iter().find_first(entry => entry.name == name) {
    Some(entry) =>
      if entry.kind == kind {
        return Ok(())
      } else {
        return Err(InvalidMember)
      }
    None => ()
  }
  if members.length() >= (8192 - 5) / 5 {
    return Err(CapacityExceeded)
  }
  let mut size = name.length() + 2
  for entry in members {
    if size > 65536 - entry.name.length() - 2 {
      return Err(CapacityExceeded)
    }
    size += entry.name.length() + 2
  }
  members.push({ name, kind, })
  Ok(())
}

///|
fn product_census_sort(
  members : Array[ClientNativeProductCensusMember],
) -> Unit {
  members.sort_by((a, b) => {
    if product_inventory_path_before(a.name, b.name) {
      -1
    } else if a.name == b.name {
      0
    } else {
      1
    }
  })
}

///|
fn product_census_root(
  value : ClientNativeProductMembers,
) -> Result[ClientNativeProductCensus, ClientNativeLocalRuntimeIssue] {
  let members : Array[ClientNativeProductCensusMember] = [
    { name: "local-product-members.json", kind: ProductFile, },
  ]
  for entry in value.members {
    let parts = entry.path.split("/").to_array()
    let kind = if parts.length() == 1 { ProductFile } else { ProductDirectory }
    match product_census_push(members, parts[0].to_owned(), kind) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  product_census_sort(members)
  Ok({ members, })
}

///|
// Validate the parent with a bounded temporary root projection. This scope
// proves neither physical retirement nor GC: caller workspace must cover the
// temporary/root and child construction overlap. Unknown/empty directories are
// never discovered from physical I/O.
fn product_census_require_parent(
  value : ClientNativeProductMembers,
  parent : String,
) -> Result[Unit, ClientNativeLocalRuntimeIssue] {
  match product_census_root(value) {
    Ok(root) =>
      if root.members.any(entry => {
          entry.name == parent && entry.kind == ProductDirectory
        }) {
        Ok(())
      } else {
        Err(InvalidMember)
      }
    Err(issue) => Err(issue)
  }
}

///|
/// Project one exact payload directory from the existing formal descriptor.
/// The root requires the descriptor's one self-hash exception as a regular
/// file. Dependencies/npm placement remain a separate selected-root route;
/// this never exempts node_modules, an empty directory or an unknown entry.
/// Caller workspace/backing must cover this metadata construction separately.
pub fn client_native_product_census(
  value : ClientNativeProductMembers,
  parent : String,
) -> Result[ClientNativeProductCensus, ClientNativeLocalRuntimeIssue] {
  if parent.is_empty() {
    return product_census_root(value)
  }
  if !product_inventory_name(parent) {
    return Err(InvalidMember)
  }
  match product_census_require_parent(value, parent) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let members : Array[ClientNativeProductCensusMember] = []
  for entry in value.members {
    let parts = entry.path.split("/").to_array()
    if parts.length() == 2 && parts[0] == parent {
      match product_census_push(members, parts[1].to_owned(), ProductFile) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  product_census_sort(members)
  Ok({ members, })
}

///|
pub fn client_native_product_census_count(
  value : ClientNativeProductCensus,
) -> Int {
  value.members.length()
}

///|
pub fn client_native_product_census_at(
  value : ClientNativeProductCensus,
  index : Int,
) -> ClientNativeProductCensusMember? {
  value.members.get(index)
}
