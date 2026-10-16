"""Public sync/async type inference for model and custom row validators."""
from typing import Any, Literal, assert_type
from pydantic import BaseModel, TypeAdapter
from actql_sdk import AsyncResult, Result
from actql import AsyncResult as ProductAsyncResult, Result as ProductResult

class Row(BaseModel):
    n: int

class Validator:
    def validate_python(self, value: Any, *, strict: Literal[True]) -> str:
        if not strict or type(value) is not dict or type(value.get('n')) is not int:
            raise ValueError('Expected an integer n')
        return str(value['n'])

def sync(result: Result, product: ProductResult) -> None:
    assert_type(result.all(schema=Row), list[Row])
    assert_type(result.all(schema=TypeAdapter(Row)), list[Row])
    assert_type(product.all(schema=Validator()), list[str])
    with result.rows(schema=Row) as reader:
        assert_type(next(reader), Row)

async def asynchronous(result: AsyncResult, product: ProductAsyncResult) -> None:
    assert_type(await result.all(schema=Row), list[Row])
    assert_type(await result.all(schema=TypeAdapter(Row)), list[Row])
    assert_type(await product.all(schema=Validator()), list[str])
    async with result.rows(schema=Row) as reader:
        assert_type(await anext(reader), Row)
