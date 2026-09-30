# ORDER BY aliases across SELECT and JOIN

## Scope

Initial baseline: `a526fe6e16c77d51ec180297e949a719b71e93d7`.
Adopted main after INFER source integration:
`0a7398e486b1547b41fa292385011fd844c59cad`.
The three committed implementation units were rebased onto this main.
Conflicts were limited to the packed mode selectors and appended bridge tests;
both INFER and ORDER acceptance paths were retained. No other worktree changed.
This fixes existing SQL/Pipe ORDER BY semantics, without changing grammar,
public API, wire contracts, provider execution or Run ownership. Affected generated
Program identities change; the Grammar Manifest and JSON/YAML Program admission
remain unchanged.

An unqualified reference inside ORDER BY resolves a SELECT alias first.
A qualified reference retains its input meaning. Expression equality permits
reuse of a selected slot only when reference bindings are also equal.
Several aliases of an equal SELECT expression are alternative evaluated
slots, not an ambiguous ORDER BY expression.

JOIN and CTE JOIN now evaluate SELECT before any alias-dependent ORDER
expression. ORDER expressions read evaluated slots; SELECT expressions are
not substituted into them. Equal ORDER expressions share one private slot.
Private slots are removed before the Named Result and never enter DISTINCT.
Independently declared SELECT occurrences keep their original evaluation
count. Existing unsupported DISTINCT orderings remain rejected.

## CTE acquisition connection

The first packed probe found an existing Frontend capture-shape gap, also
present without ORDER BY: a source CTE started with SELECT and could not
satisfy the common scan/filter/select acquisition contract. It fell through
to source-free Invocation admission and was correctly rejected by the issuer.

The Frontend now uses the same explicit capture builder as ordinary SELECT,
then evaluates the CTE over that captured Stage Result. Repeated CTE references
share the one producer. This preserves Source Evidence admission and does not
add a Host fallback or a second acquisition owner. The independent Program
fixture checks the capture and both producer references; the packed fixtures
require exactly one physical source read per Run.

## Independent acceptance fixtures

`spec/frontend/fixtures/join-order/cases.json` contains authored source rows,
expected rows, ordered column contracts and a DISTINCT refusal. It covers
normal SELECT, computed aliases, identical expressions with two aliases,
qualified input references, an alias changing an expression's reference
meaning, CTE JOIN and ordinary Pipe SELECT. Direct GeneratedValues Pipe JOIN is
covered by the shared compiler/checker regression. The currently unrouted
WITH-plus-Pipe combination is a typed refusal here, not a permanent language
restriction or a claimed execution success. The input order differs from the expected
alias order.

The installed Host supports these real-input JOIN cases through the existing
CTE acquisition boundary. Direct GeneratedValues JOIN is also tested through
the same projection/compiler helpers and normal checker. This change does
not add direct Source View JOIN support.

Run the focused packed test with:

```sh
node scripts/test-packed-public-query.mjs --join-order-only
```

The default packed public-query test also includes these cases. Both
Embedded Local and HTTP use the unchanged installed Client API, compare
Named Result rows and `Result.describe().columns`, and check that attach,
resubmission and rereading do not acquire again. The refusal must leave Run
admission and provider I/O unchanged. No frontend test bridge is loaded by
the external installation.

## Verification

Before the fix, the targeted regression file had four failures and one
qualified-reference control success. After the fix, all 81 query_program
JS tests passed, including six new regression tests. Syntax checks for the
two edited Node scripts and `git diff --check` passed.

Fixed-source packed evidence and affected job results will be recorded after
running the committed source. Linux CI for this JOIN branch is not yet verified.
