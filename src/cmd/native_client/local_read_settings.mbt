///|
// Finite operator-selected disclosure settings only. Admission does not issue a
// grant, change Result classification, authorize an Account tuple or open data.
priv struct LocalReadInstallation {
  enabled : Bool
  principal : String
  connection : String
  result_names : Array[String]
  formats : Array[String]
  purpose : String
  data_policy_cids : Array[String]
  max_bytes : Int
  max_uses : Int
  expires_at : String
}

///|
priv enum LocalReadPolicyIssue {
  InvalidOriginal
  InvalidLimits
  UnsupportedSink
  UnsupportedFormat
  InvalidPolicyReference
}

///|
priv suberror LocalReadPolicyStop {
  LocalReadPolicyStop(LocalReadPolicyIssue)
}

///|
fn[T] read_policy_decoded(
  value : Result[T, @decode.Issue],
) -> T raise LocalReadPolicyStop {
  match value {
    Ok(value) => value
    Err(_) => raise LocalReadPolicyStop(InvalidOriginal)
  }
}

///|
fn read_policy_field(
  object : @decode.ObjectView,
  key : String,
) -> @decode.Cursor raise LocalReadPolicyStop {
  read_policy_decoded(@decode.required(object, key))
}

///|
fn read_policy_text(
  object : @decode.ObjectView,
  key : String,
  maximum : Int,
) -> String raise LocalReadPolicyStop {
  let value = read_policy_decoded(@decode.text(read_policy_field(object, key)))
  if value.is_empty() || value.length() > maximum || value.contains("\u{0000}") {
    raise LocalReadPolicyStop(InvalidOriginal)
  }
  value
}

///|
fn read_policy_list(
  object : @decode.ObjectView,
  key : String,
  count : Int,
  width : Int,
) -> Array[String] raise LocalReadPolicyStop {
  let elements = read_policy_decoded(
    @decode.elements(read_policy_field(object, key)),
  )
  if elements.is_empty() || elements.length() > count {
    raise LocalReadPolicyStop(InvalidLimits)
  }
  let values : Array[String] = []
  for element in elements {
    let value = read_policy_decoded(@decode.text(element))
    // Each selector is literal. There is no wildcard expansion or implicit
    // all-Result grant. Preserve Unicode and line-ending values exactly.
    if value.is_empty() ||
      value.length() > width ||
      value.contains("\u{0000}") ||
      values.contains(value) {
      raise LocalReadPolicyStop(InvalidOriginal)
    }
    values.push(value)
  }
  values
}

///|
fn read_policy_quantity(
  object : @decode.ObjectView,
  key : String,
  maximum : Int64,
) -> Int raise LocalReadPolicyStop {
  let value = read_policy_decoded(
    @decode.safe_integer(read_policy_field(object, key)),
  )
  if value < 1L || value > maximum {
    raise LocalReadPolicyStop(InvalidLimits)
  }
  value.to_int()
}

///|
fn read_policy_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn read_policy_timestamp(value : String) -> Bool {
  // Reuse the canonical UTC timestamp Owner, including real calendar validity.
  // Parsing is not a clock, expiry decision, retention extension or grant.
  @values.timestamp_epoch_milliseconds(value) is Some(_)
}

///|
fn local_read_installation(
  text : String,
) -> Result[LocalReadInstallation, LocalReadPolicyIssue] {
  try {
    let node = match
      @source.parse_json_bytes_preserving(@utf8.encode(text), {
        max_input_bytes: 65536,
        max_nodes: 256,
        max_depth: 8,
      }) {
      Ok(value) => value
      Err(_) => return Err(InvalidOriginal)
    }
    let cursor = read_policy_decoded(
      @decode.admit(node, {
        max_nodes: 256,
        max_depth: 8,
        max_string_bytes: 4096,
        max_total_string_bytes: 16384,
      }),
    )
    let root = read_policy_decoded(
      @decode.closed_object(cursor, ["version", "native"]),
    )
    if read_policy_text(root, "version", 32) != "actql-config/0.1" {
      return Err(InvalidOriginal)
    }
    let native = read_policy_decoded(
      @decode.closed_object(read_policy_field(root, "native"), ["result_read"]),
    )
    let fields = read_policy_decoded(
      @decode.closed_object(read_policy_field(native, "result_read"), [
        "enabled", "principal", "connection", "result_names", "formats", "purpose",
        "sink", "data_policy_cids", "max_bytes", "max_uses", "expires_at",
      ]),
    )
    let enabled = read_policy_decoded(
      @decode.boolean(read_policy_field(fields, "enabled")),
    )
    if read_policy_text(fields, "sink", 16) != "stdout" {
      return Err(UnsupportedSink)
    }
    let formats = read_policy_list(fields, "formats", 3, 8)
    for format in formats {
      if format != "json" && format != "jsonl" && format != "csv" {
        return Err(UnsupportedFormat)
      }
    }
    let data_policy_cids = read_policy_list(fields, "data_policy_cids", 16, 71)
    for identity in data_policy_cids {
      if !read_policy_cid(identity) {
        return Err(InvalidPolicyReference)
      }
    }
    let expires_at = read_policy_text(fields, "expires_at", 24)
    if !read_policy_timestamp(expires_at) {
      return Err(InvalidOriginal)
    }
    Ok({
      enabled,
      principal: read_policy_text(fields, "principal", 512),
      connection: read_policy_text(fields, "connection", 512),
      result_names: read_policy_list(fields, "result_names", 16, 128),
      formats,
      purpose: read_policy_text(fields, "purpose", 256),
      data_policy_cids,
      max_bytes: read_policy_quantity(fields, "max_bytes", 536870912L),
      max_uses: read_policy_quantity(fields, "max_uses", 1024L),
      expires_at,
    })
  } catch {
    LocalReadPolicyStop(issue) => Err(issue)
  }
}

///|
fn local_read_installation_or_stop(
  text : String,
) -> LocalReadInstallation raise ClientStop {
  match local_read_installation(text) {
    Ok(value) => value
    Err(issue) =>
      stop(
        match issue {
          InvalidOriginal => "InvalidLocalReadPolicyOriginal"
          InvalidLimits => "InvalidLocalReadPolicyLimits"
          UnsupportedSink => "UnsupportedLocalReadSink"
          UnsupportedFormat => "UnsupportedLocalReadFormat"
          InvalidPolicyReference => "InvalidLocalReadPolicyReference"
        },
      )
  }
}
