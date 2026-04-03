"""
test_fpga.py  -  UART test script for Basys3 ECG Classifier
=============================================================
Usage: python test_fpga.py
Change COM_PORT below to match your system.
"""

import serial
import time
import os

# -----------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------
COM_PORT         = 'COM4'      # Change if needed (check Device Manager)
BAUD_RATE        = 115200      # Must match CLKS_PER_BIT=868 in uart_rx.v
INTER_BYTE_DELAY = 0.001       # 1ms between bytes. Increase to 0.002 if failing.

NORMAL_MEM   = "test_ecg_normal.mem"
ABNORMAL_MEM = "test_ecg_abnormal.mem"
# -----------------------------------------------------------------------


def load_mem_file(filepath):
    """Read hex .mem file -> list of 128 raw byte values (0-255)."""
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Cannot find '{filepath}'.")
    values = []
    with open(filepath, 'r') as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                val = int(line, 16)
                assert 0 <= val <= 255
                values.append(val)
            except Exception:
                raise ValueError(f"Bad value on line {lineno}: '{line}'")
    if len(values) != 128:
        raise ValueError(f"{filepath}: expected 128 values, got {len(values)}")
    return values


def send_ecg_sample(ser, byte_values, label, expected_result):
    """
    Send 128 raw bytes to FPGA, then ask user to read LEDs.
    CRITICAL: Board must be fully reset (centre button) before each test.
              classifier.v accumulates total_score — it NEVER self-clears.
    """
    print(f"\n{'='*54}")
    print(f"  Test: {label}   (expected: {expected_result})")
    print(f"{'='*54}")
    print()
    print("  ACTION REQUIRED:")
    print("  1. Press the CENTRE BUTTON on the Basys3 to RESET the board.")
    print("  2. Wait until LED[7] (middle) goes OFF.")
    print("  3. All LEDs should be OFF before you continue.")
    print()
    input("  Press ENTER here once the board is reset and all LEDs are OFF...")

    # Flush serial buffers
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    print(f"\n  Sending 128 bytes...")
    for byte_val in byte_values:
        ser.write(bytes([byte_val]))
        if INTER_BYTE_DELAY > 0:
            time.sleep(INTER_BYTE_DELAY)

    print("  All 128 bytes sent. Waiting for FPGA to finish (~50ms)...")
    time.sleep(0.05)

    print()
    print("  READ THE LEDS NOW:")
    print("    LED[15] = ABNORMAL   LED[0] = NORMAL   LED[7] = DONE")
    print()

    led15 = input("  LED[15] ABNORMAL lit? [y/n]: ").strip().lower() == 'y'
    led0  = input("  LED[0]  NORMAL   lit? [y/n]: ").strip().lower() == 'y'
    led7  = input("  LED[7]  DONE     lit? [y/n]: ").strip().lower() == 'y'

    print()

    if not led7:
        print("  WARNING: LED[7] (DONE) not lit.")
        print("  The FPGA did not complete processing. Possible causes:")
        print("  a) Board was not properly reset before sending.")
        print("  b) Bytes were dropped — increase INTER_BYTE_DELAY to 0.002")
        print("  c) COM port is wrong or shared with another program.")
        return False

    got = "ABNORMAL" if led15 else "NORMAL"
    passed = (got == expected_result)

    if passed:
        print(f"  RESULT: PASS ✓   ({got} correctly detected)")
    else:
        print(f"  RESULT: FAIL ✗   (got {got}, expected {expected_result})")
        print()
        print("  Likely cause: controller_fsm.v val_pipe width mismatch.")
        print("  Check that your controller_fsm.v uses:")
        print("    reg [11:0] val_pipe;")
        print("    val_pipe <= {val_pipe[10:0], mac_enable};")
        print("    assign classifier_valid = val_pipe[11];")
        print("  NOT [12:0] / val_pipe[12] (that is 13 cycles, not 12).")

    return passed


def main():
    print("="*54)
    print("  Basys3 ECG Classifier — UART Test")
    print("="*54)
    print(f"  COM port:  {COM_PORT}")
    print(f"  Baud rate: {BAUD_RATE}")
    print(f"  Byte gap:  {INTER_BYTE_DELAY*1000:.1f} ms")
    print()

    # Load files before opening serial port
    try:
        normal_bytes   = load_mem_file(NORMAL_MEM)
        abnormal_bytes = load_mem_file(ABNORMAL_MEM)
        print(f"  {NORMAL_MEM}:   {len(normal_bytes)} bytes loaded OK")
        print(f"  {ABNORMAL_MEM}: {len(abnormal_bytes)} bytes loaded OK")
    except Exception as e:
        print(f"\n  ERROR: {e}")
        return

    # Open serial port
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
        print(f"\n  COM{COM_PORT} opened at {BAUD_RATE} baud.")
        time.sleep(0.5)
    except serial.SerialException as e:
        print(f"\n  ERROR opening port: {e}")
        print("\n  Check:")
        print("  1. Basys3 is plugged in and powered on (switch top-left)")
        print("  2. COM port number is correct (Device Manager -> Ports)")
        print("  3. Vivado Hardware Manager is closed (it locks the port)")
        return

    results = []
    try:
        r1 = send_ecg_sample(ser, normal_bytes,   "NORMAL ECG",   "NORMAL")
        r2 = send_ecg_sample(ser, abnormal_bytes, "ABNORMAL ECG", "ABNORMAL")
        results = [("NORMAL ECG", r1), ("ABNORMAL ECG", r2)]
    finally:
        ser.close()
        print("\n  Port closed.")

    print()
    print("="*54)
    print("  SUMMARY")
    print("="*54)
    passes = sum(1 for _, p in results if p)
    for name, passed in results:
        print(f"  {'PASS ✓' if passed else 'FAIL ✗'}  {name}")
    print(f"\n  {passes}/{len(results)} tests passed")
    if passes == 2:
        print("  ECG classifier working correctly on hardware!")
    elif passes == 1:
        print("  One failure — most likely val_pipe width issue (see above).")
        print("  Use controller_fsm.v from the latest outputs, re-synthesize.")
    print("="*54)


if __name__ == '__main__':
    main()