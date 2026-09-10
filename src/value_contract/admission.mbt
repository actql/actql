///|
priv struct Budget {
  mut nodes : Int
  mut scheduled : Int
  mut text : Int
  max_depth : Int
}

///|
fn[T] invalid(cursor : @decode.Cursor, issue : ContractIssue) -> T raise Abort {
  raise Abort(
    ContractIssue(
      issue,
      path=@decode.cursor_path(cursor),
      span=@decode.cursor_span(cursor),
    ),
  )
}

///|
fn[T] decoded(result : Result[T, @decode.Issue]) -> T raise Abort {
  match result {
    Ok(value) => value
    Err(issue) => raise Abort(Decode(issue))
  }
}

///|
fn required(
  view : @decode.ObjectView,
  name : String,
) -> @decode.Cursor raise Abort {
  decoded(@decode.required(view, name))
}

///|
// Recover the key's own span only on failure; successful field scans stay linear.
fn field_invalid(
  map : @decode.Cursor,
  names : Array[String],
  name : String,
  issue : ContractIssue,
) -> Unit raise Abort {
  match @decode.closed_object(map, names.filter(n => n != name)) {
    Err(location) =>
      raise Abort(ContractIssue(issue, path=location.path, span=location.span))
    Ok(_) => invalid(map, issue)
  }
}

///|
fn charge_text(
  text : String,
  cursor : @decode.Cursor,
  budget : Budget,
) -> Unit raise Abort {
  match @scalar.admit_utf8_length(text, budget.text) {
    Ok(size) => budget.text -= size
    Err(@scalar.MalformedUtf16(_)) => invalid(cursor, InvalidUnicode)
    Err(_) => invalid(cursor, BudgetExceeded)
  }
  match @canonical.normalize_nfc_lf(text) {
    Ok(normalized) =>
      if normalized != text {
        invalid(cursor, NonCanonicalText)
      }
    Err(_) => invalid(cursor, InvalidUnicode)
  }
}

///|
fn text(cursor : @decode.Cursor, budget : Budget) -> String raise Abort {
  let value = decoded(@decode.text(cursor))
  charge_text(value, cursor, budget)
  if value.is_empty() {
    invalid(cursor, InvalidRange)
  }
  value
}

///|
fn bound(view : @decode.ObjectView, name : String) -> Int64? raise Abort {
  match @decode.lookup(view, name) {
    None => None
    Some(cursor) => {
      let value = decoded(@decode.safe_integer(cursor))
      if value < 0L {
        invalid(cursor, InvalidRange)
      }
      Some(value)
    }
  }
}

///|
// ECMAScript whitespace, matching the schema's \S predicate, without trimming names.
fn nonblank(text : String) -> Bool {
  for unit in text {
    let cp = unit.to_int()
    if !(cp >= 0x2000 && cp <= 0x200a) &&
      ![
        9, 10, 11, 12, 13, 32, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
        0xfeff,
      ].contains(cp) {
      return true
    }
  }
  false
}

///|
priv enum Work {
  Read(@decode.Cursor, Int)
  BuildArray(Bool, Int64?)
  BuildObject(Bool, Array[String])
}

///|
fn decode(
  root : @decode.Cursor,
  limits : Limits,
  checked : Bool,
) -> Contract raise Abort {
  let budget : Budget = {
    nodes: limits.max_nodes,
    scheduled: 1,
    text: limits.max_text_bytes,
    max_depth: limits.max_depth,
  }
  let work : Array[Work] = [Read(root, 0)]
  let values : Array[Contract] = []
  while !work.is_empty() {
    match work.pop().unwrap() {
      BuildArray(nullable, max_items) => {
        let child = values.pop().unwrap()
        values.push({ nullable, shape: Array(child, max_items~), })
      }
      BuildObject(nullable, names) => {
        let entries : Array[Field] = []
        for i = names.length() - 1; i >= 0; i = i - 1 {
          entries.push({ name: names[i], contract: values.pop().unwrap(), })
        }
        entries.sort_by((a, b) => @canonical.compare_utf16(a.name, b.name))
        values.push({ nullable, shape: Object({ values: entries, }), })
      }
      Read(cursor, depth) => {
        budget.scheduled -= 1
        if budget.nodes == 0 || depth > budget.max_depth {
          invalid(cursor, BudgetExceeded)
        }
        budget.nodes -= 1
        let initial = decoded(@decode.open_object(cursor))
        let type_cursor = required(initial, "type")
        let kind = text(type_cursor, budget)
        let extras = match kind {
          "string" =>
            if checked {
              ["min_length", "max_codepoints", "max_utf8_bytes"]
            } else {
              []
            }
          "number" | "boolean" | "timestamp" | "date" | "json" => []
          "decimal" => ["precision", "scale"]
          "array" => ["items", "max_items"]
          "object" =>
            if checked {
              ["fields", "additional_properties"]
            } else {
              ["fields"]
            }
          "vector" =>
            if checked {
              ["dimensions", "element_type"]
            } else {
              ["dimensions"]
            }
          "resource_ref" => ["resource_kind"]
          "artifact_ref" => ["media_type"]
          _ => invalid(type_cursor, UnknownType(kind))
        }
        let allowed = ["type", "nullable"]
        for key in extras {
          allowed.push(key)
        }
        let view = decoded(@decode.closed_object(cursor, allowed))
        let nullable = decoded(@decode.boolean(required(view, "nullable")))
        let shape = match kind {
          "string" =>
            Text({
              min_length: bound(view, "min_length"),
              max_codepoints: bound(view, "max_codepoints"),
              max_utf8_bytes: bound(view, "max_utf8_bytes"),
            })
          "number" => Number
          "boolean" => Boolean
          "timestamp" => Timestamp
          "date" => Date
          "json" => Json
          "decimal" => {
            let p = required(view, "precision")
            let precision = decoded(@decode.safe_integer(p))
            if precision < 1L || precision > 38L {
              invalid(p, InvalidRange)
            }
            let s = required(view, "scale")
            let scale = decoded(@decode.safe_integer(s))
            if scale < 0L || scale > precision {
              invalid(s, InvalidRange)
            }
            Decimal(precision=precision.to_int(), scale=scale.to_int())
          }
          "vector" => {
            let d = required(view, "dimensions")
            let dimensions = decoded(@decode.finite_number(d))
            if dimensions < 1.0 ||
              @scalar.read_integer_number(dimensions) is None {
              invalid(d, InvalidRange)
            }
            if checked {
              let e = required(view, "element_type")
              if text(e, budget) != "f32" {
                invalid(e, InvalidFixedField)
              }
            }
            Vector(dimensions~)
          }
          "resource_ref" =>
            ResourceRef(
              resource_kind=text(required(view, "resource_kind"), budget),
            )
          "artifact_ref" =>
            ArtifactRef(
              media_type=match @decode.lookup(view, "media_type") {
                None => None
                Some(c) => Some(text(c, budget))
              },
            )
          "array" => {
            let max_items = bound(view, "max_items")
            let child = required(view, "items")
            if budget.nodes == budget.scheduled || depth == budget.max_depth {
              invalid(child, BudgetExceeded)
            }
            budget.scheduled += 1
            work.push(BuildArray(nullable, max_items))
            work.push(Read(child, depth + 1))
            continue
          }
          "object" => {
            if checked {
              let a = required(view, "additional_properties")
              if decoded(@decode.boolean(a)) {
                invalid(a, InvalidFixedField)
              }
            }
            let f = required(view, "fields")
            let children = decoded(@decode.open_object(f))
            let names = decoded(@decode.object_field_names(f))
            if names.length() > budget.nodes - budget.scheduled ||
              (!names.is_empty() && depth == budget.max_depth) {
              invalid(f, BudgetExceeded)
            }
            for name in names {
              let child = required(children, name)
              charge_text(name, child, budget) catch {
                Abort(ContractIssue(issue, ..)) =>
                  field_invalid(f, names, name, issue)
                error => raise error
              }
              if !nonblank(name) ||
                name.contains(".") ||
                name == "__cid" ||
                name.has_prefix("__actql_") {
                field_invalid(f, names, name, InvalidFieldName(name))
              }
            }
            work.push(BuildObject(nullable, names))
            budget.scheduled += names.length()
            for i = names.length() - 1; i >= 0; i = i - 1 {
              work.push(Read(required(children, names[i]), depth + 1))
            }
            continue
          }
          _ => invalid(type_cursor, UnknownType(kind))
        }
        values.push({ nullable, shape, })
      }
    }
  }
  values.pop().unwrap()
}

///|
fn admit(
  cursor : @decode.Cursor,
  limits : Limits,
  checked : Bool,
) -> Result[Contract, AdmissionError] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  Ok(decode(cursor, limits, checked)) catch {
    Abort(error) => Err(error)
  }
}

///|
/// Reads normalized authored contracts and expands fixed checked-only members.
pub fn read_author(
  cursor : @decode.Cursor,
  limits : Limits,
) -> Result[Contract, AdmissionError] {
  admit(cursor, limits, false)
}

///|
/// Validates checked contract values without repairing noncanonical strings.
/// This is not a canonical JSON byte, signature or issuer-admission boundary.
pub fn read_checked(
  cursor : @decode.Cursor,
  limits : Limits,
) -> Result[Contract, AdmissionError] {
  admit(cursor, limits, true)
}
