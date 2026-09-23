# ActSQL frontend boundary

ActSQL is a separate MoonBit module, `src/actsql`. Its initial implemented
dialect slice is a literal row projection:

```sql
SELECT 1 AS id, -2 AS debt;
```

The grammar accepts one or more signed 32-bit integer literals, each with an
explicit unquoted ASCII alias, separated by commas. Keywords are
case-insensitive. An optional final semicolon is accepted. Aliases are
case-insensitively unique. The query yields one row with the authored column
order and a named `answer` Result. `FROM`, functions, expressions, parameters,
quoted identifiers, joins, aggregates and other SQL syntax are currently
unsupported; rejection includes the UTF-8 byte offset of the unsupported
token. Source offsets for each accepted literal and alias accompany the
generated document.

`compile_literal_select` emits an ordinary JSON Program document using the
common bounded encoder. The generated Program must still pass normal ActQL
parsing, semantic checking, admission, authorization and execution. This module
does not send SQL to DuckDB or choose a physical backend. Its tests compare a
separately authored Program expectation and pass the output through the
existing Program syntax parser on JS, Wasm and native targets. End-to-end SQL
execution and a public `Client.sql()` entrance remain separate release work;
the existing AQL document path does not depend on them.
