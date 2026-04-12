"""
Rust-style Result type for explicit error handling.

Usage:
    from commons.result import Ok, Err, Result

    def divide(a: float, b: float) -> Result[float, str]:
        if b == 0:
            return Err("division by zero")
        return Ok(a / b)

    match divide(10, 3):
        case Ok(value=v):
            print(f"Got {v}")
        case Err(error=e):
            print(f"Error: {e}")
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Never


@dataclass(frozen=True, slots=True)
class Ok[T]:
    value: T

    def is_ok(self) -> bool:
        return True

    def is_err(self) -> bool:
        return False

    def map[U](self, fn: Callable[[T], U]) -> Ok[U]:
        return Ok(fn(self.value))

    def map_err(self, fn: Callable[..., Any]) -> Ok[T]:
        return self

    def and_then[U, E](self, fn: Callable[[T], Result[U, E]]) -> Result[U, E]:
        return fn(self.value)

    def unwrap(self) -> T:
        return self.value

    def unwrap_or(self, default: object) -> T:
        return self.value

    def unwrap_err(self) -> Never:
        raise ValueError(f"Called unwrap_err on Ok({self.value!r})")


@dataclass(frozen=True, slots=True)
class Err[E]:
    error: E

    def is_ok(self) -> bool:
        return False

    def is_err(self) -> bool:
        return True

    def map(self, fn: Callable[..., Any]) -> Err[E]:
        return self

    def map_err[F](self, fn: Callable[[E], F]) -> Err[F]:
        return Err(fn(self.error))

    def and_then(self, fn: Callable[..., Any]) -> Err[E]:
        return self

    def unwrap(self) -> Never:
        raise ValueError(f"Called unwrap on Err({self.error!r})")

    def unwrap_or[T](self, default: T) -> T:
        return default

    def unwrap_err(self) -> E:
        return self.error


type Result[T, E] = Ok[T] | Err[E]
