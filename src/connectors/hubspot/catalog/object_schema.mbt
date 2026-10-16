///|
/// Project selected observed properties into Common's full relation field-map
/// wire. Decimal and array carriers come from property_contract, never a second
/// provider type table. This is declaration DATA, not an installed Source,
/// permission, current observation or acquisition/publication ACK.
pub fn object_schema_wire(
  catalog : PropertyCatalog,
  names : Array[String],
  max_columns : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ObjectPageIssue] {
  if max_columns <= 0 ||
    max_name_bytes <= 0 ||
    max_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  // The original top-level record key is always a separate non-null string.
  // Avoid overflowing a caller-supplied count when including that field.
  if names.length() >= max_columns {
    return Err(BudgetExceeded)
  }
  let entries : Array[(String, @contract.Contract)] = [
    ("id", @contract.primitive(@contract.StringType, nullable=false)),
  ]
  let selected : Map[String, Bool] = Map([])
  for name in names {
    if name == "id" || selected.contains(name) {
      return Err(DuplicateSelection(name))
    }
    selected[name] = true
    let contract = match property_contract(catalog, name) {
      Ok(value) => value
      Err(issue) => return Err(Property(issue))
    }
    entries.push((name, contract))
  }
  // Common validates names and canonical UTF-16 order without repairing them.
  let object = match
    @contract.object_contract(
      entries,
      nullable=false,
      max_fields=max_columns,
      max_name_bytes~,
    ) {
    Ok(value) => value
    Err(@contract.ConstructionLimit) => return Err(BudgetExceeded)
    Err(_) => return Err(InvalidResponse)
  }
  guard object.shape is @contract.Object(fields) else {
    return Err(InvalidResponse)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_ordered_object(writer)
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      @encode.ordered_key(writer, field.name)
      @contract.emit_checked(field.contract, writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
    _ => {
      @encode.cancel_writer(writer)
      Err(InvalidResponse)
    }
  }
}
