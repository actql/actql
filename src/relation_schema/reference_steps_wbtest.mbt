///|
test "reference spelling fragments retain raw UTF16 and virtual qualification" {
  let text = String::make(58, 'a') + "😀" + String::make(70, 'é')
  let left = Qualified(Left, text)
  let right = Unqualified("left." + text)
  // Five qualification units + 58 ASCII + two surrogate units + 70 BMP.
  assert_eq(compare_reference_fragment(left, right, 0, 64), (None, 64, 64))
  assert_eq(compare_reference_fragment(left, right, 64, 64), (None, 128, 64))
  assert_eq(compare_reference_fragment(left, right, 128, 64), (Some(0), 0, 7))
  assert_eq(
    compare_reference_fragment(left, Qualified(Right, text), 0, 64),
    (Some(-1), 0, 1),
  )
  assert_eq(
    compare_reference_fragment(
      Unqualified("😀"),
      Unqualified("\ue000"),
      0,
      64,
    ),
    (Some(-1), 0, 1),
  )
  assert_eq(
    compare_reference_fragment(Unqualified("é"), Unqualified("é"), 0, 64),
    (Some(-1), 0, 1),
  )
  assert_eq(
    compare_reference_fragment(Unqualified("a"), Unqualified("a"), 0, 0),
    (None, 0, 0),
  )
  assert_eq(
    compare_reference_fragment(Unqualified(""), Unqualified(""), 0, 64),
    (Some(0), 0, 0),
  )
}

///|
test "reference spelling fragments cap requested allowance and retain budget position" {
  let name = Unqualified(String::make(130, 'x'))
  assert_eq(compare_reference_fragment(name, name, 0, 100000), (None, 64, 64))
  assert_eq(compare_reference_fragment(name, name, 64, 7), (None, 71, 7))
  assert_eq(compare_reference_fragment(name, name, 71, 64), (Some(0), 0, 59))
  assert_eq(compare_reference_fragment(name, name, -1, 64), (None, -1, 0))
  assert_eq(compare_reference_fragment(name, name, 0, -1), (None, 0, 0))
}
