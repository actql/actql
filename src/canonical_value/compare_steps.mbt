///|
/// A fragment of raw UTF-16 comparison, without normalization or admission.
/// The caller retains the offset and charges each poll. A successor offset
/// belongs only to the same immutable input pair; each call scans at most
/// 64 code units. Negative offsets/allowances do not inspect either input.
pub fn compare_utf16_fragment(
  left : String,
  right : String,
  offset : Int,
  allowance : Int,
) -> (Int?, Int, Int) {
  if offset < 0 || allowance < 0 {
    return (None, offset, 0)
  }
  let common = left.length().min(right.length())
  let mut position = offset
  let mut spent = 0
  while position < common && spent < allowance.min(64) {
    let a = left[position]
    let b = right[position]
    position += 1
    spent += 1
    if a != b {
      return (Some(if a < b { -1 } else { 1 }), 0, spent)
    }
  }
  if position < common {
    (None, position, spent)
  } else {
    (
      Some(
        if left.length() < right.length() {
          -1
        } else if left.length() > right.length() {
          1
        } else {
          0
        },
      ),
      0,
      spent,
    )
  }
}
