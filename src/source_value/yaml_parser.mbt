///|
priv enum YamlStyle {
  BlockSequence
  BlockMapping
  FlowSequence
  FlowMapping
  FlowPair
} derive(Eq)

///|
priv struct YamlFrame {
  start : Point
  style : YamlStyle
  indent : Int
  container : Container
  mut phase : Phase
  mut key : (String, Span)?
  mut end : Point
}

///|
fn span_end(span : Span) -> Point {
  { byte: span.end_byte, line: span.end_line, column: span.end_column, }
}

///|
fn Parser::yaml_between(self : Parser, start : Point, end : Point) -> Span {
  {
    start_byte: start.byte,
    start_line: start.line,
    start_column: start.column,
    end_byte: end.byte,
    end_line: end.line,
    end_column: end.column,
    source_path: self.source_path,
  }
}

///|
fn Parser::yaml_key(
  self : Parser,
  flow : Bool,
  indent : Int,
  explicit : Bool,
) -> (String, Span) raise ParseAbort {
  let start = self.point()
  let mut plain = false
  let value = if self.yaml_at(0) == 0x22 || self.yaml_at(0) == 0x27 {
    String(self.yaml_quoted(!explicit, indent))
  } else if !flow &&
    explicit &&
    (self.yaml_at(0) == 0x7c || self.yaml_at(0) == 0x3e) {
    String(self.yaml_block_scalar(indent))
  } else if self.yaml_at(0) == 0x5b ||
    self.yaml_at(0) == 0x7b ||
    self.yaml_at(0) == 0x3a {
    self.fail(NonStringKey, self.path)
  } else {
    plain = true
    self.yaml_plain(flow, true, indent, multiline_key=explicit)
  }
  let span = self.span(start)
  if !explicit &&
    (
      span.end_line != span.start_line ||
      span.end_column - span.start_column > 1024
    ) {
    raise self.failure_at(InvalidYamlScalar, self.path, start)
  }
  match value {
    String(key) => {
      if plain && key == "<<" {
        raise self.failure_at(ForbiddenYamlFeature, self.path, start)
      }
      let key = match @canonical.normalize_nfc_lf(key) {
        Ok(key) => key
        Err(_) => raise self.failure_at(InvalidYamlScalar, self.path, start)
      }
      (key, span)
    }
    _ => raise self.failure_at(NonStringKey, self.path, start)
  }
}

///|
fn Parser::yaml_prefix(self : Parser) -> Int? raise ParseAbort {
  self.yaml_skip()
  let mut directive = false
  let mut version = false
  while self.column == 1 && self.yaml_at(0) == 0x25 {
    directive = true
    let start = self.point()
    let begin = self.offset
    while self.yaml_at(0) >= 0 && !yaml_break(self.yaml_at(0)) {
      ignore(self.yaml_take())
    }
    let text = self.source[begin:self.offset].to_owned()
    let words = yaml_directive_words(text)
    if words.is_empty() || words[0] == "%" {
      raise self.failure_at(InvalidYamlDirective, self.path, start)
    }
    if words[0] == "%YAML" {
      if version || words.length() != 2 || words[1] != "1.2" {
        raise self.failure_at(InvalidYamlDirective, self.path, start)
      }
      version = true
    } else if words[0] == "%TAG" {
      raise self.failure_at(ForbiddenYamlFeature, self.path, start)
    }
    self.yaml_skip()
  }
  let explicit = self.yaml_marker(0x2d)
  let marker_line = self.line
  if directive && !explicit {
    self.fail(InvalidYamlDirective, self.path)
  }
  if explicit {
    for i = 0; i < 3; i = i + 1 {
      ignore(self.yaml_take())
    }
    self.yaml_skip()
  }
  if self.yaml_at(0) == 0xfeff {
    self.fail(UnexpectedToken, self.path)
  }
  if explicit {
    Some(marker_line)
  } else {
    None
  }
}

///|
fn Parser::yaml_document(self : Parser) -> Node raise ParseAbort {
  let explicit_document = self.yaml_prefix()
  if self.yaml_marker(0x2d) {
    self.fail(MultipleDocuments, self.path)
  }
  if explicit_document is None && self.yaml_marker(0x2e) {
    self.fail(UnexpectedEnd, self.path)
  }
  let frames : Array[YamlFrame] = []
  let mut need_value = true
  let mut completed : Node? = None
  let mut parent_indent = -1
  let mut origin_line = self.line
  let mut allow_compact = !(explicit_document is Some(line) && self.line == line)
  let mut flow = false
  let mut indentless = false
  let mut empty_at : Point? = if explicit_document is Some(_) {
    Some(self.point())
  } else {
    None
  }
  while true {
    if need_value {
      self.yaml_skip(flow_indent=if flow { Some(parent_indent) } else { None })
      if flow &&
        self.line > origin_line &&
        self.column - 1 <= parent_indent &&
        self.yaml_at(0) != 0x5d &&
        self.yaml_at(0) != 0x7d {
        self.fail(InvalidYamlIndentation, self.path)
      }
      if self.nodes >= self.limits.max_nodes {
        self.fail(NodeLimit, self.path)
      }
      self.nodes += 1
      need_value = false
      let missing = empty_at is Some(_) &&
        (
          self.yaml_at(0) < 0 ||
          self.yaml_marker(0x2e) ||
          self.yaml_marker(0x2d) ||
          (
            flow &&
            (
              self.yaml_at(0) == 0x2c ||
              self.yaml_at(0) == 0x7d ||
              self.yaml_at(0) == 0x5d
            )
          ) ||
          (
            !flow &&
            self.line > origin_line &&
            self.column - 1 <= parent_indent &&
            !(indentless &&
            self.column - 1 == parent_indent &&
            self.yaml_indicator(0x2d))
          )
        )
      if missing {
        let point = empty_at.unwrap()
        completed = Some({ value: Null, span: self.yaml_between(point, point), })
      } else {
        let start = self.point()
        let mut style : YamlStyle? = None
        if self.yaml_at(0) == 0x5b {
          style = Some(FlowSequence)
        } else if self.yaml_at(0) == 0x7b {
          style = Some(FlowMapping)
        } else if flow &&
          allow_compact &&
          (self.yaml_colon(true) is Some(_) || self.yaml_indicator(0x3f)) {
          style = Some(FlowPair)
        } else if !flow && (allow_compact || self.line > origin_line) {
          if self.yaml_indicator(0x2d) {
            style = Some(BlockSequence)
          } else if self.yaml_colon(false) is Some(_) ||
            self.yaml_indicator(0x3f) {
            style = Some(BlockMapping)
          }
        }
        match style {
          Some(style) => {
            if frames.length() >= self.limits.max_depth {
              self.fail(DepthLimit, self.path)
            }
            self.deepest = Int::max(self.deepest, frames.length() + 1)
            let container = if style == BlockSequence || style == FlowSequence {
              ArrayItems([])
            } else {
              ObjectFields([], @shape.key_admission())
            }
            let indent = if style == BlockMapping || style == BlockSequence {
              self.column - 1
            } else {
              parent_indent
            }
            if style == FlowSequence || style == FlowMapping {
              ignore(self.yaml_take())
            }
            frames.push({
              start,
              style,
              indent,
              container,
              phase: First,
              key: None,
              end: self.point(),
            })
          }
          None => {
            if self.yaml_at(0) < 0 {
              self.fail(UnexpectedEnd, self.path)
            }
            let value = if self.yaml_at(0) == 0x22 || self.yaml_at(0) == 0x27 {
              String(self.yaml_quoted(false, parent_indent))
            } else if !flow &&
              (self.yaml_at(0) == 0x7c || self.yaml_at(0) == 0x3e) {
              String(self.yaml_block_scalar(parent_indent))
            } else {
              self.yaml_plain(flow, false, parent_indent)
            }
            completed = Some({ value, span: self.span(start), })
          }
        }
      }
    }
    if completed is Some(node) {
      if frames.is_empty() {
        self.yaml_skip()
        if self.yaml_marker(0x2e) {
          for i = 0; i < 3; i = i + 1 {
            ignore(self.yaml_take())
          }
          self.yaml_horizontal()
          if self.yaml_at(0) >= 0 &&
            self.yaml_at(0) != 0x23 &&
            !yaml_break(self.yaml_at(0)) {
            self.fail(TrailingContent, self.path)
          }
          self.yaml_skip()
        }
        if self.yaml_marker(0x2d) || self.yaml_marker(0x2e) {
          self.fail(MultipleDocuments, self.path)
        }
        if self.yaml_at(0) >= 0 {
          self.fail(TrailingContent, self.path)
        }
        return node
      }
      let parent = frames[frames.length() - 1]
      match parent.container {
        ArrayItems(items) => items.push(node)
        ObjectFields(fields, _) => {
          let (key, key_span) = parent.key.unwrap()
          fields.push({ key, key_span, value: node, })
          parent.key = None
        }
      }
      parent.end = span_end(node.span)
      parent.phase = AfterValue
      ignore(self.path.pop())
      completed = None
    }
    let frame = frames[frames.length() - 1]
    let block = frame.style == BlockMapping || frame.style == BlockSequence
    self.yaml_skip(flow_indent=if block { None } else { Some(frame.indent) })
    let sequence = frame.style == BlockSequence || frame.style == FlowSequence
    let closing = if sequence { 0x5d } else { 0x7d }
    if !block &&
      self.yaml_at(0) >= 0 &&
      self.yaml_at(0) != 0x5d &&
      self.yaml_at(0) != 0x7d &&
      self.line > frame.start.line &&
      self.column - 1 <= frame.indent {
      self.fail(InvalidYamlIndentation, self.path)
    }
    let mut close = false
    if block {
      if frame.phase == AfterValue {
        if self.yaml_at(0) < 0 ||
          self.yaml_marker(0x2d) ||
          self.yaml_marker(0x2e) ||
          self.column - 1 < frame.indent {
          close = true
        } else if self.line == frame.end.line && frame.end.column != 1 {
          self.fail(TrailingContent, self.path)
        } else if self.column - 1 > frame.indent {
          self.fail(InvalidYamlIndentation, self.path)
        } else if sequence && !self.yaml_indicator(0x2d) {
          close = true
        } else if !sequence && self.yaml_indicator(0x2d) {
          close = true
        }
      }
    } else if frame.style == FlowPair {
      close = frame.phase == AfterValue
    } else if self.yaml_at(0) == closing {
      ignore(self.yaml_take())
      frame.end = self.point()
      close = true
    } else if frame.phase == AfterValue {
      if self.yaml_at(0) != 0x2c {
        self.fail(
          if sequence {
            ExpectedArraySeparator
          } else {
            ExpectedObjectSeparator
          },
          self.path,
        )
      }
      ignore(self.yaml_take())
      frame.phase = Next
      continue
    }
    if close {
      ignore(frames.pop())
      let value = match frame.container {
        ArrayItems(items) => Array(items)
        ObjectFields(fields, _) => Object(fields)
      }
      completed = Some({
        value,
        span: self.yaml_between(frame.start, frame.end),
      })
      continue
    }
    if self.yaml_marker(0x2d) || self.yaml_marker(0x2e) {
      self.fail(MultipleDocuments, self.path)
    }
    if self.yaml_at(0) < 0 {
      self.fail(UnexpectedEnd, self.path)
    }
    parent_indent = frame.indent
    flow = !block
    indentless = false
    allow_compact = sequence
    empty_at = None
    if sequence {
      match frame.container {
        ArrayItems(items) => self.path.push(Index(items.length()))
        _ => ()
      }
      if block {
        if !self.yaml_indicator(0x2d) {
          self.fail(InvalidYamlIndentation, self.path)
        }
        ignore(self.yaml_take())
        empty_at = Some(self.point())
      }
      origin_line = self.line
    } else {
      let explicit = self.yaml_indicator(0x3f)
      if explicit {
        ignore(self.yaml_take())
        self.yaml_skip(flow_indent=if flow { Some(frame.indent) } else { None })
      }
      let (key, key_span) = self.yaml_key(flow, frame.indent, explicit)
      self.path.push(Key(key))
      match frame.container {
        ObjectFields(_, keys) =>
          if !@shape.admit_key(keys, key) {
            raise ParseAbort({
              issue: DuplicateKey(key),
              source_path: self.source_path,
              location: Source(key_span),
              path: Some(self.path.copy()),
            })
          }
        _ => ()
      }
      frame.key = Some((key, key_span))
      let key_end = self.point()
      self.yaml_horizontal()
      if explicit {
        self.yaml_skip(flow_indent=if flow { Some(frame.indent) } else { None })
      }
      if self.yaml_at(0) == 0x3a &&
        (!block || self.line == key_end.line || self.column - 1 == frame.indent) {
        if block && self.yaml_at(1) >= 0 && !yaml_space(self.yaml_at(1)) {
          self.fail(ExpectedColon, self.path)
        }
        ignore(self.yaml_take())
        origin_line = self.line
        empty_at = Some(self.point())
        indentless = block
      } else if flow || explicit {
        if self.nodes >= self.limits.max_nodes {
          self.fail(NodeLimit, self.path)
        }
        self.nodes += 1
        completed = Some({
          value: Null,
          span: self.yaml_between(key_end, key_end),
        })
        need_value = false
        frame.phase = Waiting
        continue
      } else {
        self.fail(ExpectedColon, self.path)
      }
    }
    frame.phase = Waiting
    need_value = true
  } nobreak {
    self.fail(UnexpectedEnd, self.path)
  }
}

///|
fn yaml_directive_words(text : String) -> Array[String] {
  let result : Array[String] = []
  let mut i = 0
  while i < text.length() {
    while i < text.length() &&
          (text[i].to_int() == 0x20 || text[i].to_int() == 0x09) {
      i += 1
    }
    if i == text.length() || text[i].to_int() == 0x23 {
      break
    }
    let start = i
    while i < text.length() &&
          text[i].to_int() != 0x20 &&
          text[i].to_int() != 0x09 {
      i += 1
    }
    result.push(text[start:i].to_owned())
  }
  result
}
