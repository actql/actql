///|
pub(all) struct RecordReadLimits {
  max_rows : Int
  max_properties : Int
  max_columns : Int
  max_request_bytes : Int
  max_request_nodes : Int
  max_request_depth : Int
}

///|
pub(all) enum RecordReadIssue {
  InvalidLimits
  BudgetExceeded
  ForeignCatalog
  ForeignTargetKey
  DuplicateTarget
  Property(PropertyIssue)
  Page(ObjectPageIssue)
  InvalidResponse
  IncompleteResponse
  ForeignRecord
  DuplicateRecord
  InvalidUpdatedAt
  ChangedObservation
} derive(Eq, Debug)

///|
/// Complete bounded target-read DATA under the original Catalog. The same
/// Host/Credential owners still authorize and count the physical request.
pub struct RecordReadRequest {
  priv catalog : PropertyCatalog
  priv targets : Array[RecordTarget]
  priv names : Array[String]
  priv document : @encode.EncodedDocument
}

///|
/// A complete response correlated to the original selectors, in their order.
/// It is not an absent-record proof, sealed Preview, conditional-write token,
/// authorization, publication or provider write outcome.
pub struct RecordReadObservation {
  response_sha256 : String
  priv request : RecordReadRequest
  priv document : @encode.EncodedDocument
}

///|
pub fn prepare_record_read_request(
  catalog : PropertyCatalog,
  targets : Array[RecordTarget],
  names : Array[String],
  limits : RecordReadLimits,
) -> Result[RecordReadRequest, RecordReadIssue] {
  if limits.max_rows <= 0 ||
    limits.max_rows > 100 ||
    limits.max_properties <= 0 ||
    limits.max_columns <= 0 ||
    limits.max_request_bytes <= 0 ||
    limits.max_request_nodes <= 0 ||
    limits.max_request_depth <= 0 {
    return Err(InvalidLimits)
  }
  if targets.is_empty() ||
    targets.length() > limits.max_rows ||
    names.length() > limits.max_columns {
    return Err(BudgetExceeded)
  }
  let key = targets[0].key
  let seen : Map[String, Bool] = Map([])
  for target in targets {
    match
      recheck_property_catalog(target.catalog, catalog, limits.max_properties) {
      Ok(_) => ()
      Err(_) => return Err(ForeignCatalog)
    }
    if target.key != key {
      return Err(ForeignTargetKey)
    }
    if seen.contains(target.value_wire) {
      return Err(DuplicateTarget)
    }
    seen[target.value_wire] = true
  }
  let selected = []
  for name in names {
    if selected.contains(name) || name == "id" {
      return Err(ForeignTargetKey)
    }
    match property_contract(catalog, name) {
      Ok(_) => ()
      Err(issue) => return Err(Property(issue))
    }
    selected.push(name)
  }
  // A response is correlated by its actual admitted key value, never by
  // provider array order or an unproven idProperty/lookup convention.
  if key != "id" && !selected.contains(key) {
    if selected.length() >= limits.max_columns {
      return Err(BudgetExceeded)
    }
    selected.push(key)
  }
  let writer = @encode.writer(
    limits.max_request_bytes,
    limits.max_request_nodes,
    limits.max_request_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "inputs")
    @encode.begin_array(writer)
    for target in targets {
      @encode.begin_object(writer)
      @encode.key(writer, "id")
      @encode.string_value(writer, target.provider_value)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    if key != "id" {
      @encode.key(writer, "idProperty")
      @encode.string_value(writer, key)
    }
    @encode.key(writer, "properties")
    @encode.begin_array(writer)
    for name in selected {
      @encode.string_value(writer, name)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok({
      catalog,
      targets: targets.copy(),
      names: selected,
      document: @encode.finish_document(writer),
    })
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn record_read_request_body(request : RecordReadRequest) -> String {
  @encode.document_text(request.document)
}

///|
pub fn record_read_request_object_type(request : RecordReadRequest) -> String {
  request.catalog.object_type
}

///|
pub fn recheck_record_read_request(
  request : RecordReadRequest,
  current : PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, PropertyIssue] {
  recheck_property_catalog(request.catalog, current, max_properties)
}

///|
fn record_read_value_wire(
  value : @admitted.CheckedValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return None
  }
  try {
    @admitted.emit_checked_wire_value(value, writer)
    Some(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      None
    }
  }
}

///|
pub fn project_record_read_observation(
  request : RecordReadRequest,
  bytes : Bytes,
  limits : ObjectPageLimits,
  max_output_bytes : Int,
  max_output_nodes : Int,
  max_output_depth : Int,
) -> Result[RecordReadObservation, RecordReadIssue] {
  if !object_page_limits_valid(limits) ||
    max_output_bytes <= 0 ||
    max_output_nodes <= 0 ||
    max_output_depth <= 0 {
    return Err(InvalidLimits)
  }
  // The existing bounded page decoder owns property types, exact Decimal,
  // null/array rules and duplicate/archived record refusal.
  let page = match
    project_object_page(bytes, request.catalog, request.names, limits) {
    Ok(value) => value
    Err(issue) => return Err(Page(issue))
  }
  if page.next_after is Some(_) ||
    page.rows.length() != request.targets.length() {
    return Err(IncompleteResponse)
  }
  // Inspect the original response envelope as well. This second bounded
  // decode and the admitted page overlap; their physical holding is not a
  // normal profile/funding claim. No derived JSON is reparsed as evidence.
  let parsed = @source.parse_json_bytes(bytes, {
    max_input_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
  }).unwrap()
  let root = @decode.admit(parsed, {
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_string_bytes: limits.max_bytes,
    max_total_string_bytes: limits.max_bytes,
  }).unwrap()
  let root = @decode.open_object(root).unwrap()
  if text(root, "status") != Some("COMPLETE") {
    return Err(IncompleteResponse)
  }
  match @decode.field(root, "errors") {
    Missing => ()
    Present(value) if @decode.array_length(value) == Some(0) => ()
    _ => return Err(IncompleteResponse)
  }
  match @decode.field(root, "numErrors") {
    Missing => ()
    Present(value) if @decode.int32(value) == Ok(0) => ()
    _ => return Err(IncompleteResponse)
  }
  let results = @decode.lookup(root, "results").unwrap()
  let selectors : Map[String, Int] = Map([])
  let updated = []
  let key = request.targets[0].key
  let mut key_index = -1
  for index, name in request.names {
    if name == key {
      key_index = index
    }
  }
  for index, row in page.rows {
    let selector = if key == "id" {
      // Top-level record IDs are already admitted nonempty strings.
      row.id
    } else {
      guard key_index >= 0 &&
        record_read_value_wire(
          row.values[key_index],
          max_output_bytes,
          max_output_nodes,
          max_output_depth,
        )
        is Some(value) else {
        return Err(BudgetExceeded)
      }
      value
    }
    if selectors.contains(selector) {
      // Two provider record IDs for one supposedly unique key are a refusal,
      // never an arbitrary first match or implicit duplicate suppression.
      return Err(DuplicateRecord)
    }
    selectors[selector] = index
    let record = @decode.open_object(
      @decode.element_at(results, index).unwrap(),
    ).unwrap()
    guard text(record, "updatedAt") is Some(value) &&
      hubspot_temporal(value, false) is Some(value) else {
      return Err(InvalidUpdatedAt)
    }
    updated.push(value)
  }
  let order = []
  for target in request.targets {
    let selector = if key == "id" {
      target.provider_value
    } else {
      target.value_wire
    }
    guard selectors.get(selector) is Some(index) else {
      return Err(ForeignRecord)
    }
    order.push(index)
  }
  let writer = @encode.writer(
    max_output_bytes, max_output_nodes, max_output_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_array(writer)
    for index in order {
      let row = page.rows[index]
      @encode.begin_object(writer)
      @encode.key(writer, "id")
      @encode.string_value(writer, row.id)
      @encode.key(writer, "updatedAt")
      @encode.string_value(writer, updated[index])
      @encode.key(writer, "properties")
      @encode.begin_object(writer)
      for column, name in request.names {
        @encode.key(writer, name)
        @admitted.emit_checked_wire_value(row.values[column], writer)
      }
      @encode.end_object(writer)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok({
      response_sha256: page.response_sha256,
      request,
      document: @encode.finish_document(writer),
    })
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn record_read_observation_wire(
  observation : RecordReadObservation,
) -> String {
  @encode.document_text(observation.document)
}

///|
/// Equality is a bounded observation check only. The Host must still perform
/// its current Account/credential/schema checks and original Effect claim.
pub fn recheck_record_read_observation(
  original : RecordReadObservation,
  current : RecordReadObservation,
  max_properties : Int,
  max_comparison_work : Int,
) -> Result[Unit, RecordReadIssue] {
  if max_properties <= 0 || max_comparison_work <= 0 {
    return Err(InvalidLimits)
  }
  match
    recheck_property_catalog(
      original.request.catalog,
      current.request.catalog,
      max_properties,
    ) {
    Ok(_) => ()
    Err(_) => return Err(ForeignCatalog)
  }
  let left_request = record_read_request_body(original.request)
  let right_request = record_read_request_body(current.request)
  let left = record_read_observation_wire(original)
  let right = record_read_observation_wire(current)
  let mut remaining = max_comparison_work
  for value in [left_request, right_request, left, right] {
    if value.length() > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= value.length()
  }
  if left_request != right_request || left != right {
    Err(ChangedObservation)
  } else {
    Ok(())
  }
}
