///|
/// Finite DATA encoding bounds, not a numerical grant or provider permission.
pub(all) struct RecordWriteLimits {
  max_fields : Int
  max_name_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
  max_output_bytes : Int
}

///|
pub(all) enum RecordWriteIssue {
  InvalidLimits
  BudgetExceeded
  EmptyWrite
  DuplicateField(String)
  FieldUnavailable(String)
  InvalidValue(String)
  UnrepresentableValue(String)
} derive(Eq, Debug)

///|
/// The original Form and original checked cells remain held beside the native
/// field-value document. No request, target, approval or claim is issued here.
pub struct RecordWriteValues {
  priv catalog : FormFieldCatalog
  priv originals : Array[(String, @admitted.CheckedValue)]
  priv document : @encode.EncodedDocument
}

///|
fn write_field_available(
  catalog : FormFieldCatalog,
  field : FormFieldMetadata,
) -> Bool {
  if field.native_type == "SINGLE_LINE_TEXT" &&
    field.write_expression != Some("") {
    return false
  }
  // The complete Form owns every original mapping destination, including
  // mappings declared later or in a subtable. Neither a missing observation
  // nor the lookup input itself is a copied-field proof.
  for owner in catalog.fields {
    guard owner.write_lookup_targets is Some(targets) else { return false }
    for target in targets {
      if target == field.code {
        return false
      }
    }
  }
  true
}

///|
fn write_value_contract(field : FormFieldMetadata) -> @contract.Contract? {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  match field.native_type {
    "SINGLE_LINE_TEXT" | "MULTI_LINE_TEXT" | "RICH_TEXT" | "LINK" => Some(text)
    "RADIO_BUTTON" | "DROP_DOWN" =>
      Some(@contract.primitive(@contract.StringType, nullable=true))
    "DATE" => Some(@contract.primitive(@contract.DateType, nullable=true))
    "DATETIME" =>
      Some(@contract.primitive(@contract.TimestampType, nullable=true))
    "CHECK_BOX"
    | "MULTI_SELECT"
    | "USER_SELECT"
    | "ORGANIZATION_SELECT"
    | "GROUP_SELECT" => @contract.array_contract(text, nullable=false)
    // Read-only/process fields and privileged create-only metadata are not
    // regular record-update candidates. Number
    // storage, Time, original table rows and issued Content need their own
    // existing carrier/original connections, never a String/Double fallback.
    _ => None
  }
}

///|
/// Read-only write-carrier projection from this original Form. This does not
/// issue provider permission, a Mapping, current authority or a dispatch use.
pub fn record_write_field_contract(
  catalog : FormFieldCatalog,
  code : String,
) -> @contract.Contract? {
  guard form_field_named(catalog, [code]) is Some(field) &&
    write_field_available(catalog, field) else {
    return None
  }
  write_value_contract(field)
}

///|
/// Same original Form's top-level native write projection by inventory index.
/// This avoids constructing a detached path catalogue during implementation
/// quotation. It neither changes writable types nor admits a value/permission.
pub fn record_write_field_contract_at(
  catalog : FormFieldCatalog,
  index : Int,
) -> @contract.Contract? {
  guard catalog.fields.get(index) is Some(field) &&
    field.path.length() == 1 &&
    write_field_available(catalog, field) else {
    return None
  }
  write_value_contract(field)
}

///|
fn write_native_value(
  writer : @encode.Writer,
  field : FormFieldMetadata,
  value : @admitted.Value,
) -> Unit raise @encode.EncodeFailure {
  match value {
    @admitted.Null => @encode.null_value(writer)
    @admitted.Text(text) | @admitted.Date(text) =>
      @encode.string_value(writer, text)
    @admitted.Timestamp(text) =>
      // Common canonical timestamps have exactly three fractional digits;
      // only a proved zero fraction is representable by native whole seconds.
      @encode.string_value(writer, text[:19].to_owned() + "Z")
    @admitted.Array(values) => {
      @encode.begin_array(writer)
      for index in 0..<@admitted.element_count(values) {
        let value = @admitted.element_at(values, index).unwrap()
        let text = match value {
          @admitted.Text(text) => text
          _ => abort("checked string-array invariant")
        }
        if field.native_type == "USER_SELECT" ||
          field.native_type == "ORGANIZATION_SELECT" ||
          field.native_type == "GROUP_SELECT" {
          @encode.begin_ordered_object(writer)
          @encode.ordered_key(writer, "code")
          @encode.string_value(writer, text)
          @encode.end_object(writer)
        } else {
          @encode.string_value(writer, text)
        }
      }
      @encode.end_array(writer)
    }
    _ => abort("checked native write invariant")
  }
}

///|
/// Encode exact declared field codes from Common values, without turning UI
/// defaults, labels or native read-only fields into intended writes. Native
/// validation still applies; this is not a claim that a provider accepted it.
pub fn prepare_record_write_values(
  catalog : FormFieldCatalog,
  cells : Array[(String, @admitted.CheckedValue)],
  limits : RecordWriteLimits,
) -> Result[RecordWriteValues, RecordWriteIssue] {
  if limits.max_fields <= 0 ||
    limits.max_name_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_text_bytes <= 0 ||
    limits.max_output_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if cells.is_empty() {
    return Err(EmptyWrite)
  }
  if cells.length() > limits.max_fields {
    return Err(BudgetExceeded)
  }
  let seen : Map[String, Bool] = Map([])
  let originals = []
  let checked = []
  let mut nodes = limits.max_nodes
  let mut text_bytes = limits.max_text_bytes
  for (code, value) in cells {
    // Check the caller's string bound before hashing it into the inventory.
    guard @scalar.admit_utf8_length(code, limits.max_name_bytes) is Ok(bytes) &&
      bytes <= text_bytes else {
      return Err(BudgetExceeded)
    }
    if seen.contains(code) {
      return Err(DuplicateField(code))
    }
    seen[code] = true
    text_bytes -= bytes
    guard form_field_named(catalog, [code]) is Some(field) &&
      record_write_field_contract(catalog, code) is Some(contract) else {
      return Err(FieldUnavailable(code))
    }
    guard @admitted.recheck_runtime_value_usage(value.value, contract, {
        max_nodes: nodes,
        max_depth: limits.max_depth,
        max_text_bytes: text_bytes,
      })
      is Some((admitted, used_nodes, used_text)) else {
      return Err(InvalidValue(code))
    }
    nodes -= used_nodes
    text_bytes -= used_text
    match admitted.value {
      @admitted.Null if field.native_type == "RADIO_BUTTON" =>
        return Err(UnrepresentableValue(code))
      @admitted.Text(text) if text.is_empty() &&
        (
          field.native_type == "RADIO_BUTTON" ||
          field.native_type == "DROP_DOWN"
        ) => return Err(UnrepresentableValue(code))
      @admitted.Date(text) if text < "1000-01-01" =>
        return Err(UnrepresentableValue(code))
      @admitted.Timestamp(text) if text < "1000-01-01T00:00:00.000Z" ||
        text.length() != 24 ||
        text[19:24] != ".000Z" => return Err(UnrepresentableValue(code))
      _ => ()
    }
    originals.push((code, value))
    checked.push((code, field, admitted))
  }
  let writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let document = try {
    @encode.begin_object(writer)
    for (code, field, value) in checked {
      @encode.key(writer, code)
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "value")
      write_native_value(writer, field, value.value)
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.finish_document(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  Ok({ catalog, originals, document, })
}

///|
pub fn record_write_values_body(values : RecordWriteValues) -> String {
  @encode.document_text(values.document)
}

///|
pub fn record_write_values_fields(values : RecordWriteValues) -> Array[String] {
  values.originals.map(cell => cell.0)
}

///|
pub fn record_write_values_match_catalog(
  values : RecordWriteValues,
  catalog : FormFieldCatalog,
) -> Bool {
  physical_equal(values.catalog, catalog)
}
