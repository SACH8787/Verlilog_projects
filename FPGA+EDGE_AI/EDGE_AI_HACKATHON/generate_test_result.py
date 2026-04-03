"""
generate_test_samples.py
========================
Extracts real ECG samples from the PTB dataset and tests them on the Basys3.

Run this in the same folder as your test_fpga.py and .mem files.
Requires: pip install kagglehub pandas pyserial numpy
"""

import subprocess
subprocess.run(["pip", "install", "kagglehub", "pandas", "pyserial", "-q"],
               capture_output=True)

import os, random, time
import numpy as np
import pandas as pd
import serial
import kagglehub
from sklearn.utils import resample

# -----------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------
COM_PORT         = 'COM4'
BAUD_RATE        = 115200
INTER_BYTE_DELAY = 0.001   # increase to 0.002 if bytes get dropped
N_SAMPLES        = 20      # how many samples to test (10 normal + 10 abnormal)
SEED             = 42
OUTPUT_FOLDER    = "ecg_samples"   # folder where .mem files are saved
# -----------------------------------------------------------------------

random.seed(SEED)
np.random.seed(SEED)

os.makedirs(OUTPUT_FOLDER, exist_ok=True)

def to_hex8(q):
    q = int(q)
    return f"{(q if q >= 0 else 256 + q):02X}"

def signal_to_mem(signal_float, fname):
    """Normalize signal to [-1,+1], quantize to int8, save as hex .mem file."""
    sig = np.array(signal_float, dtype=np.float32)
    sig = sig / (np.max(np.abs(sig)) + 1e-8)
    with open(fname, "w") as f:
        for v in sig[:128]:
            q = max(-128, min(127, int(round(float(v) * 127.0))))
            f.write(to_hex8(q) + "\n")

def load_mem_bytes(filepath):
    """Load .mem file as list of raw byte values (0-255)."""
    vals = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line:
                v = int(line, 16)
                vals.append(v)
    assert len(vals) == 128, f"Expected 128 bytes, got {len(vals)}"
    return vals

# ================================================================
# STEP 1: Load PTB dataset
# ================================================================
print("=" * 56)
print("  ECG Batch Tester — Real PTB Dataset Samples")
print("=" * 56)
print("\n[1] Loading PTB dataset from Kaggle...")

path = kagglehub.dataset_download("shayanfazeli/heartbeat")
normal_raw   = pd.read_csv(path + "/ptbdb_normal.csv",
                            header=None).iloc[:, 0:128].values
abnormal_raw = pd.read_csv(path + "/ptbdb_abnormal.csv",
                            header=None).iloc[:, 0:128].values

print(f"    Loaded {len(normal_raw)} normal samples")
print(f"    Loaded {len(abnormal_raw)} abnormal samples")

# Pick random samples (skip first few which were used for training)
n_half = N_SAMPLES // 2
n_idx = random.sample(range(100, len(normal_raw)),   n_half)
a_idx = random.sample(range(100, len(abnormal_raw)), n_half)

normal_samples   = [normal_raw[i]   for i in n_idx]
abnormal_samples = [abnormal_raw[i] for i in a_idx]

print(f"\n    Selected {n_half} normal + {n_half} abnormal samples for testing")

# ================================================================
# STEP 2: Save as .mem files
# ================================================================
print(f"\n[2] Saving samples to '{OUTPUT_FOLDER}/' folder...")

sample_files = []   # list of (filepath, true_label, sample_index)

for idx, sig in enumerate(normal_samples):
    fname = os.path.join(OUTPUT_FOLDER, f"normal_{idx:03d}.mem")
    signal_to_mem(sig, fname)
    sample_files.append((fname, "NORMAL", idx))

for idx, sig in enumerate(abnormal_samples):
    fname = os.path.join(OUTPUT_FOLDER, f"abnormal_{idx:03d}.mem")
    signal_to_mem(sig, fname)
    sample_files.append((fname, "ABNORMAL", idx))

# Shuffle so normal/abnormal are interleaved
random.shuffle(sample_files)
print(f"    Saved {len(sample_files)} .mem files")

# ================================================================
# STEP 3: Test on board
# ================================================================
print(f"\n[3] Opening serial port {COM_PORT}...")
try:
    ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
    time.sleep(0.5)
    print(f"    Connected at {BAUD_RATE} baud")
except serial.SerialException as e:
    print(f"\n    ERROR: {e}")
    print("    Check COM port number and that Vivado Hardware Manager is closed.")
    exit(1)

results = []
passes = 0
fails  = 0

print(f"\n[4] Running {len(sample_files)} tests on board...")
print("    For each test: reset board, press Enter, read LEDs.\n")

for test_num, (filepath, true_label, idx) in enumerate(sample_files, 1):
    sample_bytes = load_mem_bytes(filepath)
    short_name = os.path.basename(filepath)

    print(f"  {'='*52}")
    print(f"  Test {test_num:2d}/{len(sample_files)}: {short_name}  (true: {true_label})")
    print(f"  {'='*52}")
    print("  1. Press CENTRE BUTTON to reset board")
    print("  2. Wait for ALL LEDs to go OFF")
    input("  3. Press ENTER when ready...")

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    for byte_val in sample_bytes:
        ser.write(bytes([byte_val]))
        if INTER_BYTE_DELAY > 0:
            time.sleep(INTER_BYTE_DELAY)

    time.sleep(0.05)

    print()
    print("  READ LEDS:  LED[15]=ABNORMAL  LED[0]=NORMAL  LED[7]=DONE")
    led15 = input("  LED[15] ABNORMAL lit? [y/n]: ").strip().lower() == 'y'
    led0  = input("  LED[0]  NORMAL   lit? [y/n]: ").strip().lower() == 'y'
    led7  = input("  LED[7]  DONE     lit? [y/n]: ").strip().lower() == 'y'

    if not led7:
        got = "TIMEOUT"
        passed = False
        print("  WARNING: LED[7] not lit — board may not have completed processing")
    else:
        got = "ABNORMAL" if led15 else "NORMAL"
        passed = (got == true_label)

    status = "PASS ✓" if passed else "FAIL ✗"
    print(f"\n  {status}  Got: {got}   Expected: {true_label}")

    results.append({
        "test":     test_num,
        "file":     short_name,
        "expected": true_label,
        "got":      got,
        "pass":     passed
    })

    if passed: passes += 1
    else:      fails  += 1

    # Running accuracy
    total_so_far = passes + fails
    print(f"  Running accuracy: {passes}/{total_so_far} = {100*passes/total_so_far:.1f}%\n")

ser.close()

# ================================================================
# STEP 4: Final report
# ================================================================
print("\n" + "=" * 56)
print("  FINAL RESULTS")
print("=" * 56)

normal_results   = [r for r in results if r["expected"] == "NORMAL"]
abnormal_results = [r for r in results if r["expected"] == "ABNORMAL"]
n_pass = sum(1 for r in normal_results   if r["pass"])
a_pass = sum(1 for r in abnormal_results if r["pass"])

print(f"\n  Normal   samples:  {n_pass}/{len(normal_results)} correct  "
      f"({100*n_pass/max(1,len(normal_results)):.1f}%)")
print(f"  Abnormal samples:  {a_pass}/{len(abnormal_results)} correct  "
      f"({100*a_pass/max(1,len(abnormal_results)):.1f}%)")
print(f"\n  Overall:  {passes}/{len(results)} = {100*passes/len(results):.1f}% balanced accuracy")

print("\n  Individual results:")
print(f"  {'#':>3}  {'File':30}  {'Expected':10}  {'Got':10}  {'Result':8}")
print("  " + "-"*66)
for r in results:
    status = "PASS ✓" if r["pass"] else "FAIL ✗"
    print(f"  {r['test']:>3}  {r['file']:30}  {r['expected']:10}  {r['got']:10}  {status}")

print()
if passes == len(results):
    print("  Perfect score! Your FPGA classifier is working flawlessly.")
elif passes / len(results) >= 0.85:
    print(f"  Excellent — {100*passes/len(results):.1f}% hardware accuracy matches")
    print("  the 86.53% expected from training.")
elif passes / len(results) >= 0.70:
    print(f"  Good result — {100*passes/len(results):.1f}% accuracy.")
else:
    print(f"  Below expected — check byte ordering and reset procedure.")

print()
print(f"  All test .mem files saved in '{OUTPUT_FOLDER}/' folder")
print(f"  for re-testing without re-downloading the dataset.")
print("=" * 56)