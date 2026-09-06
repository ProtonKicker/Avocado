from __future__ import annotations

import ast
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class EvalOutput:
    lines: list[str]
    namespace: dict[str, Any]


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

        try:
            mod = ast.parse(line, mode="exec")
            if len(mod.body) != 1:
                code = compile(mod, "<avocado>", "exec")
                exec(code, ns, ns)
                outputs.append("")
                continue

            stmt = mod.body[0]
            if isinstance(stmt, ast.Expr):
                expr_code = compile(ast.Expression(stmt.value), "<avocado>", "eval")
                value = eval(expr_code, ns, ns)
                outputs.append(repr(value).replace("\n", "\\n"))
                continue

            assigned = _assigned_names(stmt)
            code = compile(mod, "<avocado>", "exec")
            exec(code, ns, ns)

            if len(assigned) == 1 and assigned[0] in ns:
                outputs.append(repr(ns[assigned[0]]).replace("\n", "\\n"))
            else:
                outputs.append("")
        except Exception as e:
            outputs.append(f"Error: {type(e).__name__}: {e}".replace("\n", "\\n"))
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
