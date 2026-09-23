///|
pub(all) enum MappingConversionIssue {
  InvalidLimits
  WorkLimit
  InvalidConversion(Int)
  UnknownTargetField(String)
  DuplicateConversion(String, String)
} derive(Eq, Debug)

///|
pub struct MappingConversion {
  target_field : String
  source_contract_cid : String
  conversion_law_cid : String
}

///|
pub fn mapping_conversion_target(value : MappingConversion) -> String {
  value.target_field
}

///|
pub fn mapping_conversion_source_cid(value : MappingConversion) -> String {
  value.source_contract_cid
}

///|
pub fn mapping_conversion_law_cid(value : MappingConversion) -> String {
  value.conversion_law_cid
}

///|
pub struct MappingConversions {
  shape : MappingContractShape
  entries : Array[MappingConversion]
  by_input : Map[String, Int]
  work : Int
}

///|
pub fn mapping_conversions_shape(
  value : MappingConversions,
) -> MappingContractShape {
  value.shape
}

///|
pub fn mapping_conversion_count(value : MappingConversions) -> Int {
  value.entries.length()
}

///|
pub fn mapping_conversion_at(
  value : MappingConversions,
  index : Int,
) -> MappingConversion? {
  value.entries.get(index)
}

///|
pub fn mapping_conversion_for(
  value : MappingConversions,
  target_field : String,
  source_contract_cid : String,
) -> MappingConversion? {
  match value.by_input.get(target_field + "|" + source_contract_cid) {
    Some(index) => Some(value.entries[index])
    None => None
  }
}

///|
pub fn mapping_conversions_work(value : MappingConversions) -> Int {
  value.work
}

///|
fn mapping_conversion_text(
  object : @decode.ObjectView,
  name : String,
) -> String? {
  match @decode.lookup(object, name) {
    Some(value) =>
      match @decode.text(value) {
        Ok(text) if !text.is_empty() => Some(text)
        _ => None
      }
    None => None
  }
}

///|
/// Check every declared conversion reference and its target/source pair.
/// A law CID is an obligation, not evidence that a converter is registered,
/// type-correct, or available at the selected Site.
pub fn check_mapping_conversions(
  shape : MappingContractShape,
  max_work : Int,
) -> Result[MappingConversions, MappingConversionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let root = member_body(shape.item)
  let object = @decode.open_object(root).unwrap()
  let conversions = match @decode.lookup(object, "conversions") {
    Some(value) => value
    None => return Err(InvalidConversion(0))
  }
  let count = match @decode.array_length(conversions) {
    Some(value) => value
    None => return Err(InvalidConversion(0))
  }
  if count > max_work || shape.writable_fields.length() > max_work - count {
    return Err(WorkLimit)
  }
  let writable : Map[String, Bool] = Map([])
  for field in shape.writable_fields {
    writable[field] = true
  }
  let entries : Array[MappingConversion] = []
  let by_input : Map[String, Int] = Map([])
  for index in 0..<count {
    let source = @decode.element_at(conversions, index).unwrap()
    let item = match
      @decode.closed_object(source, [
        "target_field", "source_contract_cid", "conversion_law_cid",
      ]) {
      Ok(value) => value
      Err(_) => return Err(InvalidConversion(index))
    }
    let target_field = match mapping_conversion_text(item, "target_field") {
      Some(value) => value
      None => return Err(InvalidConversion(index))
    }
    let source_contract_cid = match
      mapping_conversion_text(item, "source_contract_cid") {
      Some(value) if mapping_cid_valid(value) => value
      _ => return Err(InvalidConversion(index))
    }
    let conversion_law_cid = match
      mapping_conversion_text(item, "conversion_law_cid") {
      Some(value) if mapping_cid_valid(value) => value
      _ => return Err(InvalidConversion(index))
    }
    if !writable.contains(target_field) {
      return Err(UnknownTargetField(target_field))
    }
    let key = target_field + "|" + source_contract_cid
    if by_input.contains(key) {
      return Err(DuplicateConversion(target_field, source_contract_cid))
    }
    by_input[key] = entries.length()
    entries.push({ target_field, source_contract_cid, conversion_law_cid, })
  }
  Ok({ shape, entries, by_input, work: count + shape.writable_fields.length(), })
}
