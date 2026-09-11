///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Scanner {
  text : String
  mut offset : Int
  entries : Array[Entry]
  limits : Limits
  mut class_items : Int
}

///|
priv struct Group {
  capture : Int
  start : Int
  items : Array[Int]
  branches : Array[Int]
}

///|
fn peek(s : Scanner) -> Int {
  if s.offset == s.text.length() {
    -1
  } else {
    s.text[s.offset].to_int()
  }
}

///|
fn take(s : Scanner) -> Int raise Stop {
  let unit = peek(s)
  if unit < 0 {
    raise Stop(InvalidSyntax(s.offset))
  }
  s.offset += 1
  // The complete source has already passed UTF-16 validation.
  if unit >= 0xD800 && unit <= 0xDBFF {
    let low = s.text[s.offset].to_int()
    s.offset += 1
    0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00
  } else {
    unit
  }
}

///|
fn add(s : Scanner, node : Node) -> Int raise Stop {
  if s.entries.length() >= s.limits.max_nodes - s.class_items {
    raise Stop(BudgetExceeded)
  }
  let (nullable, depth) = match node {
    Anchor(_) => (true, 1)
    Capture(_, child) => (s.entries[child].nullable, s.entries[child].depth + 1)
    Repeat(min, _, child) => (min == 0.0, s.entries[child].depth + 1)
    Sequence(children) => {
      let mut n = true
      let mut d = 0
      for c in children {
        n = n && s.entries[c].nullable
        d = Int::max(d, s.entries[c].depth)
      }
      (n, d + 1)
    }
    Alternation(children) => {
      let mut n = false
      let mut d = 0
      for c in children {
        n = n || s.entries[c].nullable
        d = Int::max(d, s.entries[c].depth)
      }
      (n, d + 1)
    }
    CharacterClass(_, _) => (false, 2)
    _ => (false, 1)
  }
  if depth > s.limits.max_depth {
    raise Stop(BudgetExceeded)
  }
  let index = s.entries.length()
  s.entries.push({ node, nullable, depth, })
  index
}

///|
fn escape(s : Scanner) -> ClassItem raise Stop {
  let start = s.offset
  let c = take(s)
  match c {
    110 => Scalar(10)
    114 => Scalar(13)
    116 => Scalar(9)
    100 | 68 | 115 | 83 | 119 | 87 => Escape(c.unsafe_to_char().to_string())
    92
    | 46
    | 94
    | 36
    | 124
    | 63
    | 42
    | 43
    | 40
    | 41
    | 91
    | 93
    | 123
    | 125
    | 45 => Scalar(c)
    _ => raise Stop(InvalidSyntax(start))
  }
}

///|
fn class_scalar(s : Scanner) -> ClassItem raise Stop {
  let start = s.offset
  match take(s) {
    92 => escape(s)
    93 | 45 => raise Stop(InvalidSyntax(start))
    c => Scalar(c)
  }
}

///|
fn character_class(s : Scanner) -> Int raise Stop {
  let negated = peek(s) == 94
  if negated {
    s.offset += 1
  }
  let items : Array[ClassItem] = []
  while peek(s) != 93 && peek(s) != -1 {
    if s.class_items >= s.limits.max_nodes - s.entries.length() {
      raise Stop(BudgetExceeded)
    }
    let start = s.offset
    let first = if peek(s) == 45 &&
      (
        items.is_empty() ||
        (s.offset + 1 < s.text.length() && s.text[s.offset + 1].to_int() == 93)
      ) {
      s.offset += 1
      Scalar(45)
    } else {
      class_scalar(s)
    }
    let item = if peek(s) == 45 &&
      s.offset + 1 < s.text.length() &&
      s.text[s.offset + 1].to_int() != 93 {
      s.offset += 1
      match (first, class_scalar(s)) {
        (Scalar(a), Scalar(b)) if a <= b => Range(a, b)
        _ => raise Stop(InvalidRange(start))
      }
    } else {
      first
    }
    items.push(item)
    s.class_items += 1
  }
  if items.is_empty() || peek(s) != 93 {
    raise Stop(InvalidSyntax(s.offset))
  }
  s.offset += 1
  add(s, CharacterClass(negated, items))
}

///|
fn integer(s : Scanner) -> Double raise Stop {
  let start = s.offset
  let digits = StringBuilder()
  while peek(s) >= 48 && peek(s) <= 57 {
    // Every finite binary64 integer has at most 309 decimal digits. This cap
    // bounds exact-integer work, not a nine-digit or safe-integer restriction.
    if s.offset - start == 309 {
      raise Stop(QuantifierOutOfRange(start))
    }
    digits.write_char(take(s).unsafe_to_char())
  }
  if s.offset == start || (s.offset - start > 1 && s.text[start].to_int() == 48) {
    raise Stop(InvalidQuantifier(start))
  }
  let text = digits.to_string()
  let value = @string.parse_double(text) catch {
    _ => raise Stop(QuantifierOutOfRange(start))
  }
  if @scalar.read_integer_number(value) is None {
    raise Stop(QuantifierOutOfRange(start))
  }
  let exact = @bigint.BigInt::from_string(text)
  let represented = if value == 0.0 {
    @bigint.BigInt::from_int(0)
  } else {
    let bits = value.reinterpret_as_uint64()
    let shift = ((bits >> 52) & 0x7ffUL).to_int() - 1023 - 52
    let sig = @bigint.BigInt::from_uint64(
      (bits & 0x000fffffffffffffUL) | 0x0010000000000000UL,
    )
    if shift >= 0 {
      sig << shift
    } else {
      sig >> -shift
    }
  }
  if exact != represented {
    raise Stop(QuantifierOutOfRange(start))
  }
  value
}

///|
fn quantified(s : Scanner, child : Int) -> Int raise Stop {
  let start = s.offset
  let (min, max) : (Double, Double?) = match peek(s) {
    63 => {
      s.offset += 1
      (0.0, Some(1.0))
    }
    42 => {
      s.offset += 1
      (0.0, None)
    }
    43 => {
      s.offset += 1
      (1.0, None)
    }
    123 => {
      s.offset += 1
      let min = integer(s)
      let max = if peek(s) == 44 {
        s.offset += 1
        if peek(s) == 125 {
          None
        } else {
          Some(integer(s))
        }
      } else {
        Some(min)
      }
      if peek(s) != 125 {
        raise Stop(InvalidQuantifier(s.offset))
      }
      s.offset += 1
      if max is Some(max) && max < min {
        raise Stop(InvalidQuantifier(start))
      }
      (min, max)
    }
    _ => return child
  }
  if s.entries[child].nullable {
    raise Stop(NullableRepeat(start))
  }
  add(s, Repeat(min, max, child))
}

///|
fn finish_sequence(s : Scanner, g : Group) -> Int raise Stop {
  if g.items.is_empty() {
    raise Stop(InvalidSyntax(s.offset))
  }
  if g.items.length() == 1 {
    g.items[0]
  } else {
    add(s, Sequence(g.items))
  }
}

///|
fn parse_tree(s : Scanner) -> (Int, Int) raise Stop {
  let mut captures = 0
  let mut g : Group = { capture: 0, start: 0, items: [], branches: [], }
  let stack : Array[Group] = []
  for ;; {
    let start = s.offset
    match peek(s) {
      -1 | 41 => {
        g.branches.push(finish_sequence(s, g))
        let expression = if g.branches.length() == 1 {
          g.branches[0]
        } else {
          add(s, Alternation(g.branches))
        }
        if g.capture == 0 {
          if peek(s) != -1 {
            raise Stop(InvalidSyntax(start))
          }
          return (expression, captures)
        }
        if peek(s) == -1 {
          raise Stop(InvalidSyntax(g.start))
        }
        s.offset += 1
        let node = add(s, Capture(g.capture, expression))
        g = match stack.pop() {
          Some(g) => g
          None => raise Stop(InvalidSyntax(start))
        }
        g.items.push(quantified(s, node))
      }
      124 => {
        g.branches.push(finish_sequence(s, g))
        g = { ..g, items: [], }
        s.offset += 1
      }
      40 => {
        if stack.length() >= s.limits.max_depth ||
          captures >= s.limits.max_nodes {
          raise Stop(BudgetExceeded)
        }
        s.offset += 1
        captures += 1
        stack.push(g)
        g = { capture: captures, start, items: [], branches: [], }
      }
      _ => {
        let c = take(s)
        let node = match c {
          91 => character_class(s)
          92 =>
            match escape(s) {
              Scalar(cp) => add(s, Literal(cp))
              Escape(v) => add(s, ClassEscape(v))
              Range(_, _) => raise Stop(InvalidSyntax(start))
            }
          46 => add(s, Dot)
          94 | 36 => add(s, Anchor(c.unsafe_to_char().to_string()))
          63 | 42 | 43 | 123 | 125 | 93 | 45 => raise Stop(InvalidSyntax(start))
          cp => add(s, Literal(cp))
        }
        g.items.push(quantified(s, node))
      }
    }
  }
}

///|
pub fn parse(text : String, limits : Limits) -> Result[Pattern, Issue] {
  if limits.max_input_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_ast_bytes < 0 ||
    limits.max_ast_nodes < 0 ||
    limits.max_depth > 1073741822 {
    return Err(InvalidLimits)
  }
  let bytes = match @scalar.admit_utf8_length(text, limits.max_input_bytes) {
    Ok(v) => v
    Err(@scalar.MalformedUtf16(i)) => return Err(InvalidUnicode(i))
    Err(_) => return Err(BudgetExceeded)
  }
  match @canonical.normalize_nfc_lf(text) {
    Ok(v) if v == text => ()
    Ok(_) => return Err(NonCanonicalText)
    Err(@canonical.UnpairedSurrogate(i)) => return Err(InvalidUnicode(i))
  }
  let s : Scanner = { text, offset: 0, entries: [], limits, class_items: 0, }
  let (root, captures) = parse_tree(s) catch {
    Stop(issue) => return Err(issue)
  }
  try {
    let writer = @encode.hashing_writer(
      limits.max_ast_bytes,
      limits.max_ast_nodes,
      limits.max_depth * 2 + 2,
    )
    emit_tree(s.entries, root, captures, None, writer)
    let (hex, _, nodes) = @encode.finish_hash_usage(writer)
    let cid = "sha256:" + hex
    let writer = @encode.measuring_writer(
      limits.max_ast_bytes,
      limits.max_ast_nodes,
      limits.max_depth * 2 + 2,
    )
    emit_tree(s.entries, root, captures, Some(cid), writer)
    let ast_bytes = @encode.finish_measurement(writer)
    Ok({
      entries: s.entries,
      root,
      captures,
      cid,
      input_bytes: bytes,
      ast_bytes,
      ast_nodes: nodes + 1,
    })
  } catch {
    _ => Err(BudgetExceeded)
  }
}
