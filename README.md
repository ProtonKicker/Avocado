# Avocado's Constant

Avocado is a terminal-native math notebook written in Zig. Edit a `.txt` document on the left and see per-line results on the right.

## Features

- Two-line banner with the app name on the left and the current document path on the right.
- Mouse-draggable results divider with per-file width saved in `~/.avocado/config.json`.
- Full-width save and new-file prompt with `.txt` normalization.
- Relative save paths resolved from the directory where Avocado was launched.
- Line-by-line evaluator with practical math-first syntax.
- Mixed grammar support in one document:
  - natural math such as `sin(pi / 2)`, `e^x`, `ln(10)`
  - MATLAB-like ranges such as `1:1:10`
  - MATLAB-style matrices such as `[1 2 3; 4 5 6]`
  - Python-style assignments, lists, and indexing when useful

## Requirements

- Zig 0.16+
- A terminal with mouse support if you want to drag the divider
- On macOS / Linux, the install script also expects `curl` and `unzip`

## Fast install

The install scripts download the repo, build the Zig executable, and place an `avocado` launcher in your user bin directory.

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/ProtonKicker/Avocado/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ProtonKicker/Avocado/main/install.ps1 | iex
```

## Local development

### Build tests

```bash
zig build test
```

### Build app

```bash
zig build
```

### Run app

```bash
zig build run -- examples/demo.txt
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

- Evaluation is line-by-line, so multi-line Python blocks such as `def`, `for`, or `if` with indented bodies do not behave like a full Python file.
- After the first evaluation error, later lines show `Skipped`.
- The current Zig rewrite keeps the existing minimalist notebook workflow, not full Python or full MATLAB compatibility.
