///|
/// A real compiled payload whose identity must survive the private JS binding.
struct Original {
  value : Int
}

///|
#export_name("bindingOriginal")
pub fn original(value : Int) -> Original {
  { value, }
}

///|
#export_name("bindingOriginalValue")
pub fn original_value(original : Original) -> Int {
  original.value
}

///|
#export_name("bindingAccept")
pub fn accept(original : Original) -> Result[Original, String] {
  if original.value < 0 {
    Err("BindingContractRefused")
  } else {
    Ok(original)
  }
}

///|
#export_name("bindingUnit")
pub fn unit() -> Result[Unit, String] {
  Ok(())
}

///|
#export_name("bindingOption")
pub fn optional(original : Original, present : Bool) -> Original? {
  if present {
    Some(original)
  } else {
    None
  }
}

///|
#export_name("bindingUnitOption")
pub fn optional_unit(present : Bool) -> Unit? {
  if present {
    Some(())
  } else {
    None
  }
}

///|
#export_name("bindingTuple")
pub fn tuple(original : Original) -> (Original, String, Int64) {
  (original, "original\nUnicode: λ", 9007199254740993L)
}

///|
#export_name("bindingPairInput")
pub fn pair_input(pair : (Original, Original)) -> Bool {
  pair.0.value == 7 && pair.1.value == 11
}
