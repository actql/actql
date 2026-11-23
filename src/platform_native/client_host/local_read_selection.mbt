///|
// Finite operator-selected disclosure settings only. Admission does not issue a
// grant, change Result classification, authorize an Account tuple or open data.
struct NativeLocalReadSelection {
  enabled : Bool
  principal : String
  connection : String
  result_names : Array[String]
  formats : Array[String]
  purpose : String
  sink : NativeLocalReadSink
  policy : NativeLocalReadPolicySelection
  max_bytes : Int
  max_uses : Int
  expiry : NativeLocalReadExpiry
}

///|
// Template DATA cannot reach the finite reader. It is narrowed only against
// the SAME authenticated committed Run/Result by the binding constructor.
struct NativeLocalReadPurpose {
  enabled : Bool
  principal : String
  connection : String
  names : NativeLocalReadNamePurpose
  formats : Array[String]
  purpose : String
  sink : NativeLocalReadSink
  policy : NativeLocalReadPolicySelection
  max_bytes : Int
  max_uses : Int
  expiry : NativeLocalReadExpiry
}

///|
priv enum NativeLocalReadNamePurpose {
  FiniteResultNames(Array[String])
  RequestedOriginalResult
  RequestedOriginalResultWithAuthority
}

///|
fn NativeLocalReadPurpose::finite_selection(
  self : NativeLocalReadPurpose,
  names : Array[String],
) -> NativeLocalReadSelection {
  {
    enabled: self.enabled,
    principal: self.principal,
    connection: self.connection,
    result_names: names,
    formats: self.formats,
    purpose: self.purpose,
    sink: self.sink,
    policy: self.policy,
    max_bytes: self.max_bytes,
    max_uses: self.max_uses,
    expiry: self.expiry,
  }
}

///|
/// Syntax only, never a grant or a payload read. The returned purpose may
/// still require original-name narrowing before a finite selection exists.
pub fn NativeLocalReadPurpose::enabled(self : NativeLocalReadPurpose) -> Bool {
  self.enabled
}

///|
// Exactly one explicit selection. The Run alternative selects only the actual
// committed Result root, not every dependency in its retained Policy closure.
priv enum NativeLocalReadPolicySelection {
  ExplicitPolicyCids(Array[String])
  AcceptedRunPolicy
}

///|
/// An original destination choice only. Material still requires the actual
/// same-Host receiver and funded workspace before any read or allocation.
pub(all) enum NativeLocalReadSink {
  Stdout
  Material
  File
} derive(Eq, Debug)

///|
priv enum NativeLocalReadExpiry {
  Absolute(String)
  AcceptedRunProfile(NativeLocalReadRunRoles)
}

///|
// Literal selectors for the original adopted files, never authorization.
priv struct NativeLocalReadRunRoles {
  profile_cid : String
  run_file : String
  retention_file : String
  store_file : String
}

///|
pub(all) enum NativeLocalReadPolicyIssue {
  InvalidOriginal
  InvalidLimits
  UnsupportedSink
  UnsupportedFormat
  InvalidPolicyReference
} derive(Eq, Debug)

///|
priv suberror LocalReadPolicyStop {
  LocalReadPolicyStop(NativeLocalReadPolicyIssue)
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
fn read_policy_configuration_name(
  fields : @decode.ObjectView,
  key : String,
) -> String raise LocalReadPolicyStop {
  let name = read_policy_text(fields, key, 128)
  if !local_adoption_name(name) {
    raise LocalReadPolicyStop(InvalidOriginal)
  }
  name
}

///|
pub fn admit_native_local_read_purpose(
  text : String,
) -> Result[NativeLocalReadPurpose, NativeLocalReadPolicyIssue] {
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
        "enabled", "principal", "connection", "result_names", "result_selection",
        "formats", "purpose", "sink", "data_policy_cids", "accepted_run_policy",
        "max_bytes", "max_uses", "expires_at", "run_policy_profile_cid", "run_file",
        "retention_file", "store_file",
      ]),
    )
    let enabled = read_policy_decoded(
      @decode.boolean(read_policy_field(fields, "enabled")),
    )
    let sink = match read_policy_text(fields, "sink", 16) {
      "stdout" => Stdout
      "material" => Material
      "file" => File
      _ => return Err(UnsupportedSink)
    }
    let formats = read_policy_list(fields, "formats", 3, 8)
    for format in formats {
      if format != "json" && format != "jsonl" && format != "csv" {
        return Err(UnsupportedFormat)
      }
    }
    let expiry = match
      (
        @decode.lookup(fields, "expires_at"),
        @decode.lookup(fields, "run_policy_profile_cid"),
        @decode.lookup(fields, "run_file"),
        @decode.lookup(fields, "retention_file"),
        @decode.lookup(fields, "store_file"),
      ) {
      (Some(_), None, None, None, None) => {
        let expires_at = read_policy_text(fields, "expires_at", 24)
        if !read_policy_timestamp(expires_at) {
          return Err(InvalidOriginal)
        }
        Absolute(expires_at)
      }
      (None, Some(_), Some(_), Some(_), Some(_)) => {
        let cid = read_policy_text(fields, "run_policy_profile_cid", 71)
        if !read_policy_cid(cid) {
          return Err(InvalidPolicyReference)
        }
        AcceptedRunProfile({
          profile_cid: cid,
          run_file: read_policy_configuration_name(fields, "run_file"),
          retention_file: read_policy_configuration_name(
            fields, "retention_file",
          ),
          store_file: read_policy_configuration_name(fields, "store_file"),
        })
      }
      _ => return Err(InvalidOriginal)
    }
    let policy = match
      (
        @decode.lookup(fields, "data_policy_cids"),
        @decode.lookup(fields, "accepted_run_policy"),
      ) {
      (Some(_), None) => {
        let cids = read_policy_list(fields, "data_policy_cids", 16, 71)
        for cid in cids {
          if !read_policy_cid(cid) {
            return Err(InvalidPolicyReference)
          }
        }
        ExplicitPolicyCids(cids)
      }
      (None, Some(value)) if expiry is AcceptedRunProfile(_) => {
        if !read_policy_decoded(@decode.boolean(value)) {
          return Err(InvalidOriginal)
        }
        AcceptedRunPolicy
      }
      _ => return Err(InvalidOriginal)
    }
    let names = match
      (
        @decode.lookup(fields, "result_names"),
        @decode.lookup(fields, "result_selection"),
      ) {
      (Some(_), None) =>
        FiniteResultNames(read_policy_list(fields, "result_names", 16, 128))
      (None, Some(value)) => {
        let selected = read_policy_decoded(
          @decode.closed_object(value, ["authority", "kind"]),
        )
        if read_policy_text(selected, "kind", 32) != "requested_original_result" {
          return Err(InvalidOriginal)
        }
        if !(expiry is AcceptedRunProfile(_)) {
          return Err(InvalidOriginal)
        }
        match @decode.lookup(selected, "authority") {
          None => RequestedOriginalResult
          Some(_) if read_policy_text(selected, "authority", 32) ==
            "original_result_read" => RequestedOriginalResultWithAuthority
          Some(_) => return Err(InvalidOriginal)
        }
      }
      _ => return Err(InvalidOriginal)
    }
    Ok({
      enabled,
      principal: read_policy_text(fields, "principal", 512),
      connection: read_policy_text(fields, "connection", 512),
      names,
      formats,
      purpose: read_policy_text(fields, "purpose", 256),
      sink,
      policy,
      max_bytes: read_policy_quantity(fields, "max_bytes", 536870912L),
      max_uses: read_policy_quantity(fields, "max_uses", 1024L),
      expiry,
    })
  } catch {
    LocalReadPolicyStop(issue) => Err(issue)
  }
}

///|
/// Read-only destination DATA, never a receiver, read permit or workspace loan.
pub fn NativeLocalReadSelection::sink(
  self : NativeLocalReadSelection,
) -> NativeLocalReadSink {
  self.sink
}

///|
/// Syntax admission only; this is not an adopted configuration or read permit.
pub fn NativeLocalReadSelection::enabled(
  self : NativeLocalReadSelection,
) -> Bool {
  self.enabled
}

///|
/// Legacy finite-only API. A requested-original template is intentionally not
/// representable as a NativeLocalReadSelection, even when syntax is valid.
pub fn admit_native_local_read_selection(
  text : String,
) -> Result[NativeLocalReadSelection, NativeLocalReadPolicyIssue] {
  match admit_native_local_read_purpose(text) {
    Err(issue) => Err(issue)
    Ok(purpose) =>
      match purpose.names {
        FiniteResultNames(names) => Ok(purpose.finite_selection(names))
        RequestedOriginalResult | RequestedOriginalResultWithAuthority =>
          Err(InvalidOriginal)
      }
  }
}

///|
fn NativeLocalReadPurpose::narrow_original(
  self : NativeLocalReadPurpose,
  name : String,
  original_exists : () -> Bool,
  prepare : (Int64, Int64) -> Bool,
) -> Result[NativeLocalReadSelection, NativeLocalReadBindingIssue] {
  if name.is_empty() || name.length() > 128 || name.contains("\u{0000}") {
    return Err(SelectionMismatch)
  }
  // Finite selection record1H7R4W + pinned one-name wrapper/backing2H2R2W
  // + returned Ok1H1R1W =4H10R7W. No growth or String copy occurs.
  // Use the existing pinned collection owner, not a raw-array assumption.
  guard @shape.reference_array_retained_extent(1L, 1L) is Some(array) &&
    @execution.preparation_representation_cost({
      record_headers: 2L + array.record_headers,
      reference_slots: 8L + array.reference_slots,
      scalar_words: 5L + array.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(cost) &&
    prepare(cost, cost) else {
    return Err(Adoption(OriginalResourceScopePending))
  }
  match self.names {
    FiniteResultNames(names) => {
      if !names.contains(name) || !original_exists() {
        return Err(SelectionMismatch)
      }
      // Even an old finite list is narrowed, never widened to another name.
      Ok(self.finite_selection([name]))
    }
    RequestedOriginalResult | RequestedOriginalResultWithAuthority => {
      if !original_exists() {
        return Err(SelectionMismatch)
      }
      Ok(self.finite_selection([name]))
    }
  }
}
