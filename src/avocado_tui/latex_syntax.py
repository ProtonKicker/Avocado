from __future__ import annotations

import re

from .matlab_syntax import MathSyntaxError


_LATEX_OPERATOR_CALLS = {
    r"\cdot": "latex_cdot",
    r"\times": "latex_times",
}
_LATEX_MARKER_RE = re.compile(
    r"\\"
    r"|(?<![A-Za-z_])(?:frac|sqrt|sum|prod|alpha|beta|gamma|theta|pi)\s*[\(\{_]"
    r"|(?:\d[A-Za-z_]|[)\}][(A-Za-z_])"
)
_WRAPPER_COMMANDS = (
    "vec",
    "mathbf",
    "mathrm",
    "mathit",
    "mathsf",
    "boldsymbol",
    "operatorname",
)


def looks_like_latex_syntax(line: str) -> bool:
    text = line.strip()
    if not text:
        return False
    return bool(_LATEX_MARKER_RE.search(text))


def translate_latex_line(line: str) -> str:
    text = line.strip()
    if not text:
        raise MathSyntaxError("Empty expression")
    if not looks_like_latex_syntax(text):
        raise MathSyntaxError("Not a LaTeX-like expression")

    assign_split = _split_top_level_assignment(text)
    if assign_split is not None:
        lhs, rhs = assign_split
        return f"{_sanitize_identifier(lhs)} = {_translate_latex_expr(rhs)}"
    return _translate_latex_expr(text)


def _translate_latex_expr(expr: str) -> str:
    text = _normalize_latex_source(expr)
    for operator, call_name in _LATEX_OPERATOR_CALLS.items():
        split = _split_top_level_operator(text, operator)
        if split is not None:
            left, right = split
            return f"{call_name}({_translate_latex_expr(left)}, {_translate_latex_expr(right)})"

    try:
        from sympy.parsing.latex import parse_latex
    except ImportError as exc:  # pragma: no cover - dependency issue at runtime
        raise MathSyntaxError("LaTeX support requires sympy and antlr4-python3-runtime") from exc

    try:
        parsed = parse_latex(text)
        return _AvocadoNumPyPrinter().doprint(parsed)
    except Exception:
        fallback = _translate_legacy_structured_commands(text)
        if fallback != text:
            return fallback
        raise MathSyntaxError(f"Unable to parse LaTeX expression: {expr}")


class _AvocadoNumPyPrinter:
    def __init__(self) -> None:
        from sympy.printing.numpy import NumPyPrinter

        class _Printer(NumPyPrinter):
            def _print_Sum(self, expr) -> str:  # type: ignore[override]
                function = self._print(expr.function)
                limits = expr.limits
                if len(limits) != 1:
                    raise MathSyntaxError("Only single-index LaTeX sums are supported")
                symbol, start, stop = limits[0]
                var_name = self._print(symbol)
                start_code = self._print(start)
                stop_code = self._print(stop)
                return (
                    "builtins.sum("
                    f"({function} for {var_name} in range(int({start_code}), int({stop_code}) + 1))"
                    ")"
                )

            def _print_Product(self, expr) -> str:  # type: ignore[override]
                function = self._print(expr.function)
                limits = expr.limits
                if len(limits) != 1:
                    raise MathSyntaxError("Only single-index LaTeX products are supported")
                symbol, start, stop = limits[0]
                var_name = self._print(symbol)
                start_code = self._print(start)
                stop_code = self._print(stop)
                return (
                    "math.prod("
                    f"({function} for {var_name} in range(int({start_code}), int({stop_code}) + 1))"
                    ")"
                )

        self._printer = _Printer()

    def doprint(self, expr) -> str:
        return self._printer.doprint(expr)


def _normalize_latex_source(expr: str) -> str:
    text = expr.strip()
    text = text.replace(r"\left", "").replace(r"\right", "")
    text = _strip_wrapper_commands(text)
    text = _normalize_legacy_frac_calls(text)
    return text


def _strip_wrapper_commands(text: str) -> str:
    pattern = re.compile(
        rf"\\(?:{'|'.join(_WRAPPER_COMMANDS)})\s*\{{([^{{}}]+)\}}"
    )
    while True:
        updated = pattern.sub(r"\1", text)
        if updated == text:
            return text
        text = updated


def _normalize_legacy_frac_calls(text: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(text):
        if (
            text.startswith("frac", i)
            and (i == 0 or text[i - 1] != "\\")
            and _is_command_boundary(text, i, i + 4)
        ):
            numerator, after_numerator = _parse_group(text, i + 4)
            denominator, after_denominator = _parse_group(text, after_numerator)
            out.append(
                r"\frac{" + _normalize_legacy_frac_calls(numerator) + "}{" + _normalize_legacy_frac_calls(denominator) + "}"
            )
            i = after_denominator
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def _translate_legacy_structured_commands(text: str) -> str:
    out: list[str] = []
    i = 0
    changed = False
    while i < len(text):
        if text.startswith(r"\frac", i):
            numerator, after_numerator = _parse_group(text, i + len(r"\frac"))
            denominator, after_denominator = _parse_group(text, after_numerator)
            out.append(
                f"(({_translate_latex_expr(numerator)})/({_translate_latex_expr(denominator)}))"
            )
            i = after_denominator
            changed = True
            continue
        if text.startswith(r"\sqrt", i):
            value, after_value = _parse_group(text, i + len(r"\sqrt"))
            out.append(f"sqrt({_translate_latex_expr(value)})")
            i = after_value
            changed = True
            continue
        out.append(text[i])
        i += 1
    return "".join(out) if changed else text


def _split_top_level_assignment(text: str) -> tuple[str, str] | None:
    depth = 0
    for index, ch in enumerate(text):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "=" and depth == 0:
            if index > 0 and text[index - 1] in "<>!=":
                continue
            if index + 1 < len(text) and text[index + 1] == "=":
                continue
            lhs = text[:index].strip()
            rhs = text[index + 1 :].strip()
            if lhs and rhs:
                return lhs, rhs
    return None


def _split_top_level_operator(text: str, operator: str) -> tuple[str, str] | None:
    depth = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if depth == 0 and text.startswith(operator, i):
            lhs = text[:i].strip()
            rhs = text[i + len(operator) :].strip()
            if lhs and rhs:
                return lhs, rhs
        i += 1
    return None


def _sanitize_identifier(text: str) -> str:
    value = text.strip()
    value = re.sub(r"\\([A-Za-z]+)", r"\1", value)
    value = re.sub(r"_\{([^{}]+)\}", r"_\1", value)
    value = value.replace("{", "").replace("}", "").replace(" ", "")
    if not re.fullmatch(r"[A-Za-z_]\w*", value):
        raise MathSyntaxError(f"Unsupported LaTeX assignment target: {text}")
    return value


def _is_command_boundary(text: str, start: int, end: int) -> bool:
    before_ok = start == 0 or not (text[start - 1].isalnum() or text[start - 1] == "_")
    after_ok = end >= len(text) or text[end].isspace() or text[end] in "({"
    return before_ok and after_ok


def _parse_group(text: str, start: int) -> tuple[str, int]:
    index = start
    while index < len(text) and text[index].isspace():
        index += 1
    if index >= len(text) or text[index] not in "({":
        raise MathSyntaxError("Expected grouped LaTeX argument")

    opener = text[index]
    closer = ")" if opener == "(" else "}"
    end = _find_matching(text, index, opener, closer)
    if end == -1:
        raise MathSyntaxError("Unclosed LaTeX group")
    return text[index + 1 : end], end + 1


def _find_matching(text: str, start: int, opener: str, closer: str) -> int:
    depth = 0
    for index in range(start, len(text)):
        ch = text[index]
        if ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth == 0:
                return index
    return -1
