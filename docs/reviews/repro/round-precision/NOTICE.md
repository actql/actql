# Reference source attribution

The numerical implementation is from GoogleSQL, Copyright 2019 Google LLC,
licensed under Apache License 2.0.

Pinned revision: `81c15b796138185c046aefe852321011fdf96615`.

- https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/common/round_decimal.cc
- https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/common/round_decimal.h
- https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/common/double_double.h

These files are supplied separately and compiled unchanged after hash verification.
The small ActQL wrapper and compatibility shims select and inspect the upstream
implementation; they do not substitute another numerical algorithm.
