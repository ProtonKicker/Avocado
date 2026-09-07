# Avocado TUI

Terminal-native Python scratchpad: edit a `.py` file on the left and see per-line results on the right. Results update automatically as you type.

## Features

- Two-line banner: `Avocado` on the left, file path on the right (filename highlighted). When the window is narrow, the directory is hidden to keep the filename visible on the first line.
- Click-to-copy on the banner:
  - Click the filename to copy just the filename
  - Click the directory part to copy the full path
- Mouse-draggable vertical divider to resize the results panel; the width is saved in `~/.avocado/config.json` per file path.
- Per-line evaluator with captured `stdout`/`stderr`:
  - `print(...)` output shows up in the results panel
  - Multi-line output is flattened using `\n` so results stay aligned with editor lines
- Prelude imports before your code:
  - `import math` and `from math import *`
  - `import numpy as np`

## Install (dev)

```bash
python -m venv .venv
source .venv/bin/activate  # macOS/Linux
# .\.venv\Scripts\activate  # Windows PowerShell
python -m pip install -U pip
python -m pip install -e .
```

## Run

```bash
./avocado.sh examples/demo.py
```

## Run (Windows PowerShell)

```powershell
.\avocado.ps1 examples\demo.py
```

## Keys

- Ctrl+Q: quit
- Ctrl+N: new file (prompts for a path)
- Ctrl+S: save
- Ctrl+O: open (prompts for a path)
- Ctrl+R: toggle results panel

## Notes

- Evaluation is line-by-line, so multi-line Python blocks (e.g. `def`, `for`, `if` with indented bodies) won’t behave like a normal Python file execution.
- By default, evaluation stops at the first error and later lines show `Skipped`.
