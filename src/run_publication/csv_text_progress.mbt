///|
// Common CSV escaping, independent of Result versus Content framing/options.
// A caller owns aggregate bytes, input custody and the provisional sink. Each
// advance returns a bounded piece; a piece never establishes content completion.
priv struct CsvQuotedText {
  mut text : String?
  max_bytes : Int
  mut bytes : Int
  mut position : Int
  mut phase : Int
  quoted : Bool
}

///|
fn start_csv_quoted_text(
  text : String,
  max_bytes : Int,
) -> Result[CsvQuotedText, DeliverySerializationIssue] {
  start_csv_text(text, max_bytes, quoted=true)
}

///|
// Unquoted mode still doubles data quotes: it is also used for bounded
// canonical-value fragments inside one enclosing CSV quoted cell.
fn start_csv_text(
  text : String,
  max_bytes : Int,
  quoted~ : Bool,
) -> Result[CsvQuotedText, DeliverySerializationIssue] {
  if max_bytes < 0 {
    return Err(DeliverySerializationInvalidLimits)
  }
  Ok({
    text: Some(text),
    max_bytes,
    bytes: 0,
    position: 0,
    phase: if quoted {
      0
    } else {
      1
    },
    quoted,
  })
}

///|
fn cancel_csv_quoted_text(cursor : CsvQuotedText) -> Unit {
  cursor.text = None
  cursor.phase = 3
}

///|
// One logical work unit is an opening/closing quote or one Unicode scalar.
// Quote doubling is emitted in that scalar's unit; UTF-16 pairs never split.
fn advance_csv_quoted_text(
  cursor : CsvQuotedText,
  quantum : Int,
) -> Result[(String, Bool, Int), DeliverySerializationIssue] {
  if quantum < 1 || quantum > 64 {
    return Err(DeliverySerializationInvalidLimits)
  }
  guard cursor.text is Some(text) && cursor.phase < 2 else {
    return Err(DeliverySerializationClosed)
  }
  let output = StringBuilder()
  let mut work = 0
  while work < quantum && cursor.phase < 2 {
    let mut size = 1
    let mut scalar = 34
    let mut doubled = false
    if cursor.phase == 1 && cursor.position < text.length() {
      scalar = text[cursor.position].to_int()
      if scalar == 0 {
        cancel_csv_quoted_text(cursor)
        return Err(DeliverySerializationNul)
      }
      let mut width = 1
      if scalar >= 0xd800 && scalar <= 0xdbff {
        if cursor.position + 1 >= text.length() {
          cancel_csv_quoted_text(cursor)
          return Err(DeliverySerializationInvalidRow)
        }
        let low = text[cursor.position + 1].to_int()
        if low < 0xdc00 || low > 0xdfff {
          cancel_csv_quoted_text(cursor)
          return Err(DeliverySerializationInvalidRow)
        }
        scalar = 0x10000 + ((scalar - 0xd800) << 10) + low - 0xdc00
        width = 2
      } else if scalar >= 0xdc00 && scalar <= 0xdfff {
        cancel_csv_quoted_text(cursor)
        return Err(DeliverySerializationInvalidRow)
      }
      size = if scalar == 34 {
        doubled = true
        2
      } else if scalar < 128 {
        1
      } else if scalar < 2048 {
        2
      } else if scalar < 65536 {
        3
      } else {
        4
      }
      cursor.position += width
    } else if cursor.phase == 0 {
      cursor.phase = 1
    } else {
      cursor.phase = 2
      if !cursor.quoted {
        size = 0
      }
    }
    if size > cursor.max_bytes - cursor.bytes {
      cancel_csv_quoted_text(cursor)
      return Err(DeliverySerializationOutputLimit)
    }
    if doubled {
      output.write_char('"')
    }
    if size > 0 {
      output.write_char(scalar.unsafe_to_char())
    }
    cursor.bytes += size
    work += 1
  }
  let complete = cursor.phase == 2
  if complete {
    cursor.text = None
  }
  Ok((output.to_string(), complete, work))
}
