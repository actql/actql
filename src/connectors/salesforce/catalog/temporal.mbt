///|
/// Salesforce's documented range for `date` and `datetime` values:
/// 1700-01-01 to 4000-12-31, in UTC for a datetime. A value outside it is
/// refused before it is sent.
const DATE_MIN : String = "1700-01-01"

///|
const DATE_MAX : String = "4000-12-31"

///|
const DATETIME_MIN : String = "1700-01-01T00:00:00.000Z"

///|
const DATETIME_MAX : String = "4000-12-31T00:00:00.000Z"

///|
/// An ActQL `date`: `YYYY-MM-DD`, a valid proleptic Gregorian date.
fn actql_date(text : String) -> Bool {
  text.length() == 10 &&
  @admitted.timestamp_epoch_milliseconds(text + "T00:00:00.000Z") is Some(_)
}

///|
/// An ActQL `timestamp`: UTC `YYYY-MM-DDTHH:mm:ss.sssZ`.
fn actql_timestamp(text : String) -> Bool {
  @admitted.timestamp_epoch_milliseconds(text) is Some(_)
}

///|
/// Salesforce reports a datetime in UTC as `yyyy-MM-ddTHH:mm:ss.SSS+0000`.
/// Exactly that spelling names the same instant as the ActQL timestamp that
/// ends in `Z` instead. No other offset or form is converted: a value in any
/// other spelling is not read as a timestamp, and no local time zone applies.
fn salesforce_datetime_utc(text : String) -> String? {
  if text.length() != 28 || !text.has_suffix("+0000") {
    return None
  }
  let utc = text[:23].to_owned() + "Z"
  if actql_timestamp(utc) {
    Some(utc)
  } else {
    None
  }
}

///|
/// Why a written `date` or `datetime` value is refused before it is sent.
fn temporal_write_issue(
  native_type : String,
  text : String,
  field : String,
) -> WriteBodyIssue? {
  match native_type {
    "date" =>
      if !actql_date(text) {
        Some(InvalidValue(field))
      } else if text < DATE_MIN || text > DATE_MAX {
        Some(ValueOutOfRange(field))
      } else {
        None
      }
    "datetime" =>
      if !actql_timestamp(text) {
        Some(InvalidValue(field))
      } else if !text.has_suffix(".000Z") {
        // This revision writes whole seconds only: the millisecond part is
        // never rounded or dropped.
        Some(SubsecondTimestamp(field))
      } else if text < DATETIME_MIN || text > DATETIME_MAX {
        Some(ValueOutOfRange(field))
      } else {
        None
      }
    _ => Some(InvalidValue(field))
  }
}
