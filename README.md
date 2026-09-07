# Avocado TUI

Terminal-native Python scratchpad: edit a `.py` file on the left and see per-line results on the right.

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

- Ctrl+S: save
- Ctrl+O: open
- Ctrl+Q: quit
