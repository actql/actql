///|
pub(all) enum LookupCompleteness {
  CompletePerRequestedKey
  HardLimitOnly
} derive(Eq, Debug)

///|
pub(all) struct LookupCapacityLimits {
  max_work : Int
  max_facts : Int
}

///|
pub(all) enum LookupCapacityIssueKind {
  InvalidLimits
  WorkLimit
  FactsLimit
  InvalidBody
} derive(Eq, Debug)

///|
pub(all) struct LookupCapacityIssue {
  kind : LookupCapacityIssueKind
  source : @decode.Cursor?
}

///|
struct LookupCapacity {
  source : @decode.Cursor
  completeness : LookupCompleteness
  rows : Int64
  pages : Int64
  bytes : Int64
}

///|
struct LookupFacts {
  envelope : ContractEnvelope
  capacity : LookupCapacity?
}

///|
struct SourceLookupFacts {
  reference : CatalogReference
  facts : LookupFacts
}

///|
struct LookupCapacities {
  references : CatalogReferences
  entries : Array[LookupFacts]
  by_cid : Map[String, LookupFacts]
  views : Map[Int, SourceLookupFacts]
  work : Int
}

///|
priv suberror LookupCapacityStop {
  LookupCapacityStop(LookupCapacityIssue)
}

///|
priv struct LookupCapacityBudget {
  limit : Int
  mut used : Int
}

///|
fn lookup_charge(
  b : LookupCapacityBudget,
  n : Int,
  c : @decode.Cursor,
) -> Unit raise LookupCapacityStop {
  if n > b.limit - b.used {
    raise LookupCapacityStop({ kind: WorkLimit, source: Some(c), })
  }
  b.used += n
}

///|
fn[T] lookup_invalid(c : @decode.Cursor) -> T raise LookupCapacityStop {
  raise LookupCapacityStop({ kind: InvalidBody, source: Some(c), })
}

///|
fn lookup_capacity_body(
  c : @decode.Cursor,
  b : LookupCapacityBudget,
) -> LookupCapacity raise LookupCapacityStop {
  if @decode.object_length(c) != Some(5) {
    lookup_invalid(c)
  }
  let mut completeness = None
  let mut rows = None
  let mut pages = None
  let mut bytes = None
  let mut version = false
  for i in 0..<5 {
    let (name, value) = @decode.field_at(c, i).unwrap()
    lookup_charge(b, 1, value)
    lookup_charge(b, name.length(), value)
    match name {
      "version" | "completeness" => {
        let text = match @decode.text(value) {
          Ok(v) => v
          Err(_) => lookup_invalid(value)
        }
        lookup_charge(b, text.length(), value)
        if name == "version" {
          if text != "actql-lookup-capacity/0.1" {
            lookup_invalid(value)
          }
          version = true
        } else {
          completeness = Some(
            match text {
              "complete_per_requested_key" => CompletePerRequestedKey
              "hard_limit_only" => HardLimitOnly
              _ => lookup_invalid(value)
            },
          )
        }
      }
      "max_rows_per_key"
      | "max_pages_per_request"
      | "max_response_bytes_per_page" => {
        let n = match @decode.safe_integer(value) {
          Ok(v) => v
          Err(_) => lookup_invalid(value)
        }
        if n <= 0 {
          lookup_invalid(value)
        }
        match name {
          "max_rows_per_key" => rows = Some(n)
          "max_pages_per_request" => pages = Some(n)
          _ => bytes = Some(n)
        }
      }
      _ => lookup_invalid(value)
    }
  }
  guard completeness is Some(completeness) &&
    rows is Some(rows) &&
    pages is Some(pages) &&
    bytes is Some(bytes) &&
    version else {
    lookup_invalid(c)
  }
  { source: c, completeness, rows, pages, bytes, }
}

///|
/// Validates all supplied carrier-facts components, even unreferenced ones.
/// This proves component shape and Catalog ownership, not authority or runtime completeness.
pub fn check_lookup_capacities(
  references : CatalogReferences,
  limits : LookupCapacityLimits,
) -> Result[LookupCapacities, LookupCapacityIssue] {
  if limits.max_work < 0 || limits.max_facts < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let b = { limit: limits.max_work, used: 0, }
  let entries = []
  let by_cid : Map[String, LookupFacts] = Map([])
  let views : Map[Int, SourceLookupFacts] = Map([])
  try {
    for envelope in references.contents.registry.entries {
      let root = envelope.body
      lookup_charge(b, 1, root)
      if envelope.kind != "carrier_facts" {
        continue
      }
      if entries.length() >= limits.max_facts {
        raise LookupCapacityStop({ kind: FactsLimit, source: Some(root), })
      }
      let count = match @decode.object_length(root) {
        Some(v) => v
        None => lookup_invalid(root)
      }
      let mut capacity = None
      for i in 0..<count {
        let (name, value) = @decode.field_at(root, i).unwrap()
        lookup_charge(b, 1, value)
        lookup_charge(b, name.length(), value)
        if name == "lookup_capacity" {
          capacity = Some(lookup_capacity_body(value, b))
        }
      }
      let facts = { envelope, capacity, }
      entries.push(facts)
      by_cid[envelope.cid] = facts
    }
    for reference in references.references {
      lookup_charge(b, 1, reference.contract.body)
      if reference.contract.kind == "carrier_facts" {
        views[member_index(reference.item)] = {
          reference,
          facts: by_cid[reference.contract.cid],
        }
      }
    }
    Ok({ references, entries, by_cid, views, work: b.used, })
  } catch {
    LookupCapacityStop(issue) => Err(issue)
  }
}

///|
pub fn lookup_capacity_references(v : LookupCapacities) -> CatalogReferences {
  v.references
}

///|
pub fn lookup_capacity_usage(v : LookupCapacities) -> (Int, Int) {
  (v.work, v.entries.length())
}

///|
pub fn lookup_facts_at(v : LookupCapacities, i : Int) -> LookupFacts? {
  v.entries.get(i)
}

///|
pub fn lookup_facts_envelope(v : LookupFacts) -> ContractEnvelope {
  v.envelope
}

///|
pub fn lookup_facts_capacity(v : LookupFacts) -> LookupCapacity? {
  v.capacity
}

///|
pub fn lookup_capacity_source(v : LookupCapacity) -> @decode.Cursor {
  v.source
}

///|
pub fn lookup_capacity_completeness(v : LookupCapacity) -> LookupCompleteness {
  v.completeness
}

///|
pub fn lookup_capacity_rows_per_key(v : LookupCapacity) -> Int64 {
  v.rows
}

///|
pub fn lookup_capacity_pages_per_request(v : LookupCapacity) -> Int64 {
  v.pages
}

///|
/// Decoded response-body octets, not transport or canonical-row bytes.
pub fn lookup_capacity_response_bytes_per_page(v : LookupCapacity) -> Int64 {
  v.bytes
}

///|
pub fn source_lookup_facts(
  v : LookupCapacities,
  item : Member,
) -> SourceLookupFacts? {
  if member_section(item) != SourceViews ||
    !physical_equal(
      member_environment(item),
      v.references.contents.registry.environment,
    ) {
    return None
  }
  v.views.get(member_index(item))
}

///|
pub fn source_lookup_reference(v : SourceLookupFacts) -> CatalogReference {
  v.reference
}

///|
pub fn source_lookup_body(v : SourceLookupFacts) -> LookupFacts {
  v.facts
}
