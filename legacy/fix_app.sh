#!/bin/bash
# Script to fix absolute paths and potential issues in the app bundle resources
# Run this if the app doesn't start

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 1. Clean up potential pyc files that could cause issues
find "$DIR" -name "*.pyc" -delete

# 2. Ensure all __init__.py files are present
touch "$DIR/core/__init__.py"
touch "$DIR/ui/__init__.py"
touch "$DIR/ui/tabs/__init__.py"
touch "$DIR/features/__init__.py"

# 3. Add a wrapper that shows the error if it fails (for debugging on the user side)
cat << 'WRAPP' > "$DIR/debug_launcher.py"
# -*- coding: utf-8 -*-
import os, sys, traceback

try:
    base = os.path.dirname(os.path.abspath(__file__))
    if base not in sys.path:
        sys.path.insert(0, base)
    import main
    app = main.App()
    app.mainloop()
except Exception as e:
    import Tkinter as tk
    import tkMessageBox
    root = tk.Tk()
    root.withdraw()
    err = traceback.format_exc()
    tkMessageBox.showerror("Startup Error", "The application failed to start.\n\nError:\n" + err)
    with open(os.path.expanduser("~/Desktop/iGeniusAI_error.txt"), "w") as f:
        f.write(err)
WRAPP

echo "Fixed. Try running build_app.sh again."
