///|
// Advance one UTF-16 code-unit comparison in the existing bounded session.
// None retains the next position; every completed comparison resets it.
// Order is identical to canonical compare_utf16, without a whole-key scan
// hidden inside one charged control transition.
fn graph_identity_compare_unit(
  left : String,
  right : String,
  position : Int,
) -> (Int?, Int) {
  if position >= left.length() || position >= right.length() {
    return (
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
    )
  }
  if left[position] < right[position] {
    return (Some(-1), 0)
  }
  if left[position] > right[position] {
    return (Some(1), 0)
  }
  let next = position + 1
  if next >= left.length() || next >= right.length() {
    return (
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
    )
  }
  (None, next)
}
