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

    aggregate = _translate_substack_aggregate(text)
    if aggregate is not None:
        return aggregate

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


def _translate_substack_aggregate(text: str) -> str | None:
    if text.startswith(r"\sum"):
        aggregate_name = "builtins.sum"
        index = len(r"\sum")
    elif text.startswith(r"\prod"):
        aggregate_name = "math.prod"
        index = len(r"\prod")
    else:
        return None

    lower_text: str | None = None
    upper_text: str | None = None
    while index < len(text):
        while index < len(text) and text[index].isspace():
            index += 1
        if index >= len(text) or text[index] not in "_^":
            break
        marker = text[index]
        script_text, index = _parse_script_argument(text, index + 1)
        if marker == "_":
            lower_text = script_text
        else:
            upper_text = script_text

    if lower_text is None or not lower_text.lstrip().startswith(r"\substack"):
        return None

    body = text[index:].strip()
    if not body:
        raise MathSyntaxError("Expected a LaTeX expression after sum/product limits")

    clause_parts = _build_substack_clauses(lower_text, upper_text)
    body_code = _translate_latex_expr(body)
    generator = f"({body_code} {' '.join(clause_parts)})"
    return f"{aggregate_name}({generator})"


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


def _build_substack_clauses(lower_text: str, shared_upper: str | None) -> list[str]:
    content, _ = _parse_command_group(lower_text.strip(), r"\substack")
    lines = _split_substack_lines(content)
    clauses: list[str] = []
    binder_count = 0
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        binding = _parse_substack_binding(line, shared_upper)
        if binding is not None:
            clauses.append(binding)
            binder_count += 1
            continue
        clauses.append(f"if {_translate_latex_condition(line)}")

    if binder_count == 0:
        raise MathSyntaxError(r"\substack requires at least one index binding")
    return clauses


def _parse_substack_binding(line: str, shared_upper: str | None) -> str | None:
    equal_match = re.fullmatch(r"(.+?)\s*=\s*(.+)", line)
    if equal_match is not None:
        if shared_upper is None:
            raise MathSyntaxError(
                r"\substack bindings of the form i=1 require an outer upper bound such as ^{n}"
            )
        var_name = _sanitize_identifier(equal_match.group(1))
        start_code = _translate_latex_expr(equal_match.group(2))
        stop_code = _translate_latex_expr(shared_upper)
        return f"for {var_name} in range(int({start_code}), int({stop_code}) + 1)"

    normalized = _normalize_relation_operators(line)
    lower_chain = re.fullmatch(r"(.+?)\s*<=\s*(.+?)\s*<=\s*(.+)", normalized)
    if lower_chain is not None:
        start_code = _translate_latex_expr(lower_chain.group(1))
        var_name = _sanitize_identifier(lower_chain.group(2))
        stop_code = _translate_latex_expr(lower_chain.group(3))
        return f"for {var_name} in range(int({start_code}), int({stop_code}) + 1)"

    upper_chain = re.fullmatch(r"(.+?)\s*>=\s*(.+?)\s*>=\s*(.+)", normalized)
    if upper_chain is not None:
        start_code = _translate_latex_expr(upper_chain.group(1))
        var_name = _sanitize_identifier(upper_chain.group(2))
        stop_code = _translate_latex_expr(upper_chain.group(3))
        return f"for {var_name} in range(int({start_code}), int({stop_code}) - 1, -1)"

    return None


def _translate_latex_condition(text: str) -> str:
    normalized = _normalize_relation_operators(text)
    normalized = re.sub(r"(?<![<>=!])=(?!=)", "==", normalized)
    parts = re.split(r"(<=|>=|!=|==|<|>)", normalized)
    if len(parts) == 1:
        return _translate_latex_expr(normalized)
    translated_parts: list[str] = []
    for index, part in enumerate(parts):
        stripped = part.strip()
        if not stripped:
            continue
        if index % 2 == 1:
            translated_parts.append(stripped)
        else:
            translated_parts.append(_translate_latex_expr(stripped))
    return " ".join(translated_parts)


def _normalize_relation_operators(text: str) -> str:
    return (
        text.replace(r"\leq", "<=")
        .replace(r"\le", "<=")
        .replace(r"\geq", ">=")
        .replace(r"\ge", ">=")
        .replace(r"\neq", "!=")
        .replace(r"\ne", "!=")
    )


def _parse_command_group(text: str, command: str) -> tuple[str, int]:
    if not text.startswith(command):
        raise MathSyntaxError(f"Expected {command}")
    return _parse_group(text, len(command))


def _split_substack_lines(text: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if ch in "({":
            depth += 1
        elif ch in ")}":
            depth -= 1
        if depth == 0 and text.startswith(r"\\", i):
            parts.append("".join(current))
            current = []
            i += 2
            continue
        current.append(ch)
        i += 1
    parts.append("".join(current))
    return parts


def _parse_script_argument(text: str, start: int) -> tuple[str, int]:
    index = start
    while index < len(text) and text[index].isspace():
        index += 1
    if index >= len(text):
        raise MathSyntaxError("Expected LaTeX script argument")
    if text[index] in "({":
        return _parse_group(text, index)
    if text[index] == "\\":
        end = index + 1
        while end < len(text) and text[end].isalpha():
            end += 1
        return text[index:end], end
    return text[index], index + 1


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
