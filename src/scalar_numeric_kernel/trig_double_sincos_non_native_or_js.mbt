// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// Calculates the sine of a number in radians. Handles special cases and edge
/// conditions according to IEEE 754 standards.
///
/// Parameters:
///
/// * `x` : The angle in radians for which to calculate the sine.
///
/// Returns the sine of the angle `x`.
///
/// Example:
///
/// ```mbt check
/// test {
///   inspect(@scalar_numeric_kernel.sin(0.0), content="0")
///   inspect(@scalar_numeric_kernel.sin(1.570796326794897), content="1") // pi / 2
///   inspect(@scalar_numeric_kernel.sin(2.0), content="0.9092974268256817")
///   inspect(@scalar_numeric_kernel.sin(-5.0), content="0.9589242746631385")
///   inspect(
///     @scalar_numeric_kernel.sin(31415926535897.9323846),
///     content="0.0012091232715481885",
///   )
///   inspect(@scalar_numeric_kernel.sin(@double.not_a_number), content="NaN")
///   inspect(@scalar_numeric_kernel.sin(@double.infinity), content="NaN")
///   inspect(@scalar_numeric_kernel.sin(@double.neg_infinity), content="NaN")
/// }
/// ```
pub fn sin(x : Double) -> Double {
  if x.is_inf() || x.is_nan() {
    return @double.not_a_number
  }
  let y = [0.0, 0.0]
  let z = 0.0
  if x.abs() <= PI_OVER_4 {
    return __kernel_sin(x, z, 0)
  } else {
    let n = rem_pio2(x, y)
    match n & 3 {
      0 => __kernel_sin(y[0], y[1], 1)
      1 => __kernel_cos(y[0], y[1])
      2 => -__kernel_sin(y[0], y[1], 1)
      _ => -__kernel_cos(y[0], y[1])
    }
  }
}

///|
/// Calculates the cosine of a number in radians. Handles special cases and edge
/// conditions according to IEEE 754 standards.
///
/// Parameters:
///
/// * `x` : The angle in radians for which to calculate the cosine.
///
/// Returns the cosine of the angle `x`.
///
/// Example:
///
/// ```mbt check
/// test {
///   inspect(@scalar_numeric_kernel.cos(0.0), content="1")
///   inspect(@scalar_numeric_kernel.cos(2.5), content="-0.8011436155469337")
///   inspect(@scalar_numeric_kernel.cos(-3.141592653589793), content="-1") // -pi
///   inspect(@scalar_numeric_kernel.cos(-5.0), content="0.28366218546322625")
///   inspect(
///     @scalar_numeric_kernel.cos(31415926535897.9323846),
///     content="0.9999992690101899",
///   )
///   inspect(@scalar_numeric_kernel.cos(@double.not_a_number), content="NaN")
///   inspect(@scalar_numeric_kernel.cos(@double.infinity), content="NaN")
///   inspect(@scalar_numeric_kernel.cos(@double.neg_infinity), content="NaN")
/// }
/// ```
pub fn cos(x : Double) -> Double {
  if x.is_inf() || x.is_nan() {
    return @double.not_a_number
  }
  let y = [0.0, 0.0]
  let z = 0.0
  if x.abs() <= PI_OVER_4 {
    return __kernel_cos(x, z)
  } else {
    let n = rem_pio2(x, y)
    match n & 3 {
      0 => __kernel_cos(y[0], y[1])
      1 => -__kernel_sin(y[0], y[1], 1)
      2 => -__kernel_cos(y[0], y[1])
      _ => __kernel_sin(y[0], y[1], 1)
    }
  }
}
