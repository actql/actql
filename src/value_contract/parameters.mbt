///|
/// Parameter-only constraints; these do not extend general value contracts.
pub enum ParameterRule {
  Plain
  Numeric(integer~ : Bool, minimum~ : Double?, maximum~ : Double?)
  Duration
  Items(ParameterType, length~ : Int64?)
  Properties(ParameterFields)
}

///|
pub struct ParameterType {
  contract : Contract
  rule : ParameterRule
}

///|
struct ParameterFields {
  values : Array[(String, ParameterType)]
}

///|
pub fn parameter_fields(
  fields : ParameterFields,
) -> Array[(String, ParameterType)] {
  fields.values.copy()
}

///|
/// Read-only access in canonical field order without copying the field array.
pub fn parameter_field_at(
  fields : ParameterFields,
  index : Int,
) -> (String, ParameterType)? {
  fields.values.get(index)
}

///|
/// Type syntax only. Defaults and metadata are retained for the binding boundary
/// to validate; this is not an admitted set of parameter declarations.
pub struct ParameterSyntax {
  parameter_type : ParameterType
  default_value : @decode.Cursor?
  metadata : @decode.Cursor?
}

///|
priv enum ParameterWork {
  ReadParameter(@decode.Cursor, Int)
  ParameterArray(Bool, Int64?, Int64?)
  ParameterObject(Bool, Array[String])
}

///|
fn parameter_bound(
  view : @decode.ObjectView,
  key : String,
) -> Double? raise Abort {
  match @decode.lookup(view, key) {
    None => None
    Some(cursor) => {
      let value = decoded(@decode.finite_number(cursor))
      if value == 0.0 && 1.0 / value < 0.0 {
        invalid(cursor, InvalidRange)
      }
      Some(value)
    }
  }
}

///|
fn parameter_decode(
  root : @decode.Cursor,
  limits : Limits,
) -> ParameterSyntax raise Abort {
  let budget : Budget = {
    nodes: limits.max_nodes,
    scheduled: 1,
    text: limits.max_text_bytes,
    max_depth: limits.max_depth,
  }
  let work : Array[ParameterWork] = [ReadParameter(root, 0)]
  let values : Array[ParameterType] = []
  let mut default_value = None
  let mut metadata = None
  while !work.is_empty() {
    match work.pop().unwrap() {
      ParameterArray(nullable, max_items, length) => {
        let child = values.pop().unwrap()
        values.push({
          contract: { nullable, shape: Array(child.contract, max_items~), },
          rule: Items(child, length~),
        })
      }
      ParameterObject(nullable, names) => {
        let entries : Array[(String, ParameterType)] = []
        for index = names.length() - 1; index >= 0; index = index - 1 {
          entries.push((names[index], values.pop().unwrap()))
        }
        entries.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
        let fields = entries.map(e => { name: e.0, contract: e.1.contract, })
        values.push({
          contract: { nullable, shape: Object({ values: fields, }), },
          rule: Properties({ values: entries, }),
        })
      }
      ReadParameter(cursor, depth) => {
        budget.scheduled -= 1
        if budget.nodes == 0 || depth > budget.max_depth {
          invalid(cursor, BudgetExceeded)
        }
        budget.nodes -= 1
        let initial = decoded(@decode.open_object(cursor))
        let type_cursor = required(initial, "type")
        let kind = text(type_cursor, budget)
        let extras = match kind {
          "number" => ["integer", "minimum", "maximum"]
          "string" => ["format"]
          "boolean" | "date" | "timestamp" => []
          "decimal" => ["precision", "scale"]
          "array" => ["items", "length", "max_items"]
          "object" => ["fields"]
          _ => invalid(type_cursor, UnknownType(kind))
        }
        let allowed = ["type", "nullable"]
        for key in extras {
          allowed.push(key)
        }
        if depth == 0 {
          allowed.push("default")
          allowed.push("meta")
        }
        let view = decoded(@decode.closed_object(cursor, allowed))
        if depth == 0 {
          default_value = @decode.lookup(view, "default")
          metadata = @decode.lookup(view, "meta")
        }
        let nullable = match @decode.lookup(view, "nullable") {
          None => false
          Some(c) => decoded(@decode.boolean(c))
        }
        let mut rule = Plain
        let shape = match kind {
          "number" => {
            let integer = match @decode.lookup(view, "integer") {
              None => false
              Some(c) => decoded(@decode.boolean(c))
            }
            rule = Numeric(
              integer~,
              minimum=parameter_bound(view, "minimum"),
              maximum=parameter_bound(view, "maximum"),
            )
            Number
          }
          "string" => {
            if @decode.lookup(view, "format") is Some(c) {
              if text(c, budget) != "duration" {
                invalid(c, InvalidFixedField)
              }
              rule = Duration
            }
            Text({
              min_length: None,
              max_codepoints: None,
              max_utf8_bytes: None,
            })
          }
          "boolean" => Boolean
          "date" => Date
          "timestamp" => Timestamp
          "decimal" => {
            let p = required(view, "precision")
            let s = required(view, "scale")
            let precision = decoded(@decode.safe_integer(p))
            let scale = decoded(@decode.safe_integer(s))
            if precision < 1L || precision > 38L {
              invalid(p, InvalidRange)
            }
            if scale < 0L || scale > precision {
              invalid(s, InvalidRange)
            }
            Decimal(precision=precision.to_int(), scale=scale.to_int())
          }
          "array" => {
            let length = bound(view, "length")
            if length == Some(0L) {
              invalid(required(view, "length"), InvalidRange)
            }
            let max_items = bound(view, "max_items")
            let child = required(view, "items")
            if budget.nodes == budget.scheduled || depth == budget.max_depth {
              invalid(child, BudgetExceeded)
            }
            budget.scheduled += 1
            work.push(ParameterArray(nullable, max_items, length))
            work.push(ReadParameter(child, depth + 1))
            continue
          }
          "object" => {
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
            budget.scheduled += names.length()
            work.push(ParameterObject(nullable, names))
            for index = names.length() - 1; index >= 0; index = index - 1 {
              work.push(
                ReadParameter(required(children, names[index]), depth + 1),
              )
            }
            continue
          }
          _ => invalid(type_cursor, UnknownType(kind))
        }
        values.push({ contract: { nullable, shape, }, rule, })
      }
    }
  }
  { parameter_type: values.pop().unwrap(), default_value, metadata, }
}

///|
/// Read recursive Parameter type syntax while preserving default/meta cursors.
pub fn read_parameter_syntax(
  cursor : @decode.Cursor,
  limits : Limits,
) -> Result[ParameterSyntax, AdmissionError] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  Ok(parameter_decode(cursor, limits)) catch {
    Abort(error) => Err(error)
  }
}
