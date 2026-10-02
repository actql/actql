///|
pub(all) enum Utf8AdmissionIssue {
  InvalidLimit
  LimitExceeded
  MalformedUtf16(Int)
} derive(Debug, Eq)

///|
/// Optional projection of the typed result; all rejection reasons become None.
pub fn utf8_length_within(text : String, limit : Int) -> Int? {
  match admit_utf8_length(text, limit) {
    Ok(bytes) => Some(bytes)
    Err(_) => None
  }
}

///|
/// Exact raw UTF-8 byte length without normalization or byte allocation.
/// Counts the preserved scalar value; identifier normalization is a separate contract.
/// Error order: invalid limit, whole-string UTF-16 lower bound, then the first
/// malformed scalar or byte overflow encountered in a left-to-right scan.
pub fn admit_utf8_length(
  text : String,
  limit : Int,
) -> Result[Int, Utf8AdmissionIssue] {
  match admit_utf8_length64(text, limit.to_int64()) {
    Ok(bytes) => Ok(bytes.to_int())
    Err(issue) => Err(issue)
  }
}

///|
/// Same scan and error order as the Int API, without narrowing the allowance.
pub fn admit_utf8_length64(
  text : String,
  limit : Int64,
) -> Result[Int64, Utf8AdmissionIssue] {
  admit_utf8_window(text, limit, 2147483647)
}

///|
/// Use bounded Int accounting windows and an Int64 balance. Windows never split
/// or copy text and never perform their own UTF-16-length early rejection.
/// Refilling the accounting window cannot change which input error is reported.
/// Small windows let tests exercise refills without multi-gigabyte strings.
/// A window must fit one complete scalar, whose UTF-8 width is at most four bytes.
fn admit_utf8_window(
  text : String,
  limit : Int64,
  window : Int,
) -> Result[Int64, Utf8AdmissionIssue] {
  if limit < 0 || window < 4 {
    return Err(InvalidLimit)
  }
  if text.length().to_int64() > limit {
    return Err(LimitExceeded)
  }
  // ASCII has the same UTF-16 and UTF-8 length. Account for its prefix in
  // whole windows and continue the scalar scan at the first non-ASCII unit.
  let mut ascii_index = 0
  while ascii_index < text.length() && text[ascii_index].to_int() < 0x80 {
    ascii_index += 1
  }
  if ascii_index == text.length() {
    return Ok(ascii_index.to_int64())
  }
  let consumed = ascii_index / window * window
  let mut remaining = limit - consumed.to_int64()
  let mut allowance = if remaining > window.to_int64() {
    window
  } else {
    remaining.to_int()
  }
  let mut used = ascii_index - consumed
  let mut index = ascii_index
  while index < text.length() {
    let unit = text[index].to_int()
    let width = if unit < 0x80 {
      1
    } else if unit < 0x800 {
      2
    } else if unit >= 0xd800 && unit <= 0xdbff {
      if index + 1 >= text.length() {
        return Err(MalformedUtf16(index))
      }
      let trailing = text[index + 1].to_int()
      if trailing < 0xdc00 || trailing > 0xdfff {
        return Err(MalformedUtf16(index))
      }
      4
    } else if unit >= 0xdc00 && unit <= 0xdfff {
      return Err(MalformedUtf16(index))
    } else {
      3
    }
    if width > allowance - used {
      remaining -= used.to_int64()
      used = 0
      allowance = if remaining > window.to_int64() {
        window
      } else {
        remaining.to_int()
      }
      if width > allowance {
        return Err(LimitExceeded)
      }
    }
    used += width
    index += if width == 4 { 2 } else { 1 }
  }
  Ok(limit - remaining + used.to_int64())
}
