# Avocado's Constant

Terminal-native math notebook: edit a `.txt` document on the left and see per-line results on the right. The evaluator is math-first, while still accepting Python and MATLAB-like lines in the same document.

The app backend is still Python-based: the TUI runs on `Textual`, the runtime uses Python plus `numpy`, and the mixed-grammar evaluator adds a lightweight MATLAB-like syntax layer on top of the Python engine.

## Features

- Two-line banner with `Avocado's Constant` on the left and the current document path on the right.
- Click-to-copy banner path behavior:
  - click the filename to copy just the filename,
  - click the directory to copy the full path.
- Mouse-draggable vertical divider; width is stored in `~/.avocado/config.json`.
- `.txt`-only save workflow in the UI for mixed math notes instead of `.py` scratch files.
- Per-line evaluation with captured `stdout` / `stderr`.
- Mixed grammar support in one document:
  - natural math such as `sin(pi/2)`, `e^x`, `ln(10)`,
  - MATLAB-like ranges such as `1:1:10`,
  - MATLAB-style matrices such as `[1 2 3; 4 5 6]`,
  - Python assignments and expressions when useful.

## Requirements

- Python 3.10+
- A terminal with mouse support if you want to drag the divider

## Fast install

This downloads the repo as a zip, installs it into a dedicated virtual environment, and drops an `avocado` launcher into your user bin directory.

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/ProtonKicker/Avocado/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ProtonKicker/Avocado/main/install.ps1 | iex
```

## Editable install

### macOS / Linux

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -e .
```

### Windows (PowerShell)

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -U pip
python -m pip install -e .
```

## Run

### With the `avocado` command

```bash
avocado examples/demo.txt
```

### Module entrypoint

```bash
python -m avocado_tui.__main__ examples/demo.txt
```

### Wrapper scripts

macOS / Linux:

```bash
./avocado.sh examples/demo.txt
```

Windows (PowerShell):

```powershell
.\avocado.ps1 examples\demo.txt
```

## File behavior

- Passing a missing path creates a new document.
- Missing extensions are normalized to `.txt` for new documents.
- Saving from the UI always writes `.txt`.
- Missing parent directories are created automatically.
- Relative paths resolve from the directory where `avocado` was launched.

## Example document

The bundled demo document shows a mixed notebook:

```text
x = 3
sin(pi / 2)
1:1:5
[1 2 3; 4 5 6]
e^x
```

## Keys

- Ctrl+Q: quit
- Ctrl+N: new document
- Ctrl+S: save document
- Ctrl+R: toggle results panel

## Notes

- Evaluation is line-by-line, so multi-line Python blocks such as `def`, `for`, or `if` with indented bodies still do not behave like a full Python file.
- By default, evaluation stops at the first error and later lines show `Skipped`.
- Phase 1 intentionally focuses on practical math aliases, ranges, and matrices instead of full LaTeX or full MATLAB compatibility.
