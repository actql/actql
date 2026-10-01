# Internal structural fixture tool

This package decodes and formats historical structural fixtures only. It is
not a public source frontend, compatibility entry, or runtime package export.
`parse_fixture`, `parse_fixture_bytes`, and `format_fixture` retain independent
lossless tests without allowing public Host input to execute the old language.
Production imports must not depend on this package. Historical source files
and expected machine Programs remain separate artifacts.
