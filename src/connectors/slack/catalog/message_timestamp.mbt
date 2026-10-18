///|
// Slack's decimal epoch token is an identity String. Only its derived instant
// enters the existing Timestamp owner; neither identity nor arithmetic uses a
// binary64 intermediary. This is physical response normalization, not authored
// Timestamp admission or a trusted clock.
fn message_epoch_timestamp(text : String) -> String? {
  let negative = text.has_prefix("-")
  let start = if negative { 1 } else { 0 }
  let mut point = -1
  for index in start..<text.length() {
    if text[index] == '.' && point < 0 {
      point = index
    } else if text[index] < '0' || text[index] > '9' {
      return None
    }
  }
  if point <= start ||
    point - start > 19 ||
    text.length() - point - 1 < 1 ||
    text.length() - point - 1 > 9 {
    return None
  }
  let whole = match @scalar.read_decimal_int64(text[start:point].to_owned()) {
    Ok(value) => value
    Err(_) => return None
  }
  let mut fraction = 0
  for index in (point + 1)..<text.length() {
    fraction = fraction * 10 + text[index].to_int() - 48
  }
  for _ in (text.length() - point - 1)..<9 {
    fraction *= 10
  }
  if negative && fraction != 0 {
    if whole == 9223372036854775807L {
      return None
    }
    @admitted.epoch_parts_timestamp(-whole - 1L, 1000000000 - fraction)
  } else {
    @admitted.epoch_parts_timestamp(
      if negative {
        -whole
      } else {
        whole
      },
      fraction,
    )
  }
}
