///|
// Presentation of the original CheckOutcome only. No recheck, Run or authority
// is created, and no undisclosed input values are added to its public Reasons.
priv struct LocalCheckText {
  body : StringBuilder
  mut remaining : Int
}

///|
fn LocalCheckText::append(
  self : LocalCheckText,
  value : String,
) -> Unit raise ClientStop {
  let bytes = @utf8.encode(value).length()
  if bytes > self.remaining {
    stop("LocalCheckDisplayLimit")
  }
  self.remaining -= bytes
  self.body.write_string(value)
}

///|
fn local_check_field(value : Json, name : String) -> Json raise ClientStop {
  guard value is Object(fields) && fields.get(name) is Some(field) else {
    stop("LocalCheckDisplayUnavailable")
  }
  field
}

///|
fn local_check_text(value : Json) -> String raise ClientStop {
  guard value is String(text) else { stop("LocalCheckDisplayUnavailable") }
  text
}

///|
fn local_check_items(value : Json) -> Array[Json] raise ClientStop {
  guard value is Array(items) else { stop("LocalCheckDisplayUnavailable") }
  items
}

///|
fn local_check_location(
  value : Json,
  source : String,
) -> String raise ClientStop {
  let document = local_check_text(local_check_field(value, "document_id"))
  if local_check_field(value, "kind") == Json::string("structured") {
    return document +
      " pointer " +
      local_explain_literal(local_check_field(value, "pointer"))
  }
  let start = local_check_field(value, "start_byte")
  let end = local_check_field(value, "end_byte")
  guard start is Number(offset, ..) else {
    stop("LocalCheckDisplayUnavailable")
  }
  let bytes = @utf8.encode(source)
  guard offset >= 0 && offset <= bytes.length().to_double() else {
    stop("LocalCheckDisplayUnavailable")
  }
  let mut line = 1
  let mut column = 1
  for index = 0; index < offset.to_int(); index = index + 1 {
    if bytes[index] == b'\r' {
      line += 1
      column = 1
    } else if bytes[index] == b'\n' {
      if index == 0 || bytes[index - 1] != b'\r' {
        line += 1
      }
      column = 1
    } else {
      column += 1
    }
  }
  document +
  ": line " +
  line.to_string() +
  ", byte " +
  column.to_string() +
  " (" +
  local_check_text(local_check_field(value, "precision")) +
  "; bytes " +
  local_explain_literal(start) +
  ".." +
  local_explain_literal(end) +
  ")"
}

///|
fn local_check_reason(
  output : LocalCheckText,
  reason : Json,
  source : String,
) -> Unit raise ClientStop {
  let code = local_check_text(local_check_field(reason, "code"))
  guard reason is Object(fields) else { stop("LocalCheckDisplayUnavailable") }
  let facts = match fields.get("facts") {
    Some(Object(facts)) => facts
    _ => Map([])
  }
  output.append("  - " + code)
  if local_check_reason_presentation(code, facts) is Some((summary, advice)) {
    output.append(": " + summary + "\n    " + advice)
  }
  output.append("\n")
  if fields.get("location") is Some(location) {
    output.append("    At " + local_check_location(location, source) + "\n")
  }
  let keys = facts.keys().to_array()
  keys.sort()
  for key in keys {
    output.append(
      "    " +
      key.replace(old="_", new=" ") +
      ": " +
      local_explain_literal(facts[key]) +
      "\n",
    )
  }
  if fields.get("fixes") is Some(Array(fixes)) && fixes.length() > 0 {
    output.append(
      "    Suggested edits need review; inspect them with --json.\n",
    )
  }
}

///|
fn local_check_reasons(
  output : LocalCheckText,
  title : String,
  reasons : Json,
  source : String,
) -> Unit raise ClientStop {
  let items = local_check_items(reasons)
  if items.is_empty() {
    return
  }
  output.append("\n" + title + " (" + items.length().to_string() + "):\n")
  for reason in items {
    local_check_reason(output, reason, source)
  }
}

///|
fn local_check_report_text(
  output : LocalCheckText,
  report : Json,
  source : String,
) -> Unit raise ClientStop {
  let verdict = match local_check_text(local_check_field(report, "verdict")) {
    "verified" => "Valid"
    "invalid" => "Invalid"
    "undetermined" => "Undetermined (not verified)"
    _ => stop("LocalCheckDisplayUnavailable")
  }
  let runnable = local_check_field(report, "runnable")
  output.append(
    "Validation: " +
    verdict +
    "\nRunnable: " +
    local_check_text(local_check_field(runnable, "verdict")) +
    "\n",
  )
  let scope = match
    local_check_text(
      local_check_field(local_check_field(report, "scope"), "kind"),
    ) {
    "bound_input" => "bound input"
    "template_only" => "template only"
    _ => stop("LocalCheckDisplayUnavailable")
  }
  output.append("Scope: " + scope + "\n")
  local_check_reasons(
    output,
    "Problems",
    local_check_field(report, "reasons"),
    source,
  )
  local_check_reasons(
    output,
    "Requirements",
    local_check_field(report, "requirements"),
    source,
  )
  local_check_reasons(
    output,
    "Not runnable",
    local_check_field(runnable, "reasons"),
    source,
  )
  let coverage = local_check_field(report, "coverage")
  local_check_reasons(
    output,
    "Analysis limits",
    local_check_field(coverage, "limits"),
    source,
  )
  let unresolved = local_check_items(local_check_field(coverage, "unresolved"))
  if !unresolved.is_empty() {
    output.append("\nUnresolved checks:\n")
    for item in unresolved {
      output.append(
        "  - " +
        local_check_text(local_check_field(item, "boundary")) +
        ": " +
        local_check_text(local_check_field(item, "reason")) +
        "\n",
      )
    }
  }
  guard report is Object(fields) else { stop("LocalCheckDisplayUnavailable") }
  if fields.get("omissions") is Some(_) {
    output.append("\nSome requirements were omitted from this report.\n")
  }
}

///|
fn local_check_reply(
  wire : String,
  json : Bool,
  source : String,
  max_bytes? : Int = 65536,
) -> String raise ClientStop {
  // Preserve exact machine output, including all identities and locations.
  if json {
    return wire
  }
  // The original bounded reader rejects duplicate keys and malformed input;
  // the generated closed schema checks the same public contract as the wire.
  ignore(local_input_cursor(wire))
  let value = @json.parse(wire) catch {
    _ => stop("LocalCheckDisplayUnavailable")
  }
  if !wire_check_outcome_shape(value) {
    stop("LocalCheckDisplayUnavailable")
  }
  let output = { body: StringBuilder(), remaining: max_bytes, }
  output.append("ActQL CHECK\n")
  match local_check_text(local_check_field(value, "outcome")) {
    "completed" =>
      local_check_report_text(
        output,
        local_check_field(value, "report"),
        source,
      )
    "failed" | "unavailable" as outcome => {
      output.append("Check: " + outcome + " (no complete validation verdict)\n")
      local_check_reason(output, local_check_field(value, "problem"), source)
      guard value is Object(fields) else {
        stop("LocalCheckDisplayUnavailable")
      }
      if fields.get("partial_report") is Some(report) {
        output.append("\nPartial report only:\n")
        local_check_report_text(output, report, source)
      }
    }
    _ => stop("LocalCheckDisplayUnavailable")
  }
  output.append(
    "\nNo Run started; no provider calls. Runnable is a check result, not execution permission.\nUse --json for the complete machine-readable report.\n",
  )
  output.body.to_string()
}
