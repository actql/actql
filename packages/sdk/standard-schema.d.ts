// Compatible Standard Schema V1 declarations, adapted from
// https://github.com/standard-schema/standard-schema (MIT).
// Copyright (c) 2024 Colin McDonnell. See STANDARD-SCHEMA-LICENSE.
// Kept in the public package so consumers need no runtime schema dependency.
export interface StandardSchemaV1<Input = unknown, Output = Input> {
  readonly '~standard': StandardSchemaV1.Props<Input, Output>;
}
export declare namespace StandardSchemaV1 {
  export interface Props<Input = unknown, Output = Input> {
    readonly version: 1;
    readonly vendor: string;
    readonly validate: (value: unknown, options?: Options | undefined) =>
      Result<Output> | Promise<Result<Output>>;
    readonly types?: Types<Input, Output> | undefined;
  }
  export interface Types<Input = unknown, Output = Input> {
    readonly input: Input;
    readonly output: Output;
  }
  export interface Options {
    readonly libraryOptions?: Record<string, unknown> | undefined;
  }
  export type Result<Output> = SuccessResult<Output> | FailureResult;
  export interface SuccessResult<Output> {
    readonly value: Output;
    readonly issues?: undefined;
  }
  export interface FailureResult {
    readonly issues: ReadonlyArray<Issue>;
  }
  export interface Issue {
    readonly message: string;
    readonly path?: ReadonlyArray<PropertyKey | PathSegment> | undefined;
  }
  export interface PathSegment {
    readonly key: PropertyKey;
  }
  export type InferInput<Schema extends StandardSchemaV1> =
    NonNullable<Schema['~standard']['types']>['input'];
  export type InferOutput<Schema extends StandardSchemaV1> =
    NonNullable<Schema['~standard']['types']>['output'];
}
