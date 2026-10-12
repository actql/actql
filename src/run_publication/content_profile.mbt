///|
pub(all) enum ContentFormat {
  ContentCsv
  ContentJsonl
} derive(Eq, Debug)

///|
pub(all) enum ContentSerializationIssue {
  ContentInvalidLimits
  ContentInvalidOptions
  ContentMissingOption(String)
  ContentUnknownOption(String)
  ContentInvalidOption(String)
  ContentInvalidFields
  ContentConditionalCsv(String)
  ContentMissingRequired(Int)
  ContentForeignValue(Int)
  ContentReferenceUnavailable
  ContentInputUnavailableIssue
  ContentIncompleteInput
  ContentRowLimit
  ContentByteLimit
  ContentValueEncoding
  ContentClosed
  ContentBusy
} derive(Eq, Debug)

///|
/// A checked byte profile, not an order witness, input lease or Ref issuer.
/// The serialization barrier still owns those independent obligations.
struct ContentSerializationProfile {
  format : ContentFormat
  name : String
  fields : Array[@schema.Field]
  columns : Array[Int]
  header : Bool
  delimiter : String
  null_marker : String
  bom : Bool
  line_ending : String
  work : Int
}

///|
pub(all) struct ContentProfileLimits {
  max_fields : Int
  max_name_bytes : Int
  max_work : Int
  max_options_bytes : Int
  max_options_nodes : Int
  max_options_depth : Int
}

///|
/// All source formats use these defaults. CSV header and NULL spelling are
/// never defaulted; JSONL rejects CSV-only options, including false header.
pub fn prepare_content_serialization_profile(
  format : ContentFormat,
  schema : @schema.Schema,
  fields : Array[String],
  options_wire : String,
  limits : ContentProfileLimits,
) -> Result[ContentSerializationProfile, ContentSerializationIssue] {
  if limits.max_fields < 1 ||
    limits.max_name_bytes < 1 ||
    limits.max_work < 1 ||
    limits.max_options_bytes < 1 ||
    limits.max_options_nodes < 1 ||
    limits.max_options_depth < 1 {
    return Err(ContentInvalidLimits)
  }
  if fields.is_empty() || fields.length() > limits.max_fields {
    return Err(ContentInvalidFields)
  }
  let options = match
    parse_contract_wire(
      options_wire,
      limits.max_options_bytes,
      limits.max_options_nodes,
      limits.max_options_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(ContentInvalidOptions)
  }
  guard @json.object_fields(options) is Some(entries) else {
    return Err(ContentInvalidOptions)
  }
  let allowed = if format == ContentCsv {
    [
      "name", "header", "null_marker", "field_delimiter", "encoding", "line_ending",
    ]
  } else {
    ["name", "encoding", "line_ending"]
  }
  let mut work = entries.length()
  if work > limits.max_work {
    return Err(ContentInvalidLimits)
  }
  for (key, _) in entries {
    if !allowed.contains(key) {
      return Err(ContentUnknownOption(key))
    }
  }
  guard @json.object_field(options, "name") is Some(name_value) else {
    return Err(ContentMissingOption("name"))
  }
  guard name_value is @json.String(name) else {
    return Err(ContentInvalidOption("name"))
  }
  if name.is_empty() ||
    name.length() > limits.max_name_bytes ||
    @scalar.admit_utf8_length(name, limits.max_name_bytes) is Err(_) ||
    name.contains("\u{0}") {
    return Err(ContentInvalidOption("name"))
  }
  let mut header = false
  let mut marker = ""
  let mut delimiter = ","
  if format == ContentCsv {
    guard @json.object_field(options, "header") is Some(header_value) else {
      return Err(ContentMissingOption("header"))
    }
    guard header_value is @json.Bool(value) else {
      return Err(ContentInvalidOption("header"))
    }
    header = value
    guard @json.object_field(options, "null_marker") is Some(marker_value) else {
      return Err(ContentMissingOption("null_marker"))
    }
    guard marker_value is @json.String(value) && ["", "\\N"].contains(value) else {
      return Err(ContentInvalidOption("null_marker"))
    }
    marker = value
    if @json.object_field(options, "field_delimiter") is Some(value) {
      guard value is @json.String(text) && [",", ";"].contains(text) else {
        return Err(ContentInvalidOption("field_delimiter"))
      }
      delimiter = text
    }
  }
  let encoding = match @json.object_field(options, "encoding") {
    None => "utf-8"
    Some(@json.String("UTF-8")) => "utf-8"
    Some(@json.String("UTF-8-BOM")) => "utf-8-bom"
    Some(@json.String(text)) => text
    _ => return Err(ContentInvalidOption("encoding"))
  }
  if !["utf-8", "utf-8-bom"].contains(encoding) {
    return Err(ContentInvalidOption("encoding"))
  }
  let line_ending = match @json.object_field(options, "line_ending") {
    None => "lf"
    Some(@json.String("LF")) => "lf"
    Some(@json.String("CRLF")) => "crlf"
    Some(@json.String(text)) => text
    _ => return Err(ContentInvalidOption("line_ending"))
  }
  if !["lf", "crlf"].contains(line_ending) {
    return Err(ContentInvalidOption("line_ending"))
  }
  let checked_fields = []
  let columns = []
  let seen : Map[Int, Unit] = Map([])
  for name in fields {
    if name.length() > limits.max_name_bytes ||
      @scalar.admit_utf8_length(name, limits.max_name_bytes) is Err(_) {
      return Err(ContentInvalidFields)
    }
    // The schema's ordinary reference-name rules decide resolution. Presence
    // comes from the declaration, never from a sampled row or nullable flag.
    let mut found : Int? = None
    for column in 0..<@schema.field_count(schema) {
      if work >= limits.max_work {
        return Err(ContentInvalidLimits)
      }
      work += 1
      if @schema.field_reference_name_at(schema, column) == Some(name) {
        found = Some(column)
        break
      }
    }
    guard found is Some(column) && !seen.contains(column) else {
      return Err(ContentInvalidFields)
    }
    let field = @schema.field_at(schema, column).unwrap()
    if format == ContentCsv && field.presence != @schema.Required {
      return Err(ContentConditionalCsv(name))
    }
    seen[column] = ()
    checked_fields.push(field)
    columns.push(column)
  }
  Ok({
    format,
    name,
    fields: checked_fields,
    columns,
    header,
    delimiter,
    null_marker: marker,
    bom: encoding == "utf-8-bom",
    line_ending: if line_ending == "lf" {
      "\n"
    } else {
      "\r\n"
    },
    work,
  })
}

///|
/// Bounded profile preparation work, charged by the consuming checker.
pub fn content_serialization_profile_work(
  profile : ContentSerializationProfile,
) -> Int {
  profile.work
}

///|
pub fn content_serialization_name(
  profile : ContentSerializationProfile,
) -> String {
  profile.name
}

///|
pub fn content_serialization_media_type(
  profile : ContentSerializationProfile,
) -> String {
  if profile.format == ContentCsv {
    "text/csv"
  } else {
    "application/x-ndjson"
  }
}

///|
/// Emit the admitted byte options, including resolved common defaults. The
/// enclosing barrier supplies its checked order and finite physical ceilings.
/// Author JSON is not reparsed to guess which defaults the encoder will use.
pub fn emit_content_serialization_options(
  profile : ContentSerializationProfile,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "encoding")
  @encode.string_value(writer, if profile.bom { "utf-8-bom" } else { "utf-8" })
  @encode.key(writer, "fields")
  @encode.begin_array(writer)
  for field in profile.fields {
    @encode.string_value(writer, @schema.reference_name(field.name))
  }
  @encode.end_array(writer)
  @encode.key(writer, "format")
  @encode.string_value(
    writer,
    if profile.format == ContentCsv {
      "csv"
    } else {
      "jsonl"
    },
  )
  if profile.format == ContentCsv {
    @encode.key(writer, "field_delimiter")
    @encode.string_value(writer, profile.delimiter)
    @encode.key(writer, "header")
    @encode.bool_value(writer, profile.header)
    @encode.key(writer, "null_marker")
    @encode.string_value(writer, profile.null_marker)
  }
  @encode.key(writer, "line_ending")
  @encode.string_value(
    writer,
    if profile.line_ending == "\n" {
      "lf"
    } else {
      "crlf"
    },
  )
  @encode.key(writer, "name")
  @encode.string_value(writer, profile.name)
}
