///|
/// Count Unicode scalar values without normalization or allocation. Ill-formed
/// UTF-16 is not text and returns None. The count cannot exceed String.length().
/// Language string constraints require callers to normalize with NFC then LF first.
pub fn unicode_scalar_count(text : String) -> Int? {
  let mut index = 0
  let mut count = 0
  while index < text.length() {
    let unit = text[index].to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if index + 1 >= text.length() {
        return None
      }
      let trailing = text[index + 1].to_int()
      if trailing < 0xDC00 || trailing > 0xDFFF {
        return None
      }
      index = index + 1
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      return None
    }
    count = count + 1
    index = index + 1
  }
  Some(count)
}
