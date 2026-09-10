///|
priv suberror ExpressionError {
  SyntaxFailure(Int, Int)
  UnknownFunction(Int, Int)
  InvalidArguments(Int, Int)
  CapacityExceeded(Int, Int)
}

///|
priv struct Parsed {
  node : @value.Node
  numeric_token : Bool
  chain : String?
}

///|
priv struct Parser {
  field_references : Array[FieldReference]
  relation_references : Array[FieldReference]
  tokens : Array[Token]
  span : @value.Span
  mut pos : Int
  mut nodes : Int
  max_depth : Int
  max_nodes : Int
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.tokens[self.pos]
}

///|
fn Parser::has(self : Parser, kind : TokenKind) -> Bool {
  self.peek().kind == kind
}

///|
fn Parser::advance(self : Parser) -> Token raise ExpressionError {
  let token = self.peek()
  if token.kind == Eof {
    raise SyntaxFailure(token.start, token.end)
  }
  self.pos = self.pos + 1
  token
}

///|
fn Parser::take(self : Parser, kind : TokenKind) -> Unit raise ExpressionError {
  let token = self.peek()
  if token.kind != kind {
    raise SyntaxFailure(token.start, token.end)
  }
  ignore(self.advance())
}

///|
fn Parser::node(
  self : Parser,
  value : @value.Value,
) -> @value.Node raise ExpressionError {
  if self.nodes >= self.max_nodes {
    let token = self.peek()
    raise CapacityExceeded(token.start, token.end)
  }
  self.nodes = self.nodes + 1
  { value, span: self.span, }
}

///|
fn Parser::object(
  self : Parser,
  fields : Array[(String, @value.Node)],
) -> @value.Node raise ExpressionError {
  self.node(
    @value.Object(
      fields.map(pair => { key: pair.0, key_span: self.span, value: pair.1, }),
    ),
  )
}

///|
fn Parser::form(
  self : Parser,
  name : String,
  value : @value.Node,
) -> @value.Node raise ExpressionError {
  self.object([(name, value)])
}

///|
fn Parser::arguments(
  self : Parser,
  name : String,
  args : Array[@value.Node],
) -> @value.Node raise ExpressionError {
  self.form(name, self.node(@value.Array(args)))
}

///|
fn parsed(node : @value.Node) -> Parsed {
  { node, numeric_token: false, chain: None, }
}

///|
fn literal_value(node : @value.Node) -> @value.Node? {
  object_get(node, "literal")
}

///|
fn precedence(token : TokenKind) -> Int {
  match token {
    Reserved(Or) => 1
    Reserved(And) => 2
    Reserved(Is) => 4
    Punctuation(Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual) =>
      5
    Reserved(In | Between | Like) => 6
    Punctuation(Concat) => 7
    Punctuation(Plus | Minus) => 8
    Punctuation(Multiply | Divide | Modulo) => 9
    Word(_)
    | QuotedName(_)
    | StringLiteral(_)
    | NumberLiteral(..)
    | Parameter(_)
    | Eof
    | Reserved(
      Not
      | Null
      | True
      | False
      | Unknown
      | Distinct
      | From
      | Case
      | When
      | Then
      | Else
      | End
      | Cast
      | As
    )
    | Punctuation(
      OpenParen
      | CloseParen
      | OpenBracket
      | CloseBracket
      | Comma
      | Dot
    ) => 0
  }
}
