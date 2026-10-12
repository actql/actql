///|
/// LIST_FILES retains its installed Source name and decoded selector expression.
/// It is not a Source capability or an acquisition-completion proof.
pub(all) enum FileListSelector {
  AllFiles
  ExactPaths(Expression)
  Glob(Expression)
}

///|
pub fn file_list_selector(query : Query) -> FileListSelector? {
  query.file_listing
}

///|
fn QueryParser::file_listing_source(
  self : QueryParser,
) -> (Array[NamePart], NamePart?, Array[QueryBinding], Bool, FileListSelector?) raise QueryAbort {
  self.keyword("LIST_FILES")
  self.symbol(40)
  let at = self.peek().start
  if !(self.peek().value is Word(_) || self.peek().value is QuotedName(_)) {
    raise QueryAbort("FileSourceNameMustBeStatic", at)
  }
  // Deliberately do not resolve a WITH producer into an installed Source.
  let relation = self.path()
  if self.peek().value != Symbol(44) && self.peek().value != Symbol(41) {
    raise QueryAbort("FileSourceNameMustBeStatic", at)
  }
  self.node()
  let selector = if self.peek().value == Symbol(44) {
    ignore(self.advance())
    let option = self.name()
    if option.quoted || !["paths", "glob"].contains(option.value.to_lower()) {
      raise QueryAbort("Unknown file selector", self.peek().start)
    }
    self.symbol(61)
    if self.advance().value != Operator(">") {
      raise QueryAbort("Expected file selector arrow", self.peek().start)
    }
    let start = self.index
    let expression = self.expression()
    if option.value.to_lower() == "glob" {
      for index in start..<self.index {
        let token = self.source.tokens[index]
        self.spend(1)
        if token.string_origin is Some({ raw: false, backslash: true, }) {
          raise QueryAbort("GlobEscapeAmbiguous", token.start)
        }
      }
      Glob(expression)
    } else {
      ExactPaths(expression)
    }
  } else {
    AllFiles
  }
  // One exclusive selector; never silently drop a second or unknown argument.
  self.symbol(41)
  (relation, self.optional_source_alias(), [], false, Some(selector))
}
