///|
priv enum TextMembership {
  TextMember
  TextMembershipContinue(Int, Int)
  TextNotMember
}

///|
/// Borrow the admitted original vector, inspecting one candidate and at most
/// 64 UTF-16 units. No copied lookup table, normalization or inferred member.
fn text_membership_step(
  value : String,
  bounds : @contract.TextLimits,
  entry : Int,
  offset : Int,
) -> TextMembership {
  guard @contract.text_enumerant_count(bounds) is Some(count) else {
    return TextMember
  }
  guard @contract.text_enumerant_at(bounds, entry) is Some(expected) else {
    return TextNotMember
  }
  let next = if entry + 1 < count {
    TextMembershipContinue(entry + 1, 0)
  } else {
    TextNotMember
  }
  if expected.length() != value.length() {
    return next
  }
  let end = offset + Int::min(64, value.length() - offset)
  for index in offset..<end {
    if value[index] != expected[index] {
      return next
    }
  }
  if end < value.length() {
    TextMembershipContinue(entry, end)
  } else {
    TextMember
  }
}

///|
fn text_enum_accepts(value : String, bounds : @contract.TextLimits) -> Bool {
  let mut entry = 0
  let mut offset = 0
  while true {
    match text_membership_step(value, bounds, entry, offset) {
      TextMember => return true
      TextNotMember => return false
      TextMembershipContinue(next, unit) => {
        entry = next
        offset = unit
      }
    }
  } nobreak {
    false
  }
}
