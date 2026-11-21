# SQL compatibility

ActQL's query text is GoogleSQL with Pipe syntax, extended for models, Effects
and the non-table carriers. This page lists what the SQL surface accepts, what
each form means, and what is refused. It is for people who already know SQL
and want to know how far it carries over. The exact grammar is in the
[query text specification](../spec/query-text.md); how to write Programs is
in [Writing Programs](../authoring.md).

The rule throughout: where a spelling exists in GoogleSQL, ActQL uses it with
the GoogleSQL meaning. ActQL does not claim full GoogleSQL conformance; it
claims that the parts it accepts mean what they mean there. A form that is not
accepted is refused at check time with a named reason, never approximated.

## Statements

| Form | Meaning |
| --- | --- |
| `SELECT … FROM … [WHERE] [GROUP BY] [HAVING] [QUALIFY] [WINDOW] [ORDER BY] [LIMIT [OFFSET]]` | Ordinary query. Clauses keep their SQL meaning and need no Pipe. |
| `SELECT …` without `FROM` | One logical row; expressions and parameters only. |
| `WITH name AS (…), …` | Named intermediate value of any kind (rows, graph, vectors, events). Names nothing else; see [Writing Programs](../authoring.md). |
| `FROM source [JOIN …] \|> step \|> …` | Pipe query. The initial `FROM` may carry its JOINs; every later operation starts with `\|>`. |
| `query ;` followed by `EFFECT … COMMAND …` | The long form of a Command Effect, on a retained Result ([Syntax reference](syntax.md#the-long-forms)). |
| `CREATE TABLE target AS SELECT …`, `CREATE OR REPLACE TABLE target AS (…)` | Whole-table write to a Connector target that publishes a create or replace binding. |
| `UPDATE target SET … WHERE …` | SQL form of an update Effect (same Effect as `\|> EFFECT UPDATE`). |
| `INSERT INTO target …` | SQL form of an insert Effect. |
| `DELETE FROM target WHERE …` | SQL form of a delete Effect. |

One query per Program text, apart from the Command postludes after the `;`. Interpolation
and multiple unrelated statements are refused.

## Pipe operators

Every operator after the first `FROM` is introduced by `|>` and consumes the
previous output. The full form of each ActQL operator, with its parts,
defaults and errors, is on the [Syntax reference](syntax.md).

| Operator | Meaning |
| --- | --- |
| `\|> WHERE condition` | Filter rows. |
| `\|> SELECT expr AS name, …` | Project; ends the input range scope. Supports `*`, `* EXCEPT (…)`, `* REPLACE (…)`, `alias.*` and `object.*`. |
| `\|> EXTEND expr AS name, …` | Add computed columns, keeping the input columns. |
| `\|> SET name = expr, …` | Replace a column's value. |
| `\|> RENAME name AS new, …` | Rename columns. |
| `\|> DROP name, …` | Remove columns. |
| `\|> AS alias` | Rebind the current visible columns under a range alias. |
| `\|> AGGREGATE agg(…) AS name, … GROUP BY key, …` | Group and aggregate. |
| `\|> JOIN other ON … / USING (…)` | Join the current rows with another Relation. |
| `\|> ORDER BY expr [ASC\|DESC] [NULLS FIRST\|LAST], …` | Sort. |
| `\|> LIMIT n [OFFSET m]` | Take rows; `n` and `m` are integer literals or `@parameters`. |
| `\|> DISTINCT` | Remove duplicate rows. |
| `\|> UNION ALL / UNION DISTINCT / INTERSECT DISTINCT / EXCEPT DISTINCT other`, optionally `BY NAME [ON (…)]` or `CORRESPONDING` | Set operations. |
| `\|> PIVOT(agg(expr) FOR axis IN ('a', 'b', …))`, `\|> UNPIVOT …` | Reshape. |
| `\|> ASSERT UNIQUE BY (col, …)` | Prove a key is unique for what follows; fails the Run otherwise. |
| `\|> RESULT name` | Publish the current rows as a named Result and continue. |
| `\|> INFER \`model-task:…\` [ITEM KEY (col, …)] INPUT (col, …) [KEEP (…)] AS name [MAX ITEMS n] [ON FAILURE FAIL]` | Ask a model per row; see [Syntax reference](syntax.md#infer) and [Models and INFER](../guides/models.md). |
| `\|> NEAREST candidates [USING vector] [METRIC m] K n [KEEP (…)] AS name` | Nearest-neighbour search; see [Syntax reference](syntax.md#nearest). |
| `\|> CROSS JOIN source [MAX_OUTPUT_ROWS n]`, `\|> CROSS JOIN UNNEST(…) AS e` | Cross join; array expansion. |
| `\|> name(key: value, …)` | Named call on vectors, graphs or events ([Syntax reference](syntax.md#3-arguments-of-named-calls)). |
| `\|> MATCH pattern`, `\|> node_rows()`, `\|> edge_rows()`, named graph calls | Graph pattern query and graph operations on a Graph input ([Syntax reference](syntax.md#6-graphs)). |
| `\|> SERIALIZE FORMAT … ORDER BY … \| PRESERVE ORDER OPTIONS (…)` | Turn rows into content (a `content_ref`); an `EFFECT STORE` or `EFFECT COMMAND` after it sends the content. `EFFECT STORE` on an object resource requires a `content` column; a Relation becomes content only through `SERIALIZE`. |
| `\|> EFFECT UPDATE target ID key SET (field = value, …)` | Terminal update Effect (the short form). |
| `\|> EFFECT UPSERT target ID key SET (field = value, …)` | Terminal create-or-update Effect. |
| `\|> EFFECT DELETE target ID key` | Terminal delete Effect. |
| `\|> EFFECT INSERT target (col, …) [VALUES (expr, …)]` | Terminal insert Effect; without `VALUES`, the listed columns of each row are written. |
| `\|> EFFECT STORE target SET (field = value, …)` | Terminal write of each row's content as a file or object, or of the rows into a declared table; the fields name the destination and pass the content. |
| `\|> EFFECT COMMAND connection.operation [TARGET expr] ID key [INPUT (field = value, …)]` | Terminal named operation, once per row; `TARGET` when the contract needs one. |
| `\|> CREATE [OR REPLACE] TABLE target` | Terminal whole-table write. |
| `INSERT INTO target (col, …) VALUES (…)`, `UPDATE target SET … WHERE key = …`, `DELETE FROM target WHERE key = …` | The SQL statement forms of the same Effects. |

A Pipe is a logical composition, not an execution boundary: it does not fix
the physical order, create a stage or a Checkpoint, or authorise anything.
At most one data-changing Effect per Program text, always the last step of
the Pipe; Command postludes may follow the terminating `;`. The forms and
their long forms are on the [Syntax reference](syntax.md#9-effects).

## Joins

| Join | Supported | Notes |
| --- | --- | --- |
| `[INNER] JOIN … ON / USING` | yes | Equality keys; conjunctions of keys; grouping parentheses are transparent. |
| `LEFT [OUTER] JOIN` | yes | Unmatched right columns become nullable. |
| `RIGHT [OUTER] JOIN` | yes | Unmatched left columns become nullable. |
| `CROSS JOIN` | yes | |
| `FULL [OUTER] JOIN` | partial | Requires proven key identity on both sides; chains of FULL JOINs are refused. |
| `… MAX_OUTPUT_ROWS n` | yes | An author guard on the join's output; exceeding it fails the Run. |

Join keys are columns or value-table receivers compared for equality; arithmetic,
casts and whole-row keys are refused. `USING` exposes one key column, in the
authored order, ahead of the remaining left then right columns.

## Set operations

`UNION ALL`, `UNION DISTINCT`, `INTERSECT DISTINCT` and `EXCEPT DISTINCT` are
supported in SQL chains and as Pipe operators. Column matching is positional by
default; `BY NAME`, `BY NAME ON (col, …)`, `CORRESPONDING` and
`STRICT CORRESPONDING` select name-based matching with the GoogleSQL meanings.
`INNER … BY NAME` keeps only the common columns. `FULL`/`LEFT` name
propagation is not supported.

## Expressions

| Area | Supported |
| --- | --- |
| Literals | strings (single, double, triple-quoted, raw `r'…'`, adjacent chunks concatenate), integers (decimal, hex), finite doubles, `TRUE`/`FALSE`, `NULL`, arrays `[…]`, `ARRAY[…]` and `ARRAY<T>[]` (the empty array needs its element type) |
| Parameters | `@name`, declared by the Program; never interpolated |
| Comparison and logic | `=`, `<>`, `!=`, `<`, `<=`, `>`, `>=`, `AND`, `OR`, `NOT`, `IS [NOT] NULL`, `IN (…)`, `IN UNNEST(array)`, `BETWEEN`, `LIKE`, `NOT LIKE` |
| Conditionals | `CASE WHEN … THEN … ELSE … END`, `IF`, `IFNULL`, `COALESCE`, `NULLIF` |
| Casts | `CAST(x AS STRING \| NUMBER \| FLOAT64 \| DOUBLE \| BOOLEAN \| INT64 \| TIMESTAMP \| DECIMAL(P,S))`; same-type casts are identity |
| Timestamp patterns | `PARSE_TIMESTAMP(format, string)`, `FORMAT_TIMESTAMP(format, timestamp)` with the pinned text-time grammar below |
| Strings | `CONCAT`, `\|\|`, `LENGTH`, `LOWER`, `UPPER`, `TRIM`, `LTRIM`, `RTRIM`, `LEFT`, `RIGHT`, `LPAD`, `RPAD`, `SUBSTRING`, `REPLACE`, `SPLIT`, `STARTS_WITH`, `ENDS_WITH`, `INSTR`, `STRPOS`, `BYTE_LENGTH`, `UNICODE`, `TRANSLATE`, `CONTAINS` |
| Numbers | `+ - * /`, `ABS`, `SIGN`, `ROUND`, `TRUNC`, `FLOOR`, `SQRT`, `CBRT`, `POW`, `EXP`, `LN`, `LOG`, `LOG10`, trigonometric functions, `GREATEST`, `LEAST`, `SAFE_DIVIDE` and the other `SAFE_*` forms |
| Exact integers | `CAST(value AS INT64)`, `MOD`, `DIV`; signed 64-bit integers remain distinct from `NUMBER`. Integer/decimal `MOD` and `DIV` preserve exact arithmetic and NULL propagation. |
| Aggregates | `COUNT(*)`, `COUNT(x)`, `COUNTIF`, `SUM`, `AVG`, `MIN`, `MAX`, `ARRAY_AGG(x ORDER BY …)`, `STRING_AGG(x, 'sep' ORDER BY …)`, filtered aggregates (`… WHERE …` inside the call) |
| Window functions | `OVER (PARTITION BY … ORDER BY … [ROWS …])` with the supported analytic functions, `QUALIFY`, named `WINDOW` specifications |
| Vectors | `VECTOR_COSINE_SIMILARITY`, `VECTOR_INNER_PRODUCT`, `VECTOR_L2_DISTANCE`, `VECTOR_CONCAT` |

The full function list, with types and NULL rules, is in
[Types and functions](types-and-functions.md).

`LIKE` uses the existing case-sensitive Common pattern rules: `%` matches
zero or more Unicode scalars, `_` matches one scalar, and backslash escapes
the next scalar. Neither operand is normalized. The pattern must be a checked
string literal or original bound string Parameter; a computed pattern and a
trailing escape are refused. A NULL input yields NULL after the original
pattern checks. `NOT LIKE` negates that Boolean using ordinary NULL propagation.
There is no implicit regex engine, `ESCAPE` clause or host-language matcher.
Comparison and backtracking remain subject to the original execution work and
cancellation limits.

Timestamp casts require a valid canonical UTC value with `T`, a trailing `Z`
and 3–9 fractional digits, without redundant trailing zeros beyond the minimum
three places. For example, `2026-01-02T03:04:05.123Z` and
`2026-01-02T03:04:05.123456789Z` are valid. Zero fractional digits, spaces,
offset suffixes, redundant fractions such as `.123000Z`, and surrounding
whitespace are refused rather than normalized.
An admitted program can fail when its runtime text is converted: this boundary
reports `evaluation.timestamp_canonical_required`, rather than treating the
canonical-form failure as a generic operand failure.

Timestamp pattern functions require the text-time profile. Their existing
grammar uses `yyyy`, `MM`, `dd`, `HH`, `mm`, `ss` and `SSS`, each at most once;
the literal separators are `-`, `/`, `:`, space, `.`, and `T`. Percent directives
such as `%Y` are not part of this grammar. Parsing requires a complete date,
consumes the whole input and validates the calendar. Missing time components
default to zero; the result has millisecond precision. Formatting `SSS` selects
the millisecond digits of an admitted timestamp without rounding. Input,
pattern, output and execution limits still apply. An original authored pattern
failure has the cause-bearing Problem code `ClientProgramTimestampPatternInvalid`
when its existing current-audience disclosure is available. This is distinct
from a missing text-time profile or an execution-time input-value failure.

```sql
SELECT PARSE_TIMESTAMP('yyyy-MM-dd', '2026-01-02') AS parsed;
SELECT FORMAT_TIMESTAMP('yyyy',
  CAST('2026-01-02T03:04:05.123456789Z' AS TIMESTAMP)) AS year;
```

`DATE '2026-01-02'` returns a non-null Date. One-digit months and days are
accepted and the Result uses the canonical padded spelling. Invalid Gregorian
dates are refused before execution.

`TIMESTAMP '2026-01-02 03:04:05+00'` returns the Timestamp instant
`2026-01-02T03:04:05.000Z`. Literals support UTC, fixed numeric offsets and up to
six subsecond digits using the [SQL literal profile](../spec/query-text.md).
The explicit `CAST(... AS TIMESTAMP)` path continues to require canonical UTC
input as described above.

`DATE(year, month, day)` constructs a Date from three INT64 values. It
supports years 0001 through 9999 and checks the actual number of days in the
month. An out-of-range or impossible date fails evaluation.

`DATE_ADD(date, INTERVAL n DAY)` adds signed INT64 days. `DATE_DIFF(end, start, DAY)`
counts signed day boundaries and returns INT64. `DATE_TRUNC(date, MONTH)` returns
the first day of that month as a Date. These forms require Date operands and
propagate NULL after the original operands are evaluated.

`ARRAY_CONCAT(array, ...)` joins one or more arrays with compatible item
types. It preserves order and duplicates and returns NULL for a NULL array
operand. The function uses the existing array value bounds.
[GoogleSQL ARRAY_CONCAT](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/array_functions#array_concat)

`ARRAY_TO_STRING(array, delimiter[, null_text])` joins STRING items in order.
It omits NULL elements when `null_text` is left out and substitutes it when
provided. A NULL argument returns NULL. The selected signature uses the
existing String domain. [GoogleSQL ARRAY_TO_STRING](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/array_functions#array_to_string)

`LOGICAL_AND(expression)` and `LOGICAL_OR(expression)` aggregate Boolean values.
Each ignores NULL observations and returns NULL for an empty or all-NULL group.
A per-call `WHERE` filters the input to that call. The selected forms are
grouped aggregates. [GoogleSQL Boolean aggregates](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#logical_and)

`CURRENT_DATE()` and bare `CURRENT_DATE` return the non-null UTC Date of the
original query invocation. Repeated occurrences and Saved reads use that same
original. Time-zone arguments are outside this selected signature.

`EXTRACT(YEAR FROM value)` reads the UTC year of a Timestamp and returns INT64.
The same form supports QUARTER, MONTH, DAY, DAYOFWEEK, DAYOFYEAR, HOUR, MINUTE,
SECOND, MILLISECOND and MICROSECOND.

`TIMESTAMP_DIFF(end, start, HOUR)` returns whole hours as INT64. Both arguments
must be Timestamp values. Negative durations truncate toward zero. The static
unit can be MICROSECOND, MILLISECOND, SECOND, MINUTE, HOUR or DAY.

`TIMESTAMP_TRUNC(value, DAY)` returns the Timestamp at the start of its UTC
day. The same unquoted six unit keywords are available as for
`TIMESTAMP_DIFF`. The operation preserves Timestamp nullability.

`GENERATE_ARRAY(1, 3)` returns an array of INT64 values. The same expression
can be used in `FROM UNNEST(GENERATE_ARRAY(1, 3)) AS x`. The default step is 1.
With a signed step, the result includes every reached endpoint, preserves
descending order for negative steps, and is empty for the wrong direction.
NULL input yields a NULL array and zero step is refused. Array output is
subject to the selected resource limits.

Ordinary collection aggregates require their own `ORDER BY`; an enclosing
query's order is not a substitute. `STRING_AGG(s, ',' ORDER BY n)` is the
supported spelling. `ARRAY_AGG` uses ActQL's existing NULL exclusion with or
without the optional `IGNORE NULLS` spelling. Its input must also retain a
candidate-key witness. A literal `UNION ALL` input is not implicitly assigned
a key from the observed values or row positions. Use a declared input key or
an explicit `ASSERT UNIQUE BY` before aggregation; that assertion is checked,
not inferred. Without the witness, an ordered call is refused with
`UnresolvedOrder`; omitting the order is a syntax refusal naming
`ARRAY_AGG requires aggregate ORDER BY`. See [environment qualification](status.md#sql-collection-profile).

For literal CLI `sql` and `aql` queries, the optional
`--parameter-declarations-file` supplies those declarations as named value
contracts. `--params` supplies values separately; neither types nor nullability
are inferred from them. See the [typed quick-query example](../cli.md#quick-queries).

## NULL rules

- `NULL` is SQL `NULL`: unknown. Comparisons with `NULL` yield `NULL`, and a
  `WHERE` keeps only rows whose condition is `TRUE`.
- Scalar functions propagate `NULL` unless their entry in
  [Types and functions](types-and-functions.md) says otherwise.
- `CONCAT` and `||` propagate `NULL`. `ACTQL.CONCAT` is the explicit
  null-skipping variant.
- `SUM`, `AVG`, `MIN` and `MAX` ignore `NULL`; `COUNT(x)` counts non-null
  values; `COUNT(*)` counts rows.
- Outer joins extend unmatched columns with `NULL` and mark them nullable in
  the checked schema.
- A column that an external system may omit is distinct from a `NULL` value;
  the checker refuses to read a column that is not guaranteed present.

Exact integer function operands retain integer-spelled SQL lexemes before
binary64 lowering, including through literal CTE/UNION producers. Their ordinary
`NUMBER` columns and other consumers retain the existing view; `5.0`, `5e0` and
declared `NUMBER` columns are not implicitly promoted. Explicit FLOAT64/NUMBER
to INT64 casts round to nearest with ties away from zero and reject overflow.
INT64 Result values use canonical decimal strings on the existing wire.

## Not accepted

These are refused at check time with a named reason. They are either outside
the selected GoogleSQL profile, or deliberately absent from ActQL.

| Form | Why |
| --- | --- |
| User-defined functions, `CREATE FUNCTION`, lambdas, inline JavaScript or Python | ActQL has no escape hatches; see [Language design](../concepts/language-design.md#no-escape-hatches). |
| Procedural SQL (`BEGIN`, `LOOP`, `IF … THEN`, variables, cursors) | A Program is finite and declarative. |
| `SELECT … INTO`, `MERGE`, DDL other than `CREATE [OR REPLACE] TABLE … AS` | Changes to external systems are Effects with their declared forms (`UPSERT` replaces `MERGE`). |
| `BYTES` literals and functions, collations, `SAFE_CAST`, `::` casts, `DATE` as a cast target | Not in the selected profile. |
| Computed `LIMIT`/`OFFSET`, `LIMIT 0` | Only integer literals or parameters. |
| Non-equality join keys, joins on computed keys | Keys are columns compared for equality. |
| Chains of `FULL JOIN`, `FULL`/`LEFT` `BY NAME` set operations | Not supported. |
| Multiple aggregates, non-string axes or computed buckets in `PIVOT` | Only the single-aggregate, string-axis form. |
| Unknown function names or operations | Never resolved by fuzzy matching or synonyms. |
| `TIMESTAMP '…'` with a named zone other than UTC or Etc/UTC | The literal profile supports fixed offsets without zone-rule lookup. |
| Scalar subqueries, `IN (SELECT …)` and `EXISTS` | Only the documented relational subquery positions are selected; no implicit scalar or correlated evaluation. |
| Simple `CASE value WHEN …`; unaliased computed SELECT items | Use searched `CASE WHEN …` and explicit output names. Direct field projections keep their documented names. |
| Analytic aggregates and `FIRST_VALUE`/`LAST_VALUE` without explicit `ROWS` frames | No implicit GoogleSQL default frame. The explicit-frame forms remain supported. |
| `NTILE`, `PERCENT_RANK`, three-argument `LAG`/`LEAD` | Not in the selected analytic signatures; no default-value or rank semantics are guessed. |
| `DATE` conversion overloads and other `DATE_* … INTERVAL/unit` parts | The interval addition and boundary difference forms select DAY. Boundary truncation selects MONTH. Documented quoted-unit and Number-duration forms retain their existing signatures. |
| `ARRAY_LENGTH` | This GoogleSQL function spelling is not selected; array literals and the documented `UNNEST` forms remain supported. |
| `TIMESTAMP_DIFF` with non-Timestamp arguments or a non-fixed unit | The selected Timestamp signature accepts MICROSECOND through DAY and returns whole units as INT64. |
| `EXTRACT` with a week or ISO-year part, a nonnumeric part, a non-Timestamp input or a timezone clause | The selected numeric Timestamp parts use UTC. |
| `TIMESTAMP_TRUNC` with a timezone argument or a calendar unit beyond DAY | The selected Timestamp signature uses fixed UTC buckets from MICROSECOND through DAY. |
| `GENERATE_ARRAY` with FLOAT64 or decimal operands | The selected signature generates exact INT64 progressions. |
| `REGEXP_CONTAINS`, `REGEXP_EXTRACT`, `REGEXP_REPLACE`, `ANY_VALUE`, `JSON_VALUE`, `FORMAT`, `TO_JSON_STRING`, `UNIX_SECONDS`, `SHA256`, `FARM_FINGERPRINT`, `CURRENT_DATE(time_zone)` | Outside the selected public function signatures. Refused as unsupported functions, not resolved through host-language functions or implicit timezone, regex, JSON, hashing or aggregation defaults. |
| Comma joins; `GROUP BY ROLLUP` | Use the documented explicit joins and grouping forms; no implicit expansion is selected. |
| Recursive queries, `GENERATE_UUID`, `DATETIME`/`TIME`/`NUMERIC`/`INTERVAL` literals | Outside the selected profile pending explicit language decisions; no recursive, random, clock or new scalar domain is introduced. |
| `\|> CALL`, `\|> WINDOW` as a standalone step, `\|> TABLESAMPLE`, `\|> ASSERT condition` | GoogleSQL pipe operators outside the accepted set; the `WINDOW` clause inside `SELECT`/`EXTEND` and `\|> ASSERT UNIQUE BY` are accepted. |
| String interpolation, several statements in one text | One query per Program text, with at most one data-changing Effect and Command postludes after the `;`. |

What is defined here and what each environment executes today are different
questions; see [Implementation status](status.md).


### Collection-order refusals

Ordinary `STRING_AGG` and `ARRAY_AGG` retain their required local `ORDER BY`.
The original parser's typed absence selects `ClientProgramAggregateOrderRequired`
with the existing invalid-input refusal. An arbitrary diagnostic string cannot
issue that cause. Window ordering and the already supported ordered forms keep
their existing meanings.

A checked order that cannot obtain its required original evidence retains the
general `ClientProgramOrderUnresolved` cause and existing operation-failed
refusal category. This code does not assert an ARRAY-specific origin or a
universal candidate-key law: other order sites can have their own applicable
total-order witness. For `ARRAY_AGG`, the selected aggregate profile still
requires the retained candidate key described above; writing `ORDER BY` alone
or observing unique literal rows does not supply that proof. The original
ordered-but-unkeyed query remains refused. Existing explicit `ASSERT UNIQUE BY`
controls retain their distinct positive acceptance.

Both causes use the existing two-field Problem and current-audience disclosure
boundary. A missing or protected original observation reveals only the existing
coarse refusal, and retained lookup does not submit or compile another Run.
