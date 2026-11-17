///|
// Borrowed immutable Catalog selection DATA. The managed caller funds these
// fixed controls and pays its actual visits before advancing. No capacity,
// currentness, Source permission or body emission is granted by this cursor.
struct CheckedLocalCatalogSelection {
  program : CheckedProgram
  unit : Int
  section : @environment.Section
  self_field : String?
  role : String
  identity : String
  count : Int
  mut next : Int
  mut selected : Int?
  mut closed : Bool
}

///|
fn local_catalog_selection_role(
  role : String,
) -> (@environment.Section, String?)? {
  match role {
    "schema_evidence" => Some((@environment.SchemaSnapshots, None))
    "capability_evidence" => Some((@environment.ConnectorCapabilities, None))
    "source_contract" | "source_view_contract" =>
      Some((@environment.SourceViews, Some("contract_cid")))
    "data_policy" | "request_schema" | "carrier_schema" =>
      Some((@environment.ContractRegistry, Some("cid")))
    _ => None
  }
}

///|
pub fn begin_checked_local_catalog_selection(
  program : CheckedProgram,
  unit : Int,
  role : String,
  identity : String,
) -> Result[CheckedLocalCatalogSelection, LocalDependencyBodyIssue] {
  guard local_catalog_selection_role(role) is Some((section, self_field)) else {
    return Err(MissingDependency)
  }
  Ok({
    program,
    unit,
    section,
    self_field,
    role,
    identity,
    count: @environment.member_count(checked_environment(program), section),
    next: 0,
    selected: None,
    closed: false,
  })
}

///|
pub fn checked_local_catalog_selection_remaining(
  value : CheckedLocalCatalogSelection,
) -> Int {
  value.count - value.next
}

///|
/// Advance only an already-paid visit chunk. Existing public lookup retains
/// its independent 4096 guard; actual managed owners select this DATA path.
pub fn advance_checked_local_catalog_selection(
  value : CheckedLocalCatalogSelection,
  visits : Int,
  work? : ((Int) -> Bool)? = None,
) -> Result[Unit, LocalDependencyBodyIssue] {
  if value.closed || visits < 0 || visits > value.count - value.next {
    return Err(BudgetExceeded)
  }
  let environment = checked_environment(value.program)
  for _ in 0..<visits {
    let index = value.next
    value.next += 1
    guard @environment.member_at(environment, value.section, index)
      is Some(item) else {
      value.closed = true
      return Err(MissingDependency)
    }
    let actual = match value.self_field {
      None => @environment.member_cid(item)
      Some(field) => {
        let body = @environment.member_body(item)
        guard @decode.object_length(body) is Some(count) else {
          value.closed = true
          return Err(MissingDependency)
        }
        let mut selected : String? = None
        // Original admission rejects duplicate keys. Borrow scalar fields
        // directly; opening ObjectView would build a width-sized Map here.
        for position in 0..<count {
          if work is Some(spend) && !spend(1) {
            value.closed = true
            return Err(BudgetExceeded)
          }
          guard @decode.field_at(body, position) is Some((key, child)) else {
            value.closed = true
            return Err(MissingDependency)
          }
          // Unequal lengths are O(1); an equal-length key comparison visits
          // at most this actual borrowed key before selecting its scalar.
          if key.length() != field.length() {
            continue
          }
          if work is Some(spend) && !spend(key.length()) {
            value.closed = true
            return Err(BudgetExceeded)
          }
          if key != field {
            continue
          }
          guard @decode.text(child) is Ok(text) else {
            value.closed = true
            return Err(MissingDependency)
          }
          selected = Some(text)
          break
        }
        guard selected is Some(text) else {
          value.closed = true
          return Err(MissingDependency)
        }
        text
      }
    }
    if actual.length() == value.identity.length() &&
      work is Some(spend) &&
      !spend(actual.length()) {
      value.closed = true
      return Err(BudgetExceeded)
    }
    if actual == value.identity {
      if value.selected is Some(_) {
        value.closed = true
        return Err(ForeignBody)
      }
      value.selected = Some(index)
    }
  }
  Ok(())
}

///|
pub fn checked_local_catalog_selection_geometry(
  value : CheckedLocalCatalogSelection,
) -> (Int, Int, Int)? {
  guard !value.closed &&
    value.next == value.count &&
    value.selected is Some(index) &&
    @environment.member_at(
      checked_environment(value.program),
      value.section,
      index,
    )
    is Some(item) else {
    return None
  }
  Some(@environment.member_emission_geometry(item))
}

///|
pub fn finish_checked_local_catalog_selection(
  value : CheckedLocalCatalogSelection,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CheckedLocalDependencyBody, LocalDependencyBodyIssue] {
  if value.closed || value.next != value.count {
    return Err(BudgetExceeded)
  }
  value.closed = true
  guard value.selected is Some(index) else { return Err(MissingDependency) }
  let kind = match value.role {
    "schema_evidence" => SourceSchema(index)
    "capability_evidence" => SourceCapability(index)
    "data_policy" | "request_schema" | "carrier_schema" =>
      RegistryContract(index)
    _ => SourceViewContract(index)
  }
  checked_local_dependency_body(
    value.program,
    value.unit,
    kind,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
// The same immutable checked emitter's census; no body/wire is constructed.
// Caller already owns fixed/depth controls and its actual scoped Work.
pub fn census_checked_local_catalog_selection(
  value : CheckedLocalCatalogSelection,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Result[CheckedLocalDependencyCensus, LocalDependencyBodyIssue] {
  if value.closed || value.next != value.count {
    return Err(BudgetExceeded)
  }
  value.closed = true
  guard value.selected is Some(index) else { return Err(MissingDependency) }
  let kind = match value.role {
    "schema_evidence" => SourceSchema(index)
    "capability_evidence" => SourceCapability(index)
    "data_policy" | "request_schema" | "carrier_schema" =>
      RegistryContract(index)
    _ => SourceViewContract(index)
  }
  census_checked_local_dependency_body(
    value.program,
    value.unit,
    kind,
    max_bytes,
    max_nodes,
    max_depth,
    work,
  )
}
