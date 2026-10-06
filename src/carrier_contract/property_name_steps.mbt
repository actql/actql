///|
/// Compare admitted Graph names with the existing ASCII-folded identity rule.
/// No normalized copy or hash is built. The caller retains and charges the
/// offset; each poll examines at most 64 UTF-16 units.
pub fn compare_property_name_fragment(
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
    let raw_a = left[position]
    let raw_b = right[position]
    let a = if raw_a >= 0x41 && raw_a <= 0x5A { raw_a + 0x20 } else { raw_a }
    let b = if raw_b >= 0x41 && raw_b <= 0x5A { raw_b + 0x20 } else { raw_b }
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
