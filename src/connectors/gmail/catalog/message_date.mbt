///|
enum GmailHeaderDateIssue {
  Malformed
  Unsupported
  BudgetExceeded
} derive(Eq, Debug)

///|
priv struct GmailDateText {
  text : String
  // A comment is CFWS, but is not the FWS required before a numeric zone.
  fws : Map[Int, Bool]
}

///|
priv struct GmailDateScan {
  original : GmailDateText
  mut index : Int
}

///|
fn gmail_date_text(
  text : String,
  max_units : Int,
  max_comment_depth : Int,
) -> Result[GmailDateText, GmailHeaderDateIssue] {
  if max_units < 0 || max_comment_depth < 0 || text.length() > max_units {
    return Err(BudgetExceeded)
  }
  let output = StringBuilder()
  let fws : Map[Int, Bool] = Map([])
  let mut units = 0
  let mut index = 0
  let mut depth = 0
  let mut pending = false
  let mut actual_fws = false
  while index < text.length() {
    let c = text[index]
    if depth > 0 {
      if c == '\\' {
        if index + 1 >= text.length() {
          return Err(Malformed)
        }
        index += 2
        continue
      }
      if c == '(' {
        if depth == max_comment_depth {
          return Err(BudgetExceeded)
        }
        depth += 1
      } else if c == ')' {
        depth -= 1
      } else if c == '\r' {
        if index + 2 >= text.length() ||
          text[index + 1] != '\n' ||
          (text[index + 2] != ' ' && text[index + 2] != '\t') {
          return Err(Malformed)
        }
        index += 1
      } else if c == '\n' || c.to_int() == 0 {
        return Err(Malformed)
      }
      index += 1
      continue
    }
    if c == '(' {
      if max_comment_depth == 0 {
        return Err(BudgetExceeded)
      }
      depth = 1
      pending = units > 0
    } else if c == ' ' || c == '\t' {
      pending = units > 0
      actual_fws = true
    } else if c == '\r' {
      if index + 2 >= text.length() ||
        text[index + 1] != '\n' ||
        (text[index + 2] != ' ' && text[index + 2] != '\t') {
        return Err(Malformed)
      }
      index += 1
      pending = units > 0
      actual_fws = true
    } else {
      if c.to_int() < 33 || c.to_int() > 126 || c == ')' {
        return Err(Malformed)
      }
      if pending {
        if actual_fws {
          fws[units] = true
        }
        output.write_char(' ')
        units += 1
      }
      pending = false
      actual_fws = false
      output.write_char(c.to_int().unsafe_to_char())
      units += 1
    }
    index += 1
  }
  if depth != 0 {
    return Err(Malformed)
  }
  Ok({ text: output.to_string(), fws, })
}

///|
fn gmail_date_skip_space(scan : GmailDateScan) -> Bool {
  let mut actual_fws = false
  while scan.index < scan.original.text.length() &&
        scan.original.text[scan.index] == ' ' {
    actual_fws = actual_fws || scan.original.fws.contains(scan.index)
    scan.index += 1
  }
  actual_fws
}

///|
fn gmail_date_word(scan : GmailDateScan) -> String {
  let output = StringBuilder()
  while scan.index < scan.original.text.length() {
    let c = scan.original.text[scan.index]
    if (c < 'A' || c > 'Z') && (c < 'a' || c > 'z') {
      break
    }
    output.write_char(c.to_int().unsafe_to_char())
    scan.index += 1
  }
  output.to_string().to_lower()
}

///|
fn gmail_date_number(text : String, start : Int, end : Int) -> (Int, Int) {
  let mut value = 0
  let mut mod400 = 0
  for index in start..<end {
    let digit = text[index].to_int() - 48
    // Saturation classifies years outside Value's range without overflow.
    if value < 10000 {
      value = value * 10 + digit
      if value > 10000 {
        value = 10000
      }
    }
    mod400 = (mod400 * 10 + digit) % 400
  }
  (value, mod400)
}

///|
fn gmail_date_digits(
  scan : GmailDateScan,
  minimum : Int,
  maximum : Int,
) -> (Int, Int, Int)? {
  let start = scan.index
  while scan.index < scan.original.text.length() &&
        scan.original.text[scan.index] >= '0' &&
        scan.original.text[scan.index] <= '9' {
    scan.index += 1
  }
  let count = scan.index - start
  if count < minimum || count > maximum {
    return None
  }
  let (value, mod400) = gmail_date_number(scan.original.text, start, scan.index)
  Some((value, count, mod400))
}

///|
fn gmail_date_expect(scan : GmailDateScan, c : Char) -> Bool {
  if scan.index < scan.original.text.length() &&
    scan.original.text[scan.index].to_int() == c.to_int() {
    scan.index += 1
    true
  } else {
    false
  }
}

///|
fn gmail_date_pad(value : Int, width : Int) -> String {
  let text = value.to_string()
  "0".repeat(width - text.length()) + text
}

///|
// Source RFC date conversion uses the existing UTC Value Owner. It neither
// widens authored Timestamp spelling nor samples or changes an authority clock.
fn gmail_header_date(
  text : String,
  max_units : Int,
  max_comment_depth : Int,
) -> Result[String, GmailHeaderDateIssue] {
  let original = match gmail_date_text(text, max_units, max_comment_depth) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let scan = { original, index: 0, }
  let mut weekday : Int? = None
  if scan.index < original.text.length() &&
    (
      (original.text[0] >= 'A' && original.text[0] <= 'Z') ||
      (original.text[0] >= 'a' && original.text[0] <= 'z')
    ) {
    let word = gmail_date_word(scan)
    let days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    for index, day in days {
      if word == day {
        weekday = Some(index)
      }
    }
    ignore(gmail_date_skip_space(scan))
    if weekday is None || !gmail_date_expect(scan, ',') {
      return Err(Malformed)
    }
    ignore(gmail_date_skip_space(scan))
  }
  guard gmail_date_digits(scan, 1, 2) is Some((day, _, _)) else {
    return Err(Malformed)
  }
  ignore(gmail_date_skip_space(scan))
  let month_word = gmail_date_word(scan)
  let mut month = 0
  for
    index, name in [
      "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov",
      "dec",
    ] {
    if name == month_word {
      month = index + 1
    }
  }
  if month == 0 {
    return Err(Malformed)
  }
  ignore(gmail_date_skip_space(scan))
  let year_start = scan.index
  guard gmail_date_digits(scan, 2, 2147483647)
    is Some((parsed_year, parsed_digits, parsed_mod400)) else {
    return Err(Malformed)
  }
  let mut year = parsed_year
  let mut year_digits = parsed_digits
  let mut year_mod400 = parsed_mod400
  let hour = if scan.index < original.text.length() &&
    original.text[scan.index] == ':' {
    // Obsolete CFWS can be absent between year and hour. The two digits
    // immediately before the colon are the hour, not part of the year.
    if parsed_digits < 4 {
      return Err(Malformed)
    }
    let (value, modulus) = gmail_date_number(
      original.text,
      year_start,
      scan.index - 2,
    )
    year = value
    year_mod400 = modulus
    year_digits -= 2
    gmail_date_number(original.text, scan.index - 2, scan.index).0
  } else {
    ignore(gmail_date_skip_space(scan))
    guard gmail_date_digits(scan, 2, 2) is Some((hour, _, _)) else {
      return Err(Malformed)
    }
    hour
  }
  if year_digits == 2 {
    year += if year < 50 { 2000 } else { 1900 }
    year_mod400 = year % 400
  } else if year_digits == 3 {
    year += 1900
    year_mod400 = year % 400
  }
  ignore(gmail_date_skip_space(scan))
  if !gmail_date_expect(scan, ':') {
    return Err(Malformed)
  }
  ignore(gmail_date_skip_space(scan))
  guard gmail_date_digits(scan, 2, 2) is Some((minute, _, _)) else {
    return Err(Malformed)
  }
  let mut zone_fws = gmail_date_skip_space(scan)
  let mut second = 0
  if gmail_date_expect(scan, ':') {
    ignore(gmail_date_skip_space(scan))
    guard gmail_date_digits(scan, 2, 2) is Some((value, _, _)) else {
      return Err(Malformed)
    }
    second = value
    zone_fws = gmail_date_skip_space(scan)
  }
  let zone_minutes = if scan.index < original.text.length() &&
    (original.text[scan.index] == '+' || original.text[scan.index] == '-') {
    if !zone_fws {
      return Err(Malformed)
    }
    let negative = gmail_date_expect(scan, '-')
    if !negative {
      ignore(gmail_date_expect(scan, '+'))
    }
    guard gmail_date_digits(scan, 4, 4) is Some((zone, _, _)) &&
      zone % 100 <= 59 else {
      return Err(Malformed)
    }
    let minutes = zone / 100 * 60 + zone % 100
    if negative {
      -minutes
    } else {
      minutes
    }
  } else {
    let zone = gmail_date_word(scan)
    match zone {
      "ut" | "gmt" => 0
      "est" | "cdt" => -300
      "edt" => -240
      "cst" | "mdt" => -360
      "mst" | "pdt" => -420
      "pst" => -480
      "" | "j" => return Err(Malformed)
      // RFC 5322 4.3 interprets otherwise unknown obsolete alphabetic zones
      // as -0000, not a guessed regional offset or a host locale/DST rule.
      _ => 0
    }
  }
  ignore(gmail_date_skip_space(scan))
  if scan.index != original.text.length() ||
    year < 1900 ||
    hour > 23 ||
    minute > 59 ||
    second > 60 {
    return Err(Malformed)
  }
  // The Gregorian calendar repeats every 400 years. Validation, including
  // weekday, stays in Value even for a valid year outside its output range.
  let calendar = gmail_date_pad(2000 + year_mod400, 4) +
    "-" +
    gmail_date_pad(month, 2) +
    "-" +
    gmail_date_pad(day, 2) +
    "T00:00:00.000Z"
  guard @admitted.timestamp_instant(calendar) is Some(date) else {
    return Err(Malformed)
  }
  if weekday is Some(expected) &&
    ((date.seconds / 86400L + 4L) % 7L).to_int() != expected {
    return Err(Malformed)
  }
  if year > 9999 || second == 60 {
    return Err(Unsupported)
  }
  let local_timestamp = gmail_date_pad(year, 4) +
    "-" +
    gmail_date_pad(month, 2) +
    "-" +
    gmail_date_pad(day, 2) +
    "T" +
    gmail_date_pad(hour, 2) +
    ":" +
    gmail_date_pad(minute, 2) +
    ":" +
    gmail_date_pad(second, 2) +
    ".000Z"
  guard @admitted.timestamp_instant(local_timestamp) is Some(instant) &&
    @admitted.epoch_parts_timestamp(
      instant.seconds - zone_minutes.to_int64() * 60L,
      0,
    )
    is Some(utc) else {
    return Err(Unsupported)
  }
  Ok(utc)
}
