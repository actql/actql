///|
priv enum ReferenceHop {
  RefField(String, Bool)
  RefEach
}

///|
priv enum ReferenceRoute {
  ReferenceRoute(Bool, Array[ReferenceHop], String)
}

///|
priv enum ReferenceFrame {
  RefVisit(@decode.Cursor, Int)
  RefNext(@decode.Cursor, Int, Int, Int)
}

///|
pub(all) struct ReferenceLimits {
  max_work : Int
  max_references : Int
}

///|
pub(all) enum ReferenceIssueKind {
  InvalidLimits
  WorkLimit
  ReferenceLimit
  InvalidSlot
  Resolution(CatalogIssue)
} derive(Eq, Debug)

///|
pub(all) struct ReferenceIssue {
  kind : ReferenceIssueKind
  source : @decode.Cursor?
}

///|
struct CatalogReference {
  catalog : Catalog
  item : Member
  source : @decode.Cursor
  contract : ContractEnvelope
}

///|
struct CatalogReferences {
  contents : CatalogContents
  references : Array[CatalogReference]
  work : Int
}

///|
priv struct ReferenceReader {
  limits : ReferenceLimits
  mut work : Int
  references : Array[CatalogReference]
}

///|
priv suberror ReferenceStop {
  ReferenceStop(ReferenceIssue)
}

///|
fn[T] ref_fail(
  kind : ReferenceIssueKind,
  source : @decode.Cursor,
) -> T raise ReferenceStop {
  raise ReferenceStop({ kind, source: Some(source), })
}

///|
fn ref_charge(
  reader : ReferenceReader,
  amount : Int,
  source : @decode.Cursor,
) -> Unit raise ReferenceStop {
  if amount > reader.limits.max_work - reader.work {
    ref_fail(WorkLimit, source)
  }
  reader.work += amount
}

///|
fn ref_object(
  reader : ReferenceReader,
  source : @decode.Cursor,
) -> @decode.ObjectView raise ReferenceStop {
  let count = match @decode.object_length(source) {
    Some(n) => n
    None => ref_fail(InvalidSlot, source)
  }
  ref_charge(reader, count, source)
  // Charge key text before building a lookup Map, even in a partially validated
  // container with many unexpected fields. The schema validator runs separately.
  for i in 0..<count {
    ref_charge(reader, @decode.field_at(source, i).unwrap().0.length(), source)
  }
  @decode.open_object(source).unwrap()
}

///|
fn read_reference(
  reader : ReferenceReader,
  catalog : Catalog,
  item : Member,
  source : @decode.Cursor,
  kind : String,
) -> Unit raise ReferenceStop {
  if reader.references.length() >= reader.limits.max_references {
    ref_fail(ReferenceLimit, source)
  }
  ignore(ref_object(reader, source))
  let obj = match @decode.closed_object(source, ["id", "version", "cid"]) {
    Ok(v) => v
    Err(_) => ref_fail(InvalidSlot, source)
  }
  let fields = []
  for name in ["id", "version", "cid"] {
    let value = string(obj, name) catch { _ => "" }
    if value == "" {
      ref_fail(InvalidSlot, source)
    }
    ref_charge(reader, value.length(), source)
    fields.push(value)
  }
  let entry = match
    resolve_catalog_contract(catalog, fields[0], fields[1], fields[2], kind) {
    Ok(v) => v
    Err(e) => ref_fail(Resolution(e), source)
  }
  reader.references.push({ catalog, item, source, contract: entry, })
}

///|
/// Checks every declared role slot, not just references used by Program inputs.
/// This is reference closure, not SourceView/Command body or issuer admission.
pub fn check_catalog_references(
  contents : CatalogContents,
  limits : ReferenceLimits,
) -> Result[CatalogReferences, ReferenceIssue] {
  if limits.max_work < 0 || limits.max_references < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let reader = { limits, work: 0, references: [], }
  let routes = catalog_reference_routes()
  try {
    for catalog in contents.entries {
      ref_charge(reader, 1, member_body(catalog.item))
      for is_view in [true, false] {
        let items = if is_view { catalog.views } else { catalog.commands }
        for item in items {
          let root = member_body(item)
          ref_charge(reader, 1, root)
          for route in routes {
            let ReferenceRoute(for_view, hops, kind) = route
            if for_view != is_view {
              continue
            }
            let pending = [RefVisit(root, 0)]
            while pending.pop() is Some(frame) {
              match frame {
                RefNext(array, i, count, next) =>
                  if i < count {
                    ref_charge(reader, 1, array)
                    pending.push(RefNext(array, i + 1, count, next))
                    pending.push(
                      RefVisit(@decode.element_at(array, i).unwrap(), next),
                    )
                  }
                RefVisit(source, hop) => {
                  ref_charge(reader, 1, source)
                  if hop == hops.length() {
                    read_reference(reader, catalog, item, source, kind)
                    continue
                  }
                  match hops[hop] {
                    RefField(name, required) => {
                      let obj = ref_object(reader, source)
                      match @decode.lookup(obj, name) {
                        Some(child) => pending.push(RefVisit(child, hop + 1))
                        None => if required { ref_fail(InvalidSlot, source) }
                      }
                    }
                    RefEach => {
                      let count = match @decode.array_length(source) {
                        Some(v) => v
                        None => ref_fail(InvalidSlot, source)
                      }
                      pending.push(RefNext(source, 0, count, hop + 1))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    Ok({ contents, references: reader.references, work: reader.work, })
  } catch {
    ReferenceStop(issue) => Err(issue)
  }
}

///|
pub fn reference_contents(v : CatalogReferences) -> CatalogContents {
  v.contents
}

///|
pub fn reference_usage(v : CatalogReferences) -> (Int, Int) {
  (v.work, v.references.length())
}

///|
pub fn catalog_reference_at(
  v : CatalogReferences,
  i : Int,
) -> CatalogReference? {
  v.references.get(i)
}

///|
pub fn reference_catalog(v : CatalogReference) -> Catalog {
  v.catalog
}

///|
pub fn reference_member(v : CatalogReference) -> Member {
  v.item
}

///|
pub fn reference_source(v : CatalogReference) -> @decode.Cursor {
  v.source
}

///|
pub fn reference_contract(v : CatalogReference) -> ContractEnvelope {
  v.contract
}
