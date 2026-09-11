///|
priv enum Action {
  Visit(Int)
  CloseObject
  Key(String)
  Text(String)
  Number(Double)
  OptionalNumber(Double?)
  Boolean(Bool)
  Children(Array[Int], Int)
  ClassItems(Array[ClassItem], Int)
}

///|
fn emit_tree(
  entries : Array[Entry],
  root : Int,
  captures : Int,
  cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if cid is Some(cid) {
    @encode.key(writer, "ast_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "capture_count")
  @encode.number_value(writer, captures.to_double())
  @encode.key(writer, "root")
  let todo : Array[Action] = [Visit(root)]
  while todo.pop() is Some(action) {
    match action {
      CloseObject => @encode.end_object(writer)
      Key(v) => @encode.key(writer, v)
      Text(v) => @encode.string_value(writer, v)
      Number(v) => @encode.number_value(writer, v)
      Boolean(v) => @encode.bool_value(writer, v)
      OptionalNumber(v) =>
        match v {
          Some(v) => @encode.number_value(writer, v)
          None => @encode.null_value(writer)
        }
      Children(children, i) => {
        if i == 0 {
          @encode.begin_array(writer)
        }
        if i == children.length() {
          @encode.end_array(writer)
        } else {
          todo.push(Children(children, i + 1))
          todo.push(Visit(children[i]))
        }
      }
      ClassItems(items, i) => {
        if i == 0 {
          @encode.begin_array(writer)
        }
        if i == items.length() {
          @encode.end_array(writer)
        } else {
          @encode.begin_object(writer)
          match items[i] {
            Scalar(cp) => {
              @encode.key(writer, "codepoint")
              @encode.number_value(writer, cp.to_double())
              @encode.key(writer, "kind")
              @encode.string_value(writer, "literal")
            }
            Range(a, b) => {
              @encode.key(writer, "end")
              @encode.number_value(writer, b.to_double())
              @encode.key(writer, "kind")
              @encode.string_value(writer, "range")
              @encode.key(writer, "start")
              @encode.number_value(writer, a.to_double())
            }
            Escape(v) => {
              @encode.key(writer, "kind")
              @encode.string_value(writer, "class_escape")
              @encode.key(writer, "value")
              @encode.string_value(writer, v)
            }
          }
          @encode.end_object(writer)
          todo.push(ClassItems(items, i + 1))
        }
      }
      Visit(index) => {
        @encode.begin_object(writer)
        todo.push(CloseObject)
        match entries[index].node {
          Literal(cp) => {
            @encode.key(writer, "codepoint")
            @encode.number_value(writer, cp.to_double())
            @encode.key(writer, "kind")
            @encode.string_value(writer, "literal")
          }
          ClassEscape(v) | Anchor(v) => {
            @encode.key(writer, "kind")
            @encode.string_value(
              writer,
              if entries[index].node is Anchor(_) {
                "anchor"
              } else {
                "class_escape"
              },
            )
            @encode.key(writer, "value")
            @encode.string_value(writer, v)
          }
          Dot => {
            @encode.key(writer, "kind")
            @encode.string_value(writer, "dot")
          }
          CharacterClass(negated, items) => {
            todo.push(Boolean(negated))
            todo.push(Key("negated"))
            todo.push(Text("class"))
            todo.push(Key("kind"))
            todo.push(ClassItems(items, 0))
            todo.push(Key("items"))
          }
          Capture(c, child) => {
            todo.push(Text("capture"))
            todo.push(Key("kind"))
            todo.push(Visit(child))
            todo.push(Key("expression"))
            todo.push(Number(c.to_double()))
            todo.push(Key("capture"))
          }
          Repeat(min, max, child) => {
            todo.push(Number(min))
            todo.push(Key("min"))
            todo.push(OptionalNumber(max))
            todo.push(Key("max"))
            todo.push(Text("repeat"))
            todo.push(Key("kind"))
            todo.push(Visit(child))
            todo.push(Key("expression"))
          }
          Sequence(children) | Alternation(children) => {
            let alt = entries[index].node is Alternation(_)
            todo.push(Text(if alt { "alternation" } else { "sequence" }))
            todo.push(Key("kind"))
            todo.push(Children(children, 0))
            todo.push(Key(if alt { "branches" } else { "items" }))
          }
        }
      }
    }
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-regex-ast/0.1")
  @encode.end_object(writer)
}

///|
pub fn emit(
  v : Pattern,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_tree(v.entries, v.root, v.captures, Some(v.cid), writer)
}

///|
pub fn emit_preimage(
  v : Pattern,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_tree(v.entries, v.root, v.captures, None, writer)
}
