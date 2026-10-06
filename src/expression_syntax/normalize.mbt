///|
fn finish(
  value : Node,
  role : Role,
  cursor : @decode.Cursor,
  origin : Origin,
  budget : Budget,
) -> Node raise Stop {
  match role {
    Expr | InRight => {
      let fields = match value.value {
        @map.Object(fields) => fields
        _ => invalid(cursor, origin, InvalidExpression)
      }
      let tag = fields[0].key
      let body = fields[0].value
      if tag == "typed_literal" {
        guard part(body, "type") is Some({ value: @map.String("json"), .. }) &&
          part(body, "value") is Some({ value: @map.String(_), .. }) else {
          invalid(cursor, origin, InvalidArguments)
        }
      }
      if tag == "field" || tag == "template" {
        let name = match body.value {
          @map.String(name) => name
          _ => invalid(cursor, origin, InvalidArguments)
        }
        if tag == "template" {
          template(name, cursor, origin)
          let chars = name.to_array()
          let mut i = 0
          while i < chars.length() {
            if i + 1 < chars.length() &&
              (chars[i] == '{' || chars[i] == '}') &&
              chars[i] == chars[i + 1] {
              i += 2
            } else if chars[i] == '{' {
              i += 1
              let field : Array[Char] = []
              while chars[i] != '}' {
                field.push(chars[i])
                i += 1
              }
              i += 1
              let field = String::from_array(field)
              if field.has_prefix("left.") || field.has_prefix("right.") {
                record_relation(field, cursor, origin, budget)
              } else {
                record_field(field, cursor, origin, budget)
              }
            } else {
              i += 1
            }
          }
        } else {
          canonical(name, cursor, origin)
          // Quotation suppresses lexical qualifier recognition, not this
          // whole-field alias normalization shared by text and structured input.
          if name.has_prefix("left.") || name.has_prefix("right.") {
            let parts = name.split(".").to_array()
            let available = budget.nodes - budget.scheduled
            if available < 4 || parts.length() - 2 > (available - 4) / 3 {
              invalid(cursor, origin, BudgetExceeded)
            }
            budget.nodes -= 4 + 3 * (parts.length() - 2)
            for i = 1; i < parts.length(); i = i + 1 {
              if !field_name(parts[i].to_owned()) {
                invalid(cursor, origin, InvalidName(name))
              }
            }
            let mut result = form(
              "join_field",
              named(
                [
                  (
                    "side",
                    node(@map.String(parts[0].to_owned()), cursor, origin),
                  ),
                  (
                    "name",
                    node(@map.String(parts[1].to_owned()), cursor, origin),
                  ),
                ],
                cursor,
                origin,
              ),
              cursor,
              origin,
            )
            record_relation(
              parts[0].to_owned() + "." + parts[1].to_owned(),
              cursor,
              origin,
              budget,
            )
            for i = 2; i < parts.length(); i = i + 1 {
              result = form(
                "property",
                named(
                  [
                    ("value", result),
                    (
                      "name",
                      node(@map.String(parts[i].to_owned()), cursor, origin),
                    ),
                  ],
                  cursor,
                  origin,
                ),
                cursor,
                origin,
              )
            }
            return result
          }
          if !field_name(name) {
            invalid(cursor, origin, InvalidName(name))
          }
          record_field(name, cursor, origin, budget)
        }
      }
      if ["to_number", "to_string", "to_boolean", "to_timestamp", "to_decimal"].contains(
          tag,
        ) {
        let target_fields = [
          (
            "type",
            node(
              @map.String(
                match tag {
                  "to_number" => "number"
                  "to_string" => "string"
                  "to_boolean" => "boolean"
                  "to_timestamp" => "timestamp"
                  _ => "decimal"
                },
              ),
              cursor,
              origin,
            ),
          ),
        ]
        let input = if tag == "to_decimal" {
          target_fields.push(("precision", part(body, "precision").unwrap()))
          target_fields.push(("scale", part(body, "scale").unwrap()))
          part(body, "value").unwrap()
        } else {
          body
        }
        if budget.nodes - budget.scheduled < 4 {
          invalid(cursor, origin, BudgetExceeded)
        }
        budget.nodes -= 4
        return form(
          "cast",
          named(
            [("value", input), ("target", named(target_fields, cursor, origin))],
            cursor,
            origin,
          ),
          cursor,
          origin,
        )
      }
    }
    Arguments(tag) => {
      let args = match value.value {
        @map.Array(args) => args
        _ => invalid(cursor, origin, InvalidArguments)
      }
      if ["eq", "neq", "lt", "lte", "gt", "gte"].contains(tag) {
        for arg in args {
          if literal(arg) is Some({ value: @map.Null, .. }) {
            invalid(cursor, origin, InvalidArguments)
          }
        }
      }
      if tag == "like" && !literal_or_param(args[1]) {
        invalid(cursor, origin, InvalidArguments)
      }
      if tag == "date_trunc" || tag == "date_add" || tag == "date_diff" {
        let index = if tag == "date_trunc" { 0 } else { 2 }
        if !(literal(args[index])
          is Some({ value: @map.String("ms" | "s" | "m" | "h" | "d"), .. })) {
          invalid(cursor, origin, InvalidArguments)
        }
      }
    }
    Body(tag) => {
      if ["to_decimal", "try_decimal", "quantize", "decimal_divide"].contains(
          tag,
        ) {
        decimal_fields(value, cursor, origin)
      }
      if tag == "quantize" || tag == "decimal_divide" {
        if !(part(value, "rounding")
          is Some(
            {
              value: @map.String(
                "half_even"
                | "half_up"
                | "toward_zero"
                | "floor"
                | "ceiling"
              ),
              ..
            }
          )) {
          invalid(cursor, origin, InvalidArguments)
        }
      }
      if tag == "join_field" {
        if !(part(value, "side")
          is Some({ value: @map.String("left" | "right"), .. })) {
          invalid(cursor, origin, InvalidArguments)
        }
      }
      if tag == "join_field" || tag == "property" {
        match part(value, "name") {
          Some({ value: @map.String(name), .. }) => {
            canonical(name, cursor, origin)
            if !field_name(name) {
              invalid(cursor, origin, InvalidName(name))
            }
          }
          _ => invalid(cursor, origin, InvalidArguments)
        }
      }
      if tag == "join_field" {
        let side = match part(value, "side").unwrap().value {
          @map.String(s) => s
          _ => invalid(cursor, origin, InvalidArguments)
        }
        let name = match part(value, "name").unwrap().value {
          @map.String(s) => s
          _ => invalid(cursor, origin, InvalidArguments)
        }
        record_relation(side + "." + name, cursor, origin, budget)
      }
      if tag == "split_part" &&
        !literal_or_param(part(value, "delimiter").unwrap()) {
        invalid(cursor, origin, InvalidArguments)
      }
      if [
          "parse_timestamp", "try_timestamp", "format_timestamp", "regex_match",
          "regex_extract", "regex_replace",
        ].contains(tag) {
        if !literal_or_param(part(value, "pattern").unwrap()) {
          invalid(cursor, origin, InvalidArguments)
        }
        if part(value, "flags") is Some(flags) &&
          !(flags.value is @map.String(_)) {
          invalid(cursor, origin, InvalidArguments)
        }
      }
      if tag == "vector_score" &&
        !(part(value, "metric")
        is Some({ value: @map.String("cosine" | "dot" | "l2"), .. })) {
        invalid(cursor, origin, InvalidArguments)
      }
    }
    CastTarget =>
      if part(value, "type") is Some({ value: @map.String("decimal"), .. }) {
        decimal_fields(value, cursor, origin)
      }
    _ => ()
  }
  value
}

///|
fn record_field(
  name : String,
  cursor : @decode.Cursor,
  origin : Origin,
  budget : Budget,
) -> Unit {
  if origin is Authored {
    budget.field_indices.push(budget.relation_references.length())
    record_relation(name, cursor, origin, budget)
  }
}

///|
fn record_relation(
  name : String,
  cursor : @decode.Cursor,
  origin : Origin,
  budget : Budget,
) -> Unit {
  if origin is Authored {
    budget.relation_references.push({
      name,
      location: location(cursor, origin),
    })
  }
}
