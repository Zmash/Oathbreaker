import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
failed = False
for name in ("test.py", "test2.py", "test3.py", "test4.py", "test5.py"):
    result = subprocess.run([sys.executable, name], cwd=HERE, capture_output=True, text=True)
    output = result.stdout + result.stderr
    passes = output.count("PASS ")
    bad = result.returncode != 0 or "FAIL " in output
    failed = failed or bad
    print(f"{name}: {passes} passed{' FAILED' if bad else ''}")
    if bad:
        print(output[-1500:])
sys.exit(1 if failed else 0)
