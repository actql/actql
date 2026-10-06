///|
fn reference_parts(name : FieldName) -> (String, String) {
  match name {
    Unqualified(text) => ("", text)
    Qualified(Left, text) => ("left.", text)
    Qualified(Right, text) => ("right.", text)
  }
}

///|
/// Compare reference spellings without flattening qualification. This proves
/// spelling equality only, not typed-role equality, schema admission or identity.
/// The caller owns the offset and charges each fragment. Negative offsets or
/// allowances do not scan; admitted names have representable combined lengths.
/// Return a terminal order with offset zero, or the retained next offset.
pub fn compare_reference_fragment(
  left : FieldName,
  right : FieldName,
  offset : Int,
  allowance : Int,
) -> (Int?, Int, Int) {
  if offset < 0 || allowance < 0 {
    return (None, offset, 0)
  }
  let (lp, lt) = reference_parts(left)
  let (rp, rt) = reference_parts(right)
  let ll = lp.length().to_int64() + lt.length().to_int64()
  let rl = rp.length().to_int64() + rt.length().to_int64()
  let common = ll.min(rl)
  let mut position = offset
  let mut spent = 0
  while position.to_int64() < common && spent < allowance.min(64) {
    let a = if position < lp.length() {
      lp[position]
    } else {
      lt[position - lp.length()]
    }
    let b = if position < rp.length() {
      rp[position]
    } else {
      rt[position - rp.length()]
    }
    position += 1
    spent += 1
    if a != b {
      return (Some(if a < b { -1 } else { 1 }), 0, spent)
    }
  }
  if position.to_int64() < common {
    (None, position, spent)
  } else {
    (Some(if ll < rl { -1 } else if ll > rl { 1 } else { 0 }), 0, spent)
  }
}
