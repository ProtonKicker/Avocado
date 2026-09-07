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

## Requirements

- Python 3.10+
- A terminal that supports mouse events (recommended if you want to drag the divider)

## Fast install (clone, install, delete)

This installs the `avocado` command into your user Python environment, then you can delete the cloned folder.

### macOS / Linux

```bash
git clone https://github.com/ProtonKicker/Avocado.git
cd Avocado
python3 -m pip install --user -U pip
python3 -m pip install --user .
cd ..
rm -rf Avocado

avocado --help
```

If `avocado` isn’t found, make sure `~/.local/bin` is on your PATH, then open a new terminal.

### Windows (PowerShell)

```powershell
git clone https://github.com/ProtonKicker/Avocado.git
cd Avocado
py -3 -m pip install --user -U pip
py -3 -m pip install --user .
cd ..
Remove-Item -Recurse -Force .\Avocado

avocado --help
```

If `avocado` isn’t found, open a new terminal window and try again.

## Quickstart (recommended, no venv activation)

The wrapper scripts will:

- Create a local `.venv` if missing
- Install this repo in editable mode into that `.venv`
- Launch Avocado using that `.venv`

### macOS / Linux

```bash
./avocado.sh examples/demo.py
```

### Windows (PowerShell)

```powershell
.\avocado.ps1 examples\demo.py
```

## Install (editable / dev)

This is the most flexible way to work on the code locally.

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

There are a few ways to run Avocado because Python environments differ across machines.

### Run (when your venv is active)

If you installed with `pip install -e .` and your virtual environment is active, use the `avocado` command (recommended).

macOS / Linux:

```bash
avocado examples/demo.py
```

Windows (PowerShell):

```powershell
avocado examples\demo.py
```

### Run (module entrypoint)

If you prefer not to rely on the console script, you can run the module directly:

macOS / Linux:

```bash
python -m avocado_tui.__main__ examples/demo.py
```

Windows (PowerShell):

```powershell
python -m avocado_tui.__main__ examples\demo.py
```

### Run (no activation)

If you don’t want to activate a virtual environment, use the wrapper script (`avocado.sh` / `avocado.ps1`).

macOS / Linux:

```bash
./avocado.sh examples/demo.py
```

Windows (PowerShell):

```powershell
.\avocado.ps1 examples\demo.py
```

## File Paths

- You can pass a file path as the first argument (e.g. `avocado demo.py`).
- If the file (or its parent directories) don’t exist yet, Avocado will create them.
- If you pass a directory, Avocado will error.

## Uninstall

This section has 2 steps:

1) Uninstall the package from your current Python environment (run once).

```bash
python -m pip uninstall -y avocado-tui
```

2) Optionally delete the local virtual environment folder (choose ONE command depending on your shell/OS).

macOS / Linux:

```bash
rm -rf .venv
```

Windows (PowerShell):

```powershell
Remove-Item -Recurse -Force .venv
```

## Keys

- Ctrl+Q: quit
- Ctrl+N: new file (prompts for a path)
- Ctrl+S: save
- Ctrl+R: toggle results panel

## Troubleshooting

- Dragging the divider doesn’t work: try a terminal with better mouse support (Windows Terminal, iTerm2, GNOME Terminal, Kitty).
- Installed new Python packages but Avocado can’t import them: restart Avocado so it picks up the updated `.venv`.
- `avocado` command not found: make sure your virtual environment is active and you installed with `python -m pip install -e .`.

## Notes

- Evaluation is line-by-line, so multi-line Python blocks (e.g. `def`, `for`, `if` with indented bodies) won’t behave like a normal Python file execution.
- By default, evaluation stops at the first error and later lines show `Skipped`.
