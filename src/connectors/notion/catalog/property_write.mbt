///|
/// Codec bounds only; not an Effect admission, capacity or reservation.
pub(all) struct NotionPropertyWriteLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_properties : Int
  max_items : Int
  max_text_units : Int
  max_work : Int
}

///|
pub(all) enum NotionPropertyWriteIssue {
  InvalidLimits
  BudgetExceeded
  InvalidSelection
  ForeignOriginal
  DuplicateProperty(String)
  InvalidValue(String)
  UnsupportedProperty(String)
  UnknownOption(String)
  InvalidOptions(String)
} derive(Eq, Debug)

///|
/// A provider spelling of this original checked value and property. No write
/// capability, target identity, Mapping, precondition or mutation is issued.
pub struct NotionPropertyWrite {
  priv source : NotionDataSourceCatalog
  priv property : NotionPropertyMetadata
  priv value : @admitted.CheckedValue
  priv document : @encode.EncodedDocument
}

///|
fn notion_write_limits_valid(limits : NotionPropertyWriteLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_properties >= 0 &&
  limits.max_items >= 0 &&
  limits.max_text_units >= 0 &&
  limits.max_work > 0
}

///|
/// Every option, including unselected options, is checked and charged. An
/// exact existing label selects its original id; no option is created by name.
fn notion_write_option(
  property : NotionPropertyMetadata,
  selected : String,
  work : Int,
) -> Result[(String, Int), NotionPropertyWriteIssue] {
  guard @decode.open_object(property.definition) is Ok(definition) &&
    @decode.lookup(definition, property.kind) is Some(body) &&
    @decode.open_object(body) is Ok(body) &&
    @decode.lookup(body, "options") is Some(options) &&
    @decode.array_length(options) is Some(count) else {
    return Err(InvalidOptions(property.id))
  }
  let mut remaining = work
  let mut found = None
  let ids : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(options, index).unwrap())
      is Ok(option) &&
      @decode.lookup(option, "id") is Some(id) &&
      @decode.text(id) is Ok(id) &&
      !id.is_empty() &&
      @decode.lookup(option, "name") is Some(name) &&
      @decode.text(name) is Ok(name) else {
      return Err(InvalidOptions(property.id))
    }
    if remaining == 0 || id.length() > remaining - 1 {
      return Err(BudgetExceeded)
    }
    remaining -= 1 + id.length()
    // Include exact label comparison and both hash inventories in the bound.
    if name.length() > remaining / 2 {
      return Err(BudgetExceeded)
    }
    remaining -= 2 * name.length()
    if ids.contains(id) || names.contains(name) {
      return Err(InvalidOptions(property.id))
    }
    ids[id] = true
    names[name] = true
    if name == selected {
      found = Some(id)
    }
  }
  match found {
    Some(id) => Ok((id, remaining))
    None => Err(UnknownOption(property.id))
  }
}

///|
/// Only encodes the supplied checked value. The consuming original Mapping
/// and Effect owner must separately establish writability, target/current,
/// approval, overwrite guards, whole-input keys and original Run custody.
pub fn prepare_notion_property_write(
  source : NotionDataSourceCatalog,
  property_index : Int,
  value : @admitted.CheckedValue,
  limits : NotionPropertyWriteLimits,
) -> Result[NotionPropertyWrite, NotionPropertyWriteIssue] {
  if !notion_write_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  guard notion_data_source_property_at(source, property_index) is Some(property) else {
    return Err(InvalidSelection)
  }
  let kind = property.kind
  if ![
      "title", "rich_text", "number", "checkbox", "url", "email", "phone_number",
      "select", "status", "people", "relation",
    ].contains(kind) {
    // Computed/created/edited values and Content references cannot acquire a
    // writable representation from similarly shaped JSON or strings.
    return Err(UnsupportedProperty(property.id))
  }
  let mut remaining = limits.max_work
  if property.id.length() >= remaining {
    return Err(BudgetExceeded)
  }
  remaining -= 1 + property.id.length()
  let option = match value.value {
    @admitted.Text(text) => {
      if text.length() > limits.max_text_units || text.length() > remaining {
        return Err(BudgetExceeded)
      }
      remaining -= text.length()
      if kind == "select" || kind == "status" {
        match notion_write_option(property, text, remaining) {
          Ok((id, work)) => {
            remaining = work
            Some(id)
          }
          Err(issue) => return Err(issue)
        }
      } else {
        None
      }
    }
    _ => None
  }
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidLimits)
  }
  let result : Result[Unit, NotionPropertyWriteIssue] = try {
    @encode.begin_object(writer)
    @encode.key(writer, kind)
    match value.value {
      @admitted.Null =>
        if !["number", "url", "email", "phone_number", "select", "status"].contains(
            kind,
          ) {
          Err(InvalidValue(property.id))
        } else {
          @encode.null_value(writer)
          Ok(())
        }
      @admitted.Boolean(boolean) if kind == "checkbox" => {
        @encode.bool_value(writer, boolean)
        Ok(())
      }
      @admitted.Decimal(_) if kind == "number" =>
        match @admitted.canonical_scalar_text(value, limits.max_text_units) {
          Some(text) if text.length() <= remaining => {
            @encode.decimal_number_value(writer, text)
            Ok(())
          }
          _ => Err(BudgetExceeded)
        }
      @admitted.Text(text) if kind == "title" || kind == "rich_text" => {
        @encode.begin_array(writer)
        let mut start = 0
        let mut items = 0
        let mut valid = true
        while start < text.length() {
          if items >= limits.max_items || items >= 100 {
            valid = false
            break
          }
          // The vendor permits 2000 characters per text object. This maximum
          // UTF16 chunk size is also safe for scalar-counting implementations;
          // a surrogate pair is never split, and the complete value is kept.
          let mut end = (text.length() - start).min(2000) + start
          if end < text.length() {
            let unit = text.code_unit_at(end - 1).to_int()
            if unit >= 0xd800 && unit <= 0xdbff {
              end -= 1
            }
          }
          @encode.begin_object(writer)
          @encode.key(writer, "type")
          @encode.string_value(writer, "text")
          @encode.key(writer, "text")
          @encode.begin_object(writer)
          @encode.key(writer, "content")
          @encode.string_value(writer, text[start:end].to_owned())
          @encode.end_object(writer)
          @encode.end_object(writer)
          items += 1
          start = end
        }
        @encode.end_array(writer)
        if valid {
          Ok(())
        } else {
          Err(BudgetExceeded)
        }
      }
      @admitted.Text(text) if ["url", "email", "phone_number"].contains(kind) =>
        // These native fields do not preserve empty Text distinctly from null.
        if text.is_empty() {
          Err(InvalidValue(property.id))
        } else {
          @encode.string_value(writer, text)
          Ok(())
        }
      @admitted.Text(_) if kind == "select" || kind == "status" => {
        @encode.begin_object(writer)
        @encode.key(writer, "id")
        @encode.string_value(writer, option.unwrap())
        @encode.end_object(writer)
        Ok(())
      }
      @admitted.Array(values) if kind == "people" || kind == "relation" => {
        let count = @admitted.element_count(values)
        if count > limits.max_items || count > 100 || count > remaining {
          Err(BudgetExceeded)
        } else {
          remaining -= count
          let mut issue : NotionPropertyWriteIssue? = None
          @encode.begin_array(writer)
          for index in 0..<count {
            match @admitted.element_at(values, index).unwrap() {
              @admitted.Text(id) if !id.is_empty() => {
                if id.length() > limits.max_text_units ||
                  id.length() > remaining {
                  issue = Some(BudgetExceeded)
                  break
                }
                remaining -= id.length()
                @encode.begin_object(writer)
                @encode.key(writer, "id")
                @encode.string_value(writer, id)
                @encode.end_object(writer)
              }
              _ => {
                issue = Some(InvalidValue(property.id))
                break
              }
            }
          }
          @encode.end_array(writer)
          match issue {
            Some(issue) => Err(issue)
            None => Ok(())
          }
        }
      }
      _ => Err(InvalidValue(property.id))
    }
  } catch {
    _ => Err(BudgetExceeded)
  }
  match result {
    Err(issue) => {
      @encode.cancel_writer(writer)
      return Err(issue)
    }
    Ok(_) => ()
  }
  let document = try {
    @encode.end_object(writer)
    @encode.finish_document(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  Ok({ source, property, value, document, })
}

///|
pub fn notion_property_write_matches(
  write : NotionPropertyWrite,
  source : NotionDataSourceCatalog,
  value : @admitted.CheckedValue,
) -> Bool {
  physical_equal(write.source, source) && physical_equal(write.value, value)
}

///|
/// Original ids, not display names or a representative property. A complete
/// body is returned only after all members and duplicate ids are checked.
pub fn notion_page_properties_write_wire(
  source : NotionDataSourceCatalog,
  writes : Array[NotionPropertyWrite],
  limits : NotionPropertyWriteLimits,
) -> Result[String, NotionPropertyWriteIssue] {
  if !notion_write_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if writes.length() > limits.max_properties ||
    writes.length() > limits.max_work {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work - writes.length()
  let ids : Map[String, Bool] = Map([])
  for write in writes {
    if !physical_equal(write.source, source) {
      return Err(ForeignOriginal)
    }
    if write.property.id.length() > work {
      return Err(BudgetExceeded)
    }
    work -= write.property.id.length()
    if ids.contains(write.property.id) {
      return Err(DuplicateProperty(write.property.id))
    }
    ids[write.property.id] = true
  }
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidLimits)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "properties")
    @encode.begin_object(writer)
    for write in writes {
      @encode.key(writer, write.property.id)
      @encode.emit_document(writer, write.document)
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
