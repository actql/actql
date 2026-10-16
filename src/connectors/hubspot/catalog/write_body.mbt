///|
/// Bounds for one complete ActQL row and both simultaneous output spellings.
/// They are physical inputs, not a numerical profile, grant or dispatch ACK.
pub(all) struct WriteBodyLimits {
  max_input_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_fields : Int
  max_name_bytes : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
  max_comparison_work : Int
  max_output_bytes : Int
  max_output_nodes : Int
  max_output_depth : Int
}

///|
pub(all) enum WriteBodyIssue {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  MissingField(String)
  UnexpectedField(String)
  Property(PropertyIssue)
  ValueAdmission(String, @admitted.Issue)
  UnlistedOption(String)
  UnrepresentableValue(String)
} derive(Eq, Debug)

///|
/// One pure candidate under the original metadata, never an executable Effect.
/// The two strings state the same values in ActQL and provider representations.
pub struct WriteBody {
  priv catalog : PropertyCatalog
  priv names : Array[String]
  priv properties_document : @encode.EncodedDocument
  priv value_json : String
}

///|
priv struct WriteBodyBudget {
  mut nodes : Int
  mut text_bytes : Int
  mut comparison_work : Int
}

///|
priv suberror WriteBodyStop {
  WriteBodyStop(WriteBodyIssue)
}

///|
pub fn write_body_properties_json(body : WriteBody) -> String {
  @encode.document_text(body.properties_document)
}

///|
pub fn write_body_value_json(body : WriteBody) -> String {
  body.value_json
}

///|
pub fn write_body_property_names(body : WriteBody) -> Array[String] {
  body.names.copy()
}

///|
/// Current metadata is checked by the original Catalog Owner, including every
/// admitted field. This is separate from Account, credential and target state.
pub fn recheck_write_body(
  body : WriteBody,
  current : PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, PropertyIssue] {
  recheck_property_catalog(body.catalog, current, max_properties)
}

///|
fn write_property_text(
  property : PropertyMetadata,
  value : @admitted.CheckedValue,
  max_bytes : Int,
) -> Result[String, WriteBodyIssue] {
  match value.value {
    Null => Ok("")
    Array(items) if property.native_type == "enumeration" &&
      property.field_type == "checkbox" => {
      // A leading semicolon would append instead of replacing. Delimiter and
      // empty-element collisions must not change the approved array's meaning.
      let selected : Array[String] = []
      let mut bytes = 0
      for index in 0..<@admitted.element_count(items) {
        guard @admitted.element_at(items, index) is Some(Text(text)) &&
          !text.is_empty() &&
          !text.contains(";") else {
          return Err(UnrepresentableValue(property.name))
        }
        if !property.options.contains(text) {
          return Err(UnlistedOption(property.name))
        }
        let length = @utf8.encode(text).length()
        let separator = if index == 0 { 0 } else { 1 }
        if separator > max_bytes - bytes ||
          length > max_bytes - bytes - separator {
          return Err(BudgetExceeded)
        }
        bytes += length + separator
        selected.push(text)
      }
      Ok(selected.join(";"))
    }
    Text(text) if property.native_type == "enumeration" =>
      if !property.options.contains(text) {
        Err(UnlistedOption(property.name))
      } else {
        match @admitted.canonical_scalar_text(value, max_bytes) {
          Some(text) => Ok(text)
          None => Err(BudgetExceeded)
        }
      }
    _ =>
      match @admitted.canonical_scalar_text(value, max_bytes) {
        Some(text) => Ok(text)
        None => Err(UnrepresentableValue(property.name))
      }
  }
}

///|
/// Use the existing provider decoder and Common equality Owner to establish
/// local representation roundtrip. This is no claim about a future server
/// response or successful mutation. In particular, empty strings that mean
/// clear/append cannot silently substitute another approved ActQL value.
fn recheck_write_cell_spelling(
  cursor : @decode.Cursor,
  property : PropertyMetadata,
  value : @admitted.CheckedValue,
  spelling : String,
  limits : WriteBodyLimits,
  budget : WriteBodyBudget,
) -> Result[Unit, WriteBodyIssue] {
  let provider = match
    @decode.admit(
      { value: @source.String(spelling), span: @decode.cursor_span(cursor), },
      {
        max_nodes: 1,
        max_depth: 1,
        max_string_bytes: limits.max_value_text_bytes,
        max_total_string_bytes: limits.max_value_text_bytes,
      },
    ) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  let observed = match
    object_cell(
      provider,
      property,
      value.contract,
      {
        nodes: limits.max_value_nodes,
        text_bytes: limits.max_value_text_bytes,
        depth: limits.max_depth,
      },
      limits.max_output_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(UnrepresentableValue(property.name))
  }
  let equality = match
    @admitted.start_complete_equality(value, observed, {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_value_text_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  while budget.comparison_work > 0 {
    match @admitted.advance_complete_equality(equality, 1) {
      EqualityContinue(work~) => budget.comparison_work -= work
      EqualityComplete(equal~, work~) => {
        budget.comparison_work -= work
        return if equal {
          Ok(())
        } else {
          Err(UnrepresentableValue(property.name))
        }
      }
      EqualityFailed(_, work~) => {
        budget.comparison_work -= work
        return Err(BudgetExceeded)
      }
    }
  }
  Err(BudgetExceeded)
}

///|
/// Admit the complete mapped row through existing Source/Decode/Common types.
/// Operation, target key, Preview, current authority, durable nominal request
/// and original Account/portal binding remain duties of their existing Owners.
pub fn prepare_write_body(
  catalog : PropertyCatalog,
  names : Array[String],
  bytes : Bytes,
  limits : WriteBodyLimits,
) -> Result[WriteBody, WriteBodyIssue] {
  if limits.max_input_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_name_bytes <= 0 ||
    limits.max_value_nodes <= 0 ||
    limits.max_value_text_bytes <= 0 ||
    limits.max_comparison_work <= 0 ||
    limits.max_output_bytes <= 0 ||
    limits.max_output_nodes <= 0 ||
    limits.max_output_depth <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_input_bytes ||
    names.length() > limits.max_fields {
    return Err(BudgetExceeded)
  }
  let entries = []
  for name in names {
    match require_property_write(catalog, name) {
      Ok(_) => ()
      Err(issue) => return Err(Property(issue))
    }
    let contract = match property_contract(catalog, name) {
      Ok(value) => value
      Err(issue) => return Err(Property(issue))
    }
    entries.push((name, contract))
  }
  let contract = match
    @contract.object_contract(
      entries,
      nullable=false,
      max_fields=limits.max_fields,
      max_name_bytes=limits.max_name_bytes,
    ) {
    Ok(value) => value
    Err(@contract.ConstructionLimit) => return Err(BudgetExceeded)
    Err(_) => return Err(InvalidBody)
  }
  guard contract.shape is @contract.Object(fields) else {
    return Err(InvalidBody)
  }
  let source = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_input_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidBody
        },
      )
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_input_bytes,
      max_total_string_bytes: limits.max_input_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  guard @decode.open_object(cursor) is Ok(object) else {
    return Err(InvalidBody)
  }
  for name in names {
    if @decode.lookup(object, name) is None {
      return Err(MissingField(name))
    }
  }
  for index in 0..<@decode.object_length(cursor).unwrap() {
    let (name, _) = @decode.field_at(cursor, index).unwrap()
    if !names.contains(name) {
      return Err(UnexpectedField(name))
    }
  }
  let provider = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let values = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => {
      @encode.cancel_writer(provider)
      return Err(BudgetExceeded)
    }
  }
  let budget = {
    nodes: limits.max_value_nodes,
    text_bytes: limits.max_value_text_bytes,
    comparison_work: limits.max_comparison_work,
  }
  try {
    @encode.begin_ordered_object(provider)
    @encode.begin_ordered_object(values)
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      let property = property_named(catalog, field.name).unwrap()
      let cell = @decode.lookup(object, field.name).unwrap()
      let (value, nodes, text) = match
        @admitted.admit_usage(field.contract, cell, {
          max_nodes: budget.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: budget.text_bytes,
        }) {
        Ok(value) => value
        Err(issue) => raise WriteBodyStop(ValueAdmission(field.name, issue))
      }
      budget.nodes -= nodes
      budget.text_bytes -= text
      let spelling = match
        write_property_text(property, value, limits.max_output_bytes) {
        Ok(value) => value
        Err(issue) => raise WriteBodyStop(issue)
      }
      match
        recheck_write_cell_spelling(
          cell, property, value, spelling, limits, budget,
        ) {
        Ok(_) => ()
        Err(issue) => raise WriteBodyStop(issue)
      }
      @encode.ordered_key(provider, field.name)
      @encode.string_value(provider, spelling)
      @encode.ordered_key(values, field.name)
      @admitted.emit_checked_wire_value(value, values)
    }
    @encode.end_object(provider)
    @encode.end_object(values)
    Ok({
      catalog,
      names: names.copy(),
      properties_document: @encode.finish_document(provider),
      value_json: @encode.finish(values),
    })
  } catch {
    WriteBodyStop(issue) => {
      @encode.cancel_writer(provider)
      @encode.cancel_writer(values)
      Err(issue)
    }
    @encode.OutputLimit => {
      @encode.cancel_writer(provider)
      @encode.cancel_writer(values)
      Err(BudgetExceeded)
    }
    _ => {
      @encode.cancel_writer(provider)
      @encode.cancel_writer(values)
      Err(InvalidBody)
    }
  }
}
