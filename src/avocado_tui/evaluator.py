from __future__ import annotations

import ast
import contextlib
import io
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class EvalOutput:
    lines: list[str]
    namespace: dict[str, Any]


def _squash_stream_text(text: str) -> str:
    return text.rstrip("\r\n").replace("\r\n", "\n").replace("\n", "\\n")


def _combine_stream_and_value(*parts: str) -> str:
    return " | ".join(p for p in parts if p)



def _assigned_names(stmt: ast.stmt) -> list[str]:
    if isinstance(stmt, ast.Assign):
        names: list[str] = []
        for t in stmt.targets:
            if isinstance(t, ast.Name):
                names.append(t.id)
        return names
    if isinstance(stmt, ast.AnnAssign):
        if isinstance(stmt.target, ast.Name):
            return [stmt.target.id]
        return []
    if isinstance(stmt, ast.AugAssign):
        if isinstance(stmt.target, ast.Name):
            return [stmt.target.id]
        return []
    return []


def evaluate_source_linewise(source: str, *, stop_on_error: bool = True) -> EvalOutput:
    ns: dict[str, Any] = {}
    outputs: list[str] = []

    error_seen = False
    for line in source.split("\n"):
        if error_seen and stop_on_error:
            outputs.append("Skipped")
            continue

        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            outputs.append("")
            continue

        stdout_io = io.StringIO()
        stderr_io = io.StringIO()
        try:
            with contextlib.redirect_stdout(stdout_io), contextlib.redirect_stderr(
                stderr_io
            ):
                mod = ast.parse(line, mode="exec")
                if len(mod.body) != 1:
                    code = compile(mod, "<avocado>", "exec")
                    exec(code, ns, ns)
                    outputs.append(
                        _combine_stream_and_value(
                            _squash_stream_text(stdout_io.getvalue()),
                            _squash_stream_text(stderr_io.getvalue()),
                        )
                    )
                    continue

                stmt = mod.body[0]
                if isinstance(stmt, ast.Expr):
                    expr_code = compile(ast.Expression(stmt.value), "<avocado>", "eval")
                    value = eval(expr_code, ns, ns)

                    stdout_text = _squash_stream_text(stdout_io.getvalue())
                    stderr_text = _squash_stream_text(stderr_io.getvalue())
                    value_text = repr(value).replace("\n", "\\n")
                    if value is None and stdout_text:
                        outputs.append(_combine_stream_and_value(stdout_text, stderr_text))
                    else:
                        outputs.append(
                            _combine_stream_and_value(stdout_text, stderr_text, value_text)
                        )
                    continue

                assigned = _assigned_names(stmt)
                code = compile(mod, "<avocado>", "exec")
                exec(code, ns, ns)

                stdout_text = _squash_stream_text(stdout_io.getvalue())
                stderr_text = _squash_stream_text(stderr_io.getvalue())
                if len(assigned) == 1 and assigned[0] in ns:
                    value_text = repr(ns[assigned[0]]).replace("\n", "\\n")
                    outputs.append(
                        _combine_stream_and_value(stdout_text, stderr_text, value_text)
                    )
                else:
                    outputs.append(_combine_stream_and_value(stdout_text, stderr_text))
        except Exception as e:
            stdout_text = _squash_stream_text(stdout_io.getvalue())
            stderr_text = _squash_stream_text(stderr_io.getvalue())
            err_text = _squash_stream_text(f"{type(e).__name__}: {e}")
            outputs.append(_combine_stream_and_value(stdout_text, stderr_text, err_text))
            error_seen = True

    return EvalOutput(lines=outputs, namespace=ns)


def truncate_lines(lines: list[str], width: int) -> list[str]:
    if width <= 0:
        return ["" for _ in lines]

    out: list[str] = []
    for s in lines:
        if len(s) <= width:
            out.append(s)
            continue
        if width <= 1:
            out.append("…")
            continue
        out.append(s[: width - 1] + "…")
    return out
