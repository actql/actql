///|
fn type_name(c : @contract.Contract) -> String {
  match c.shape {
    @contract.Text(_) => "string"
    @contract.Number => "number"
    @contract.Boolean => "boolean"
    @contract.Date => "date"
    @contract.Timestamp => "timestamp"
    @contract.Json => "json"
    @contract.Decimal(..) => "decimal"
    @contract.Vector(..) => "vector"
    @contract.Array(_, ..) => "array"
    @contract.Object(_) => "object"
    @contract.ResourceRef(..) => "resource_ref"
    @contract.ArtifactRef(..) => "artifact_ref"
  }
}

///|
fn scalar_kind(name : String) -> @contract.Primitive? {
  match name {
    "string" => Some(StringType)
    "number" => Some(NumberType)
    "boolean" => Some(BooleanType)
    "date" => Some(DateType)
    "timestamp" => Some(TimestampType)
    _ => None
  }
}

///|
fn typed(
  t : Types,
  c : @contract.Contract,
  source : @decode.Cursor,
) -> Int raise Stop {
  import_type(t, c, source)
}

///|
fn require_type(
  t : Types,
  nodes : Array[Node],
  id : Int,
  expected : String,
) -> @contract.Contract raise Stop {
  let node = nodes[id]
  if node.tag == "literal" &&
    @decode.is_null(node.body) &&
    scalar_kind(expected) is Some(kind) {
    let hint = primitive(t, kind, false, node.source)
    provide(t, node.inferred, hint, node.source)
  }
  let c = resolve_type(t, node.inferred, node.source)
  if type_name(c) != expected {
    fail(node.source, TypeMismatch(expected))
  }
  c
}

///|
fn operand(
  t : Types,
  nodes : Array[Node],
  node : Node,
  index : Int,
) -> @contract.Contract raise Stop {
  let child = nodes[node.children[index]]
  resolve_type(t, child.inferred, child.source)
}

///|
fn arguments(
  t : Types,
  nodes : Array[Node],
  node : Node,
  expected : String,
) -> Bool raise Stop {
  let mut nullable = false
  for id in node.children {
    nullable = require_type(t, nodes, id, expected).nullable || nullable
  }
  nullable
}

///|
fn immediate_null(node : Node) -> Bool {
  node.tag == "#null" || (node.tag == "literal" && @decode.is_null(node.body))
}

///|
fn comparable_operands(
  t : Types,
  nodes : Array[Node],
  node : Node,
  ordered : Bool,
) -> Array[@contract.Contract] raise Stop {
  let mut evidence : Int? = None
  for id in node.children {
    if !immediate_null(nodes[id]) {
      ignore(resolve_type(t, nodes[id].inferred, nodes[id].source))
      evidence = Some(nodes[id].inferred)
      break
    }
  }
  let hint = match evidence {
    Some(id) => id
    None => fail(node.source, NullTypeUnresolved)
  }
  let values : Array[@contract.Contract] = []
  for id in node.children {
    let child = nodes[id]
    if immediate_null(child) {
      provide(t, child.inferred, hint, child.source)
    }
    let c = resolve_type(t, child.inferred, child.source)
    if ordered &&
      !["string", "number", "decimal", "boolean", "date", "timestamp"].contains(
        type_name(c),
      ) {
      fail(child.source, TypeMismatch("author-orderable scalar"))
    }
    if !values.is_empty() && !@contract.key_comparable(values[0], c) {
      fail(child.source, TypeMismatch("key-comparable operands"))
    }
    values.push(c)
  }
  values
}

///|
fn decimal_target(node : Node) -> @contract.Contract raise Stop {
  let p = decoded(
    @decode.safe_integer(part(node.body, "precision")),
    node.source,
  ).to_int()
  let s = decoded(@decode.safe_integer(part(node.body, "scale")), node.source).to_int()
  match @contract.decimal_contract(p, s, nullable=false) {
    Some(c) => c
    None => fail(node.source, InvalidStaticOption("decimal precision/scale"))
  }
}

///|
fn cast_target(body : @decode.Cursor) -> @contract.Contract raise Stop {
  let name = string(part(body, "type"))
  if name == "decimal" {
    let p = decoded(@decode.safe_integer(part(body, "precision")), body).to_int()
    let s = decoded(@decode.safe_integer(part(body, "scale")), body).to_int()
    match @contract.decimal_contract(p, s, nullable=false) {
      Some(c) => c
      None => fail(body, InvalidStaticOption("decimal target"))
    }
  } else {
    match scalar_kind(name) {
      Some(kind) => @contract.primitive(kind, nullable=false)
      None => fail(body, InvalidStaticOption("cast target"))
    }
  }
}

///|
fn text_time(tag : String) -> Bool {
  [
    "split_part", "substring", "utf8_truncate", "try_number", "parse_timestamp",
    "try_timestamp", "format_timestamp", "regex_match", "regex_extract", "regex_replace",
    "nfkc", "case_fold",
  ].contains(tag)
}

///|
fn regex_static_argument(tag : String, option : Node) -> Unit raise Stop {
  // Bound values and pattern-dependent checks remain PatternValidation work.
  if option.tag == "$param" {
    return
  }
  let valid = if option.tag == "literal" {
    match @decode.view(option.body) {
      NumberValue(n) =>
        tag == "regex_extract" &&
        n >= 0 &&
        @scalar.read_integer_number(n) is Some(_)
      TextValue(_) => tag == "regex_replace"
      _ => false
    }
  } else {
    false
  }
  if !valid {
    fail(
      option.source,
      InvalidStaticOption(
        if tag == "regex_extract" {
          "regex capture"
        } else {
          "regex replacement"
        },
      ),
    )
  }
}

///|
fn infer(
  t : Types,
  nodes : Array[Node],
  index : Int,
  env : Scopes,
  pending : Array[Obligation],
  profiles : Map[String, Bool],
) -> Int raise Stop {
  let node = nodes[index]
  let source = node.source
  let tag = node.tag
  spend(t.budget, source)
  let values = node.children.map(id => nodes[id].inferred)
  if text_time(tag) {
    if tag == "regex_extract" || tag == "regex_replace" {
      regex_static_argument(tag, nodes[node.children[2]])
    }
    profiles["actql-text-time/0.1"] = true
    pending.push({
      node_index: index,
      kind: ProfileAdmission("actql-text-time/0.1"),
    })
    pending.push({ node_index: index, kind: HostEnvelope, })
    let mut nullable = false
    for i in 0..<node.children.length() {
      let expected = if i == 0 {
        if tag == "format_timestamp" {
          "timestamp"
        } else {
          "string"
        }
      } else if (tag == "split_part" && i == 2) ||
        tag == "substring" ||
        tag == "utf8_truncate" ||
        (tag == "regex_extract" && i == 2) {
        "number"
      } else {
        "string"
      }
      nullable = require_type(t, nodes, node.children[i], expected).nullable ||
        nullable
    }
    if [
        "parse_timestamp", "try_timestamp", "format_timestamp", "regex_match", "regex_extract",
        "regex_replace",
      ].contains(tag) {
      pending.push({ node_index: index, kind: PatternValidation(tag), })
    }
    if tag.has_prefix("regex_") {
      let obj = decoded(@decode.open_object(node.body), source)
      if @decode.lookup(obj, "flags") is Some(flags) {
        let flags = string(flags)
        charge(t.budget, source, flags)
        let mut m = false
        let mut s = false
        for ch in flags {
          if ch == 'm' && !m {
            m = true
          } else if ch == 's' && !s {
            s = true
          } else {
            fail(source, InvalidStaticOption("regex flags"))
          }
        }
      }
    }
    let result = match tag {
      "try_number" => @contract.NumberType
      "parse_timestamp" | "try_timestamp" => TimestampType
      "regex_match" => BooleanType
      _ => StringType
    }
    return primitive(
      t,
      result,
      nullable || ["try_number", "try_timestamp", "regex_extract"].contains(tag),
      source,
    )
  }
  match tag {
    "#null" => put(t, Hole, true, source)
    "literal" =>
      match @decode.view(node.body) {
        NullValue => put(t, Hole, true, source)
        BoolValue(_) => primitive(t, BooleanType, false, source)
        NumberValue(_) => primitive(t, NumberType, false, source)
        TextValue(text) => {
          let bytes = t.budget.text
          charge(t.budget, source, text)
          let size = (bytes - t.budget.text).to_int64()
          typed(
            t,
            @contract.string_contract(nullable=false, max_utf8_bytes=Some(size)).unwrap(),
            source,
          )
        }
        _ => primitive(t, JsonType, false, source)
      }
    "field" | "$param" | "join_field" => {
      let (map, name) = if tag == "field" {
        (env.fields, string(node.body))
      } else if tag == "$param" {
        (env.parameters, string(node.body))
      } else {
        let side = string(part(node.body, "side"))
        let map = if side == "left" { env.left } else { env.right }
        match map {
          Some(map) => (map, string(part(node.body, "name")))
          None => fail(source, MissingJoinScope(side))
        }
      }
      charge(t.budget, source, name)
      match map.get(name) {
        Some(id) => id
        None =>
          fail(
            source,
            if tag == "$param" {
              UnknownParameter(name)
            } else {
              UnknownField(name)
            },
          )
      }
    }
    "template" => {
      let text = string(node.body)
      charge(t.budget, source, text)
      let units = text.to_array()
      let mut i = 0
      let mut nullable = false
      while i < units.length() {
        if (units[i] == '{' || units[i] == '}') &&
          i + 1 < units.length() &&
          units[i] == units[i + 1] {
          i += 2
          continue
        }
        if units[i] != '{' {
          i += 1
          continue
        }
        i += 1
        let name : Array[Char] = []
        while i < units.length() && units[i] != '}' {
          name.push(units[i])
          i += 1
        }
        i += 1
        let name = String::from_array(name)
        spend(t.budget, source)
        let id = match
          (if name.has_prefix("left.") || name.has_prefix("right.") {
            let parts = name.split(".").to_array()
            let scope = if parts[0] == "left" { env.left } else { env.right }
            match scope {
              Some(scope) => scope.get(parts[1].to_owned())
              None => fail(source, MissingJoinScope(parts[0].to_owned()))
            }
          } else {
            env.fields.get(name)
          }) {
          Some(id) => id
          None => fail(source, UnknownField(name))
        }
        let c = resolve_type(t, id, source)
        if !["string", "number", "decimal", "boolean", "date", "timestamp"].contains(
            type_name(c),
          ) {
          fail(source, TypeMismatch("printable template field"))
        }
        nullable = nullable || c.nullable
      }
      primitive(t, StringType, nullable, source)
    }
    "array" | "#in_list" =>
      put(
        t,
        Sequence(peers(t, values, source), Some(values.length().to_int64())),
        false,
        source,
      )
    "empty_array" => {
      let cursor = part(node.body, "items")
      let c = item_contract(t, cursor)
      put(t, Sequence(import_type(t, c, source), Some(0L)), false, source)
    }
    "object" => {
      let fields : Array[(String, Int)] = []
      for i in 0..<values.length() {
        fields.push((node.names[i], values[i]))
      }
      fields.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
      put(t, Product(fields), false, source)
    }
    "if" | "case" | "coalesce" => {
      let branches : Array[Int] = []
      if tag == "if" {
        ignore(require_type(t, nodes, node.children[0], "boolean"))
        branches.push(values[1])
        branches.push(values[2])
      } else if tag == "case" {
        for i = 0; i + 1 < values.length(); i = i + 2 {
          ignore(require_type(t, nodes, node.children[i], "boolean"))
          branches.push(values[i + 1])
        }
        branches.push(values[values.length() - 1])
      } else {
        for value in values {
          branches.push(value)
        }
      }
      let common = peers(t, branches, source)
      if tag == "coalesce" {
        let mut nullable = true
        for value in branches {
          nullable = nullability(t, value, source) && nullable
        }
        refine(t, common, nullable, source)
      } else {
        common
      }
    }
    "cast" => {
      let target = cast_target(part(node.body, "target"))
      let child = nodes[node.children[0]]
      if immediate_null(child) {
        provide(t, child.inferred, typed(t, target, source), source)
      }
      let actual = operand(t, nodes, node, 0)
      let allowed = match type_name(target) {
        "string" =>
          ["string", "number", "decimal", "boolean", "date", "timestamp"]
        "number" => ["string", "number"]
        "boolean" => ["string", "boolean"]
        "timestamp" => ["string", "timestamp"]
        "decimal" => ["string", "number", "decimal"]
        _ => []
      }
      if !allowed.contains(type_name(actual)) {
        fail(source, TypeMismatch("cast input"))
      }
      typed(t, @contract.with_nullability(target, actual.nullable), source)
    }
    "property" => {
      let receiver = operand(t, nodes, node, 0)
      let name = string(part(node.body, "name"))
      charge(t.budget, source, name)
      let (base, _) = head(t, values[0], source)
      match t.entries[base].kind {
        Product(fields) => {
          // Canonical sorted names permit logarithmic lookup, with no new map.
          let mut lo = 0
          let mut hi = fields.length()
          while lo < hi {
            spend(t.budget, source)
            let mid = lo + (hi - lo) / 2
            let order = @canonical.compare_utf16(fields[mid].0, name)
            if order < 0 {
              lo = mid + 1
            } else {
              hi = mid
            }
          }
          if lo == fields.length() || fields[lo].0 != name {
            fail(source, UnknownField(name))
          }
          let id = fields[lo].1
          refine(t, id, receiver.nullable || nullability(t, id, source), source)
        }
        _ => fail(source, TypeMismatch("closed object receiver"))
      }
    }
    "subscript" => {
      ignore(operand(t, nodes, node, 0))
      ignore(require_type(t, nodes, node.children[1], "number"))
      let (base, _) = head(t, values[0], source)
      match t.entries[base].kind {
        Sequence(item, _) => refine(t, item, true, source)
        _ => fail(source, TypeMismatch("typed array receiver"))
      }
    }
    "is_null" | "not_null" => {
      ignore(operand(t, nodes, node, 0))
      primitive(t, BooleanType, false, source)
    }
    "not" | "and" | "or" | "is_true" | "is_false" | "is_unknown" => {
      let nullable = arguments(t, nodes, node, "boolean")
      primitive(
        t,
        BooleanType,
        nullable && ["not", "and", "or"].contains(tag),
        source,
      )
    }
    "lower"
    | "upper"
    | "trim"
    | "len"
    | "concat"
    | "concat_strict"
    | "replace"
    | "contains"
    | "like" => {
      let nullable = arguments(t, nodes, node, "string")
      if tag == "like" {
        pending.push({ node_index: index, kind: PatternValidation("like"), })
      }
      primitive(
        t,
        if tag == "len" {
          NumberType
        } else if tag == "contains" || tag == "like" {
          BooleanType
        } else {
          StringType
        },
        nullable && tag != "concat",
        source,
      )
    }
    "sqrt" | "floor" | "safe_div" => {
      let nullable = arguments(t, nodes, node, "number")
      primitive(t, NumberType, nullable || tag == "safe_div", source)
    }
    "eq"
    | "neq"
    | "lt"
    | "lte"
    | "gt"
    | "gte"
    | "between"
    | "is_distinct_from"
    | "nullif" => {
      let cs = comparable_operands(
        t,
        nodes,
        node,
        ["lt", "lte", "gt", "gte", "between"].contains(tag),
      )
      if tag == "nullif" {
        refine(t, values[0], true, source)
      } else {
        primitive(
          t,
          BooleanType,
          tag != "is_distinct_from" && cs.any(c => c.nullable),
          source,
        )
      }
    }
    "in" | "not_in" => {
      let (base, _) = head(t, values[1], source)
      let item = match t.entries[base].kind {
        Sequence(item, _) => item
        _ => fail(source, TypeMismatch("membership array"))
      }
      // The independently known left operand can resolve NULL list items.
      let left = nodes[node.children[0]]
      if immediate_null(left) {
        provide(t, left.inferred, item, source)
      } else {
        provide(t, item, left.inferred, source)
      }
      let lc = operand(t, nodes, node, 0)
      let rc = operand(t, nodes, node, 1)
      let ic = resolve_type(t, item, source)
      if !["string", "number", "decimal", "boolean", "date", "timestamp"].contains(
          type_name(lc),
        ) ||
        !@contract.key_comparable(lc, ic) {
        fail(source, TypeMismatch("membership element domain"))
      }
      primitive(
        t,
        BooleanType,
        lc.nullable || rc.nullable || ic.nullable,
        source,
      )
    }
    "negate" => {
      let c = operand(t, nodes, node, 0)
      if !["number", "decimal"].contains(type_name(c)) {
        fail(source, TypeMismatch("number or decimal"))
      }
      values[0]
    }
    "divide" | "modulo" => {
      let nullable = arguments(t, nodes, node, "number")
      primitive(t, NumberType, nullable, source)
    }
    "add" | "subtract" | "multiply" => {
      let cs = comparable_operands(t, nodes, node, false)
      let nullable = cs[0].nullable || cs[1].nullable
      match (cs[0].shape, cs[1].shape) {
        (@contract.Number, @contract.Number) =>
          primitive(t, NumberType, nullable, source)
        (
          @contract.Decimal(precision=p, scale=s),
          @contract.Decimal(precision=q, scale=r),
        ) => {
          let scale = if tag == "multiply" {
            s + r
          } else if s > r {
            s
          } else {
            r
          }
          let p = if tag == "multiply" {
            p + q
          } else {
            (if p - s > q - r { p - s } else { q - r }) + scale + 1
          }
          match
            @contract.decimal_contract(
              if p > 38 {
                38
              } else {
                p
              },
              scale,
              nullable~,
            ) {
            Some(c) => typed(t, c, source)
            None =>
              fail(source, TypeMismatch("representable decimal result scale"))
          }
        }
        _ => fail(source, TypeMismatch("matching numeric domains"))
      }
    }
    "try_decimal" | "quantize" | "decimal_divide" => {
      let target = decimal_target(node)
      let first = operand(t, nodes, node, 0)
      if !(if tag == "try_decimal" {
          ["string", "number", "decimal"].contains(type_name(first))
        } else {
          type_name(first) == "decimal"
        }) {
        fail(source, TypeMismatch("decimal function input"))
      }
      let mut nullable = first.nullable || tag == "try_decimal"
      if tag == "decimal_divide" {
        let divisor = operand(t, nodes, node, 1)
        if !["number", "decimal"].contains(type_name(divisor)) {
          fail(source, TypeMismatch("decimal or number divisor"))
        }
        nullable = nullable || divisor.nullable
      }
      typed(t, @contract.with_nullability(target, nullable), source)
    }
    "date_trunc" | "date_add" | "date_diff" => {
      let vi = if tag == "date_trunc" { 1 } else { 0 }
      let ui = if tag == "date_trunc" { 0 } else { 2 }
      if tag == "date_diff" &&
        immediate_null(nodes[node.children[0]]) &&
        !immediate_null(nodes[node.children[1]]) {
        let peer = operand(t, nodes, node, 1)
        if !["date", "timestamp"].contains(type_name(peer)) {
          fail(source, TypeMismatch("temporal peer"))
        }
        provide(t, values[0], values[1], source)
      }
      let value = operand(t, nodes, node, vi)
      let domain = type_name(value)
      if domain != "date" && domain != "timestamp" {
        fail(source, TypeMismatch("date or timestamp"))
      }
      ignore(require_type(t, nodes, node.children[ui], "string"))
      let unit = string(nodes[node.children[ui]].body)
      if domain == "date" && unit != "d" {
        fail(source, InvalidStaticOption("date unit must be d"))
      }
      if tag == "date_trunc" {
        values[vi]
      } else {
        let other = require_type(
          t,
          nodes,
          node.children[1],
          if tag == "date_add" {
            "number"
          } else {
            domain
          },
        )
        let nullable = value.nullable || other.nullable
        if tag == "date_diff" {
          primitive(t, NumberType, nullable, source)
        } else {
          refine(t, values[0], nullable, source)
        }
      }
    }
    "vector_score" | "vector_concat" => {
      profiles["actql-veca/0.1"] = true
      pending.push({
        node_index: index,
        kind: ProfileAdmission("actql-veca/0.1"),
      })
      let mut nullable = false
      let mut dimensions = 0.0
      let mut dimension_sum = @bigint.BigInt::from_int(0)
      if tag == "vector_score" {
        for i in 0..<2 {
          if immediate_null(nodes[node.children[i]]) &&
            !immediate_null(nodes[node.children[1 - i]]) {
            let peer = operand(t, nodes, node, 1 - i)
            if type_name(peer) != "vector" {
              fail(source, TypeMismatch("vector peer"))
            }
            provide(t, values[i], values[1 - i], source)
          }
        }
      }
      for i in 0..<values.length() {
        let c = operand(t, nodes, node, i)
        nullable = nullable || c.nullable
        let d = match c.shape {
          @contract.Vector(dimensions~) => dimensions
          _ => fail(source, TypeMismatch("typed vector"))
        }
        if tag == "vector_score" {
          if i > 0 && d != dimensions {
            fail(source, TypeMismatch("equal vector dimensions"))
          }
          dimensions = d
        } else {
          dimension_sum = dimension_sum + exact_dimension(d)
        }
      }
      if tag == "vector_score" {
        primitive(t, NumberType, nullable, source)
      } else {
        let width = dimension_sum.bit_length()
        if width > 1024 || (width > 53 && dimension_sum.ctz() < width - 53) {
          fail(source, TypeMismatch("exact representable dimension sum"))
        }
        // Construct the final binary64 only after exact integer accumulation.
        // Prefix sums need not be representable, so argument order is irrelevant.
        let significand = if width > 53 {
          (dimension_sum >> (width - 53)).to_uint64()
        } else {
          dimension_sum.to_uint64() << (53 - width)
        }
        dimensions = (((width + 1022).to_uint64() << 52) |
        (significand & 0x000fffffffffffffUL)).reinterpret_as_double()
        typed(
          t,
          @contract.vector_contract(dimensions, nullable~).unwrap(),
          source,
        )
      }
    }
    _ => fail(source, TypeMismatch("known admitted expression"))
  }
}

///|
// The admitted dimension is a positive finite integer. Decode its significand
// and exponent without decimal conversion or any floating-point addition.
// Each input has at most 1024 bits; the sum grows only logarithmically with
// the already-budgeted number of operands.
fn exact_dimension(value : Double) -> @bigint.BigInt {
  let bits = value.reinterpret_as_uint64()
  let shift = ((bits >> 52) & 0x7ffUL).to_int() - 1023 - 52
  let significand = @bigint.BigInt::from_uint64(
    (bits & 0x000fffffffffffffUL) | 0x0010000000000000UL,
  )
  if shift >= 0 {
    significand << shift
  } else {
    significand >> -shift
  }
}

///|
// Account for both the preflight scan and the existing author reader. JSON
// node/key counts conservatively dominate contract-reader node/text work.
fn item_contract(
  t : Types,
  source : @decode.Cursor,
) -> @contract.Contract raise Stop {
  let before_work = t.budget.work
  let before_text = t.budget.text
  let work = [source]
  while work.pop() is Some(cursor) {
    spend(t.budget, cursor)
    match @decode.view(cursor) {
      TextValue(text) => charge(t.budget, cursor, text)
      ArrayValue(values) => {
        spend(t.budget, cursor, amount=values.length())
        for value in values {
          work.push(value)
        }
      }
      ObjectValue(obj) => {
        let names = decoded(@decode.object_field_names(cursor), cursor)
        spend(t.budget, cursor, amount=names.length())
        for name in names {
          charge(t.budget, cursor, name)
          work.push(@decode.lookup(obj, name).unwrap())
        }
      }
      _ => ()
    }
  }
  let nodes = before_work - t.budget.work
  let bytes = before_text - t.budget.text
  spend(t.budget, source, amount=nodes)
  if bytes > t.budget.text {
    fail(source, BudgetExceeded)
  }
  t.budget.text -= bytes
  match
    @contract.read_author(source, {
      max_nodes: nodes,
      max_depth: t.budget.limits.max_depth,
      max_text_bytes: bytes,
    }) {
    Ok(c) => c
    Err(_) => fail(source, BudgetExceeded)
  }
}
