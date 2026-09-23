///|
/// One bounded projection of Salesforce's authorized sObject listing. It is
/// discovery material, not a static Connector Catalog or execution authority.
pub(all) struct ListLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_resources : Int
  max_selected : Int
  max_name_units : Int
}

///|
pub(all) struct ListedResource {
  name : String
  queryable : Bool
  createable : Bool
  updateable : Bool
}

///|
pub(all) struct ResourceListing {
  selected : Array[ListedResource]
  visible_count : Int
  truncated : Bool
  response_sha256 : String
}

///|
pub(all) enum ListingIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  DuplicateResource(String)
} derive(Eq, Debug)

///|
pub fn project_resource_listing(
  bytes : Bytes,
  limits : ListLimits,
) -> Result[ResourceListing, ListingIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_resources < 0 ||
    limits.max_selected < 0 ||
    limits.max_selected > limits.max_resources ||
    limits.max_name_units < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "sobjects") is Some(list) &&
    @decode.array_length(list) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_resources {
    return Err(BudgetExceeded)
  }
  let selected = []
  let seen : Map[String, Bool] = Map([])
  let mut name_units = 0
  let selected_count = if count < limits.max_selected {
    count
  } else {
    limits.max_selected
  }
  for index in 0..<selected_count {
    guard @decode.open_object(@decode.element_at(list, index).unwrap())
      is Ok(entry) &&
      required_text(entry, "name") is Some(name) &&
      valid_api_name(name) else {
      return Err(InvalidResponse)
    }
    if seen.contains(name) {
      return Err(DuplicateResource(name))
    }
    if name.length() > limits.max_name_units - name_units {
      return Err(BudgetExceeded)
    }
    guard optional_boolean(entry, "queryable", false) is Some(queryable) &&
      optional_boolean(entry, "createable", false) is Some(createable) &&
      optional_boolean(entry, "updateable", false) is Some(updateable) else {
      return Err(InvalidResponse)
    }
    name_units += name.length()
    seen[name] = true
    selected.push({ name, queryable, createable, updateable, })
  }
  Ok({
    selected,
    visible_count: count,
    truncated: selected_count != count,
    response_sha256: @sha.hex(bytes),
  })
}

///|
pub(all) enum ResourceSelectionIssue {
  ListingTruncated
  NotVisible
  DescribeRequired
  DescribeMismatch
} derive(Eq, Debug)

///|
/// Selection cannot turn a failed or omitted describe into absence. A resource
/// missing from a complete visible listing is only "not visible" to this
/// authority, not globally nonexistent.
pub fn select_described_resource(
  listing : ResourceListing,
  name : String,
  described : ResourceMetadata?,
) -> Result[ResourceMetadata, ResourceSelectionIssue] {
  let mut listed : ListedResource? = None
  for entry in listing.selected {
    if entry.name == name {
      listed = Some(entry)
      break
    }
  }
  guard listed is Some(entry) else {
    return Err(if listing.truncated { ListingTruncated } else { NotVisible })
  }
  guard described is Some(resource) else { return Err(DescribeRequired) }
  if resource.name != name ||
    (resource.queryable && !entry.queryable) ||
    (resource.createable && !entry.createable) ||
    (resource.updateable && !entry.updateable) {
    return Err(DescribeMismatch)
  }
  Ok(resource)
}
