///|
priv enum Keyword {
  And
  Or
  Not
  Is
  Null
  True
  False
  Unknown
  Distinct
  From
  In
  Between
  Like
  Case
  When
  Then
  Else
  End
  Cast
  As
} derive(Eq)

///|
priv enum Symbol {
  Plus
  Minus
  Multiply
  Divide
  Modulo
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
  Concat
  OpenParen
  CloseParen
  OpenBracket
  CloseBracket
  Comma
  Dot
} derive(Eq)

///|
priv enum TokenKind {
  Word(String)
  QuotedName(String)
  StringLiteral(String)
  NumberLiteral(spelling~ : String, value~ : Double)
  Parameter(String)
  Reserved(Keyword)
  Punctuation(Symbol)
  Eof
} derive(Eq)

///|
/// Offsets are half-open Unicode-scalar offsets in the decoded expression.
priv struct Token {
  kind : TokenKind
  start : Int
  end : Int
}

///|
pub(all) enum LexicalProblem {
  InvalidLimits
  ByteLimit
  TokenLimit
  InvalidUnicode
  UnsupportedToken
  Comment
  UnclosedQuote
  EmptyQuotedName
  ParameterName
  NonfiniteNumber
} derive(Eq, Debug)

///|
priv suberror LexicalError {
  LexicalError(LexicalProblem, Int, Int)
} derive(Debug)

///|
fn ascii_start(ch : Char) -> Bool {
  (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_'
}

///|
fn digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn ascii_continue(ch : Char) -> Bool {
  ascii_start(ch) || digit(ch)
}

///|
fn keyword(text : String) -> Keyword? {
  let upper = StringBuilder()
  for ch in text.iter() {
    upper.write_char(
      if ch >= 'a' && ch <= 'z' {
        (ch.to_int() - 32).unsafe_to_char()
      } else {
        ch
      },
    )
  }
  match upper.to_string() {
    "AND" => Some(And)
    "OR" => Some(Or)
    "NOT" => Some(Not)
    "IS" => Some(Is)
    "NULL" => Some(Null)
    "TRUE" => Some(True)
    "FALSE" => Some(False)
    "UNKNOWN" => Some(Unknown)
    "DISTINCT" => Some(Distinct)
    "FROM" => Some(From)
    "IN" => Some(In)
    "BETWEEN" => Some(Between)
    "LIKE" => Some(Like)
    "CASE" => Some(Case)
    "WHEN" => Some(When)
    "THEN" => Some(Then)
    "ELSE" => Some(Else)
    "END" => Some(End)
    "CAST" => Some(Cast)
    "AS" => Some(As)
    _ => None
  }
}

///|
fn text_slice(chars : Array[Char], start : Int, end : Int) -> String {
  let out = StringBuilder()
  for i = start; i < end; i = i + 1 {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
/// Bound allocation and reject unpaired UTF-16 before String.iter can replace
/// it. No whole-source normalization: diagnostic offsets refer to the original
/// decoded expression, not its normalized token payloads.
fn source_chars(
  source : String,
  max_bytes : Int,
) -> Array[Char] raise LexicalError {
  let chars : Array[Char] = []
  let mut offset = 0
  let mut bytes = 0
  while offset < source.length() {
    let first = source[offset].to_int()
    let mut point = first
    let mut width = 1
    if first >= 0xD800 && first <= 0xDBFF {
      if offset + 1 >= source.length() {
        raise LexicalError(InvalidUnicode, chars.length(), chars.length() + 1)
      }
      let next = source[offset + 1].to_int()
      if next < 0xDC00 || next > 0xDFFF {
        raise LexicalError(InvalidUnicode, chars.length(), chars.length() + 1)
      }
      point = 0x10000 + (first - 0xD800) * 1024 + next - 0xDC00
      width = 2
    } else if first >= 0xDC00 && first <= 0xDFFF {
      raise LexicalError(InvalidUnicode, chars.length(), chars.length() + 1)
    }
    let size = if point < 0x80 {
      1
    } else if point < 0x800 {
      2
    } else if point < 0x10000 {
      3
    } else {
      4
    }
    if size > max_bytes - bytes {
      raise LexicalError(ByteLimit, chars.length(), chars.length() + 1)
    }
    bytes = bytes + size
    chars.push(point.unsafe_to_char())
    offset = offset + width
  }
  chars
}

///|
/// Lexical grammar only: this neither accepts a complete expression nor
/// validates function signatures, types, source positions or reference authority.
/// max_tokens counts non-EOF tokens; exactly one EOF is appended separately.
fn lex(
  source : String,
  max_bytes~ : Int,
  max_tokens~ : Int,
) -> Array[Token] raise LexicalError {
  if max_bytes < 0 || max_tokens < 0 {
    raise LexicalError(InvalidLimits, 0, 0)
  }
  let chars = source_chars(source, max_bytes)
  let tokens : Array[Token] = []
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
      i = i + 1
      continue
    }
    if tokens.length() >= max_tokens {
      raise LexicalError(TokenLimit, i, i + 1)
    }
    let start = i
    let kind : TokenKind = if ch == '\'' || ch == '"' {
      let out = StringBuilder()
      i = i + 1
      let mut closed = false
      while i < chars.length() {
        let current = chars[i]
        i = i + 1
        if current != ch {
          out.write_char(current)
        } else if i < chars.length() && chars[i] == ch {
          out.write_char(ch)
          i = i + 1
        } else {
          closed = true
          break
        }
      }
      if !closed {
        raise LexicalError(UnclosedQuote, start, i)
      }
      let text = out.to_string()
      if ch == '"' && text == "" {
        raise LexicalError(EmptyQuotedName, start, i)
      }
      let normalized = match @canonical.normalize_nfc_lf(text) {
        Ok(value) => value
        Err(_) => raise LexicalError(InvalidUnicode, start, i)
      }
      if ch == '\'' {
        StringLiteral(normalized)
      } else {
        QuotedName(normalized)
      }
    } else if ch == '$' {
      i = i + 1
      if i >= chars.length() || !ascii_start(chars[i]) {
        raise LexicalError(ParameterName, start, i)
      }
      let name_start = i
      while i < chars.length() && ascii_continue(chars[i]) {
        i = i + 1
      }
      Parameter(text_slice(chars, name_start, i))
    } else if ascii_start(ch) {
      i = i + 1
      while i < chars.length() && ascii_continue(chars[i]) {
        i = i + 1
      }
      let text = text_slice(chars, start, i)
      match keyword(text) {
        Some(value) => Reserved(value)
        None => Word(text)
      }
    } else if digit(ch) {
      i = i + 1
      if ch != '0' {
        while i < chars.length() && digit(chars[i]) {
          i = i + 1
        }
      }
      if i + 1 < chars.length() && chars[i] == '.' && digit(chars[i + 1]) {
        i = i + 2
        while i < chars.length() && digit(chars[i]) {
          i = i + 1
        }
      }
      if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
        let mut end = i + 1
        if end < chars.length() && (chars[end] == '+' || chars[end] == '-') {
          end = end + 1
        }
        if end < chars.length() && digit(chars[end]) {
          i = end + 1
          while i < chars.length() && digit(chars[i]) {
            i = i + 1
          }
        }
      }
      let spelling = text_slice(chars, start, i)
      // Share the source decoder's exact-significand rebasing, including its
      // handling of arbitrarily long mantissa/exponent cancellation.
      let value = match
        @value.parse_json(spelling, {
          max_input_bytes: spelling.length(),
          max_nodes: 1,
          max_depth: 0,
        }) {
        Ok({ value: @value.Number(number), .. }) => number
        _ => raise LexicalError(NonfiniteNumber, start, i)
      }
      NumberLiteral(spelling~, value~)
    } else {
      let next = chars.get(i + 1)
      if (ch == '-' && next == Some('-')) ||
        (ch == '/' && next == Some('*')) ||
        (ch == '*' && next == Some('/')) {
        raise LexicalError(Comment, i, i + 2)
      }
      let (symbol, width) = match (ch, next) {
        ('<', Some('>')) => (NotEqual, 2)
        ('<', Some('=')) => (LessEqual, 2)
        ('>', Some('=')) => (GreaterEqual, 2)
        ('|', Some('|')) => (Concat, 2)
        ('+', _) => (Plus, 1)
        ('-', _) => (Minus, 1)
        ('*', _) => (Multiply, 1)
        ('/', _) => (Divide, 1)
        ('%', _) => (Modulo, 1)
        ('=', _) => (Equal, 1)
        ('<', _) => (Less, 1)
        ('>', _) => (Greater, 1)
        ('(', _) => (OpenParen, 1)
        (')', _) => (CloseParen, 1)
        ('[', _) => (OpenBracket, 1)
        (']', _) => (CloseBracket, 1)
        (',', _) => (Comma, 1)
        ('.', _) => (Dot, 1)
        _ => raise LexicalError(UnsupportedToken, i, i + 1)
      }
      i = i + width
      Punctuation(symbol)
    }
    tokens.push({ kind, start, end: i, })
  }
  tokens.push({ kind: Eof, start: i, end: i, })
  tokens
}
