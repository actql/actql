# Portable resident Effect Checkpoint reports

The resident Site journal can retain and acknowledge the original report, but
the Cloud receiver also needs the common protocol Owner in its portable
Coordinator package. This change exports admission, immutable identity facts,
report-bound reply serialization and reply admission through
`@actql/coordinator-core`. It depends on the original report protocol in #1208;
the final merge destination is main after that parent is integrated.

The facade retains admitted common values in private handles. A copied object,
Dispatch handle or arbitrary metadata cannot be used as a report handle.
Canonical report admission binds the exact dispatch and Checkpoint; it does
not establish remote physical persistence or current authorization.

The receiver must authenticate the current Site/generation, restore the
original Effect Run and retained consumer, and use its existing Run Owner to
persist the exact waiting projection before calling `acceptedJson`. Reply
serialization performs no waiting transition, approval, Effect execution or
custody cleanup. Definitive refusals retain the existing closed protocol codes.

The Node cases compare independent canonical vectors and reject another
consumer attempt/generation, corrupt/noncanonical/oversized reports, forged
handles and foreign ACKs. The type case keeps report and Dispatch handles
distinct and excludes approval and private refusal messages. These cases are
also registered in the existing packed Coordinator consumer; no new package,
version, wire identity or parallel Owner is introduced.

Focused verification prepares only coordinator-core and runs the new facade
cases, the existing payload case and the new declaration type case. The packed
campaign, full Core, Hosted CI, Native execution and Cloud Preview are separate
coverage. This component does not complete the resident CLI capture/Preview
assembly, authenticated Cloud report receipt, approval or resumed Effect apply.
