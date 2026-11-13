///|
/// Exact quoted String output geometry without a Writer, encoded copy, or
/// normalization. The scalar walk matches quoted_contents: controls escape,
/// other valid Unicode scalars retain their spelling. Neither size is a grant.
/// Return None for invalid UTF16, before any output constructor is entered.
pub fn quoted_string_construction_extent(text : String) -> (Int64, Int64)? {
  let mut bytes = 2L
  let mut units = 2L
  let mut i = 0
  while i < text.length() {
    let unit = text[i].to_int()
    if unit == 0x22 ||
      unit == 0x5c ||
      unit == 8 ||
      unit == 12 ||
      unit == 10 ||
      unit == 13 ||
      unit == 9 {
      bytes += 2L
      units += 2L
    } else if unit < 32 {
      bytes += 6L
      units += 6L
    } else if unit >= 0xd800 && unit <= 0xdbff {
      if i + 1 >= text.length() {
        return None
      }
      let low = text[i + 1].to_int()
      if low < 0xdc00 || low > 0xdfff {
        return None
      }
      bytes += 4L
      units += 2L
      i += 1
    } else if unit >= 0xdc00 && unit <= 0xdfff {
      return None
    } else {
      bytes += if unit < 128 { 1L } else if unit < 2048 { 2L } else { 3L }
      units += 1L
    }
    i += 1
  }
  Some((bytes, units))
}
