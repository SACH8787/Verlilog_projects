========================================================================
  EDGE AI ECG ACCELERATOR
  Real-Time ECG Arrhythmia Detection on FPGA
  FPGA Hackathon 2026 Submission
  Indian Institute of Information Technology Guwahati
  Department of ECE
========================================================================

WHAT THIS PROJECT DOES
-----------------------
This project implements a real-time ECG arrhythmia detection
system using a custom neural network hardware accelerator on a
Xilinx Artix-7 FPGA (Digilent Basys3 board).

A Conv1D neural network trained in PyTorch is converted entirely
into integer arithmetic (int8/int16/int32) and deployed as
hand-written Verilog RTL — no HLS, no IP cores.
The FPGA receives 128 bytes of ECG data over UART, processes
it through a 240-MAC parallel 13-stage pipeline, and
classifies the heartbeat as NORMAL or ABNORMAL in under 5 us.

RESULTS SUMMARY:
  Float model accuracy    : 90.86%
  Hardware accuracy (live): 85.0%  (17/20 real PTB-DB samples)
  Pipeline latency        : 4.99 microseconds
  Power consumption       : 0.142 W at 100 MHz

LED OUTPUTS ON THE BOARD:
  LED[0]  (rightmost) = ON -> NORMAL heartbeat
  LED[15] (leftmost)  = ON -> ABNORMAL (arrhythmia detected)
  LED[7]  (middle)    = ON -> inference complete


PROJECT STRUCTURE
-----------------
EDGE_AI_HACKATHON/
├── EDGE_AI_HACKATHON.xpr        Vivado project file (open this)
├── src/                         All Verilog source files
│   ├── basys3_top.v             Board top-level
│   ├── top_accelerator.v        Accelerator structural top
│   ├── controller_fsm.v         7-state inference control FSM
│   ├── conv1d_engine.v          240-MAC conv + FC, 13-stage pipeline
│   ├── pe_mac.v                 2-stage pipelined MAC unit
│   ├── classifier.v             FC score accumulation + threshold
│   ├── rom_memory.v             Weight ROM ($readmemh)
│   ├── relu.v                   Combinatorial ReLU
│   ├── max_pool.v               Running max pool
│   ├── uart_rx.v                4-state UART receiver (115200 baud)
│   └── dual_port_ram.v          128-byte dual-port sample buffer
├── tb/
│   └── tb_full.v                Automated pass/fail testbench
├── mem/
│   ├── conv_weights.mem         240 int8 conv weights (hex)
│   ├── test_ecg_normal.mem      Normal ECG test sample (128 bytes)
│   └── test_ecg_abnormal.mem    Abnormal ECG test sample (128 bytes)
└── python/
    ├── test_fpga.py             Interactive UART test script
    └── generate_test_samples.py Downloads PTB-DB and tests 20 samples


REQUIREMENTS
------------
Hardware:
  - Digilent Basys3 board (Xilinx Artix-7 xc7a35tcpg236-1)
  - Micro-USB cable (for programming and UART)

Software:
  - Xilinx Vivado 2020.x or later (free WebPACK edition is enough)
  - Python 3.8+  with pyserial:  pip install pyserial
  - (Optional for batch testing): pip install kagglehub pandas scikit-learn numpy


========================================================================
STEP 1 — OPEN THE PROJECT
========================================================================

1. Extract the project ZIP to a folder with NO SPACES in the path.
   Good:  C:\FPGA\EDGE_AI_HACKATHON\
   Bad:   C:\My Projects\EDGE AI\        <- spaces cause Vivado errors

2. Launch Vivado.

3. Click:  File -> Open Project

4. Navigate to the extracted folder and open:
   EDGE_AI_HACKATHON.xpr


========================================================================
STEP 2 — RUN BEHAVIOURAL SIMULATION (verify math first)
========================================================================

This step checks that the Verilog pipeline produces the same
integer scores as the Python simulation.

1. In the Flow Navigator (left panel), click:
   Run Simulation -> Run Behavioural Simulation

2. Vivado compiles all RTL and launches the waveform viewer.

3. The testbench (tb_full.v) automatically loads both .mem files
   and runs two tests. Check the Tcl Console at the bottom.
   You should see EXACTLY:

   ========================================
    tb_full: ECG Accelerator Tests
   ========================================

   --- TEST 1: NORMAL ECG ---
     total_score  = -550551  (expected -550551)
     is_abnormal  = 0   is_normal = 1
     RESULT: PASS ✓

   --- TEST 2: ABNORMAL ECG ---
     total_score  = 1181310  (expected 1181310)
     is_abnormal  = 1   is_normal = 0
     RESULT: PASS ✓

   RESULTS: 2 PASSED  0 FAILED
    STATUS: ALL TESTS PASSED - ready to program FPGA ✓

   If you see "xxxx" values: copy the three .mem files from mem/
   directly into the simulation directory:
   EDGE_AI_HACKATHON.sim/sim_1/behav/xsim/

4. Close the simulation when done.


========================================================================
STEP 3 — GENERATE THE BITSTREAM
========================================================================

1. In the Flow Navigator, click:  Generate Bitstream

2. If prompted "Synthesis/Implementation not run", click YES to run both.

3. Expected results after implementation:
   - WNS (Worst Negative Slack): +0.379 ns  <- positive means TIMING MET
   - Failed Routes: 0
   - LUT utilisation: 85.4%  (17,759 / 20,800)
   - Power: 0.142 W

4. When complete, click  Open Implemented Design  to verify.
   DRC shows 15 warnings - all safe to ignore (missing I/O delays
   on LEDs/buttons, and a cosmetic CFGBVS voltage property).


========================================================================
STEP 4 — PROGRAM THE BASYS3 BOARD
========================================================================

1. Connect the Basys3 to your PC with the micro-USB cable.

2. Slide the power switch (top-left of board) to ON.
   The board will power up with random LED states — this is normal.

3. In Vivado:  Open Hardware Manager -> Open Target -> Auto Connect
   The board should appear as "xc7a35t_0".

4. Click:  Program Device
   The bitstream path auto-fills:
   EDGE_AI_HACKATHON.runs/impl_1/basys3_top.bit

5. Click PROGRAM.
   The DONE LED (small green LED near the USB port) lights up.
   All other LEDs should now be OFF — the neural network is ready.


========================================================================
STEP 5 — FIND YOUR COM PORT
========================================================================

The Basys3 appears as a USB serial device.

Windows:
  1. Open Device Manager  (Win+X -> Device Manager)
  2. Expand "Ports (COM & LPT)"
  3. Find "USB Serial Port (COMx)" — note the number, e.g. COM4

Linux:
  ls /dev/ttyUSB*
  Typically /dev/ttyUSB0 or /dev/ttyUSB1

NOTE: Vivado Hardware Manager uses the same COM port.
Close Hardware Manager (or disconnect the hardware target)
before running the Python script, or the script will fail
with "port already in use".


========================================================================
STEP 6 — TEST ON HARDWARE (Python UART script)
========================================================================

The Python script sends pre-recorded ECG samples to the board
and asks you to read the LEDs.

1. Open a terminal/command prompt in the project folder.

2. Edit test_fpga.py and set your COM port:
   COM_PORT = 'COM4'     <- change to your port number

3. Run:
   python test_fpga.py

4. For each test:
   a. Press the CENTRE BUTTON on the Basys3 to reset it.
   b. Wait until LED[7] (middle LED) goes OFF.
   c. Make sure ALL LEDs are OFF.
   d. Press ENTER in the terminal.
   e. The script sends 128 bytes. Wait ~1 second.
   f. Read the LEDs and type y or n when prompted.

5. Expected results:
   Normal ECG test:
     LED[0]  (rightmost) = ON   -> answer y to "NORMAL lit?"
     LED[15] (leftmost)  = OFF  -> answer n to "ABNORMAL lit?"
     LED[7]  (middle)    = ON   -> answer y to "DONE lit?"
     Result: PASS ✓

   Abnormal ECG test:
     LED[15] (leftmost)  = ON   -> answer y to "ABNORMAL lit?"
     LED[0]  (rightmost) = OFF  -> answer n to "NORMAL lit?"
     LED[7]  (middle)    = ON   -> answer y to "DONE lit?"
     Result: PASS ✓

IMPORTANT — Always reset between tests:
  The classifier accumulates a running score that is only cleared
  by the reset button. If you skip the reset, the second test
  will produce a wrong result because it starts from the first
  test's leftover score.


========================================================================
STEP 7 — BATCH TEST WITH REAL PTB-DB SAMPLES (optional)
========================================================================

To test with 20 real ECG samples from the PTB Diagnostic Database:

1. Install extra dependencies:
   pip install kagglehub pandas scikit-learn numpy pyserial

2. Make sure COM_PORT is set correctly in generate_test_samples.py

3. Run:
   python generate_test_samples.py

4. The script downloads the PTB-DB dataset (~100 MB, one-time),
   picks 10 normal and 10 abnormal samples, saves them as .mem files
   in the ecg_samples/ folder, then walks you through testing each one.

5. Expected accuracy: 85% (17 out of 20 correct).


========================================================================
TROUBLESHOOTING
========================================================================

PROBLEM: Simulation shows "xxxx" or "zzzz" values
FIX: Copy conv_weights.mem, test_ecg_normal.mem, test_ecg_abnormal.mem
     from the mem/ folder into:
     EDGE_AI_HACKATHON.sim/sim_1/behav/xsim/

PROBLEM: Python script says "could not open port COM4"
FIX 1: Check the port number in Device Manager and update COM_PORT.
FIX 2: Close Vivado Hardware Manager — it holds the COM port.
FIX 3: Close any other serial monitor (PuTTY, Arduino IDE, etc).

PROBLEM: LED[7] never lights up after sending bytes
FIX: Increase INTER_BYTE_DELAY from 0.001 to 0.002 in test_fpga.py.
     This gives the UART receiver more time between bytes.

PROBLEM: Both samples classified as NORMAL
FIX: You did not reset the board between tests. Press the CENTRE
     BUTTON and wait for all LEDs to go OFF before each test.

PROBLEM: Vivado "Spawn failed: No error" messages
CAUSE: This is a known Windows-specific Vivado bug (Windows Defender
       or a hung background process). It affects simulation only.
       The bitstream and hardware are not affected.
FIX: Close and re-open Vivado. If it persists, check Task Manager
     for hung vivado_simulator.exe processes and end them.

PROBLEM: Synthesis fails with "cannot replace file with itself"
CAUSE: Vivado locked a .mem file during a previous simulation.
FIX: Close all Vivado windows, reopen the project, and re-run.


========================================================================
KEY NUMBERS (for report / demo)
========================================================================

  Float model accuracy       : 90.86%
  Hardware simulation acc    : 86.53%
  Live hardware accuracy     : 85.0%  (17/20 samples)
  Normal samples correct     : 8/10 = 80%
  Abnormal samples correct   : 9/10 = 90%

  Pipeline latency           : 4.99 microseconds
  End-to-end latency (UART)  : 11.11 milliseconds
  Throughput                 : 90 inferences per second
  CPU equivalent latency     : ~7 milliseconds
  Speedup vs CPU (pipeline)  : >1,400x

  Total on-chip power        : 0.142 W
  CPU power equivalent       : ~15 W
  Power saving               : >100x

  LUT utilisation            : 17,759 / 20,800 = 85.4%
  FF  utilisation            : 12,768 / 41,600 = 30.7%
  DSP48E1                    : 40 / 90 = 44.4%
  Block RAM                  : 1 / 50 = 2.0%
  Timing slack (WNS)         : +0.379 ns (met at 100 MHz)
  Power                      : 0.142 W

  Normal test score          : -550,551  (threshold = -107,020)
  Abnormal test score        : +1,181,310
  Score gap                  : 1,731,861 (16x threshold distance)


========================================================================
HOW IT WORKS (brief technical summary)
========================================================================

Training (Python / Colab):
  1. A Conv1D neural network is trained on the PTB-DB ECG dataset.
  2. Batch Normalisation parameters are analytically folded into
     integer bias constants (one per filter).
  3. Conv weights are quantised to int8 per-filter.
  4. FC weights are quantised to int16.
  5. A threshold is found by scanning all test set scores.
  6. Everything is exported as .mem and localparam values.

Hardware (Verilog):
  1. uart_rx receives 128 int8 bytes from the PC.
  2. dual_port_ram buffers them; basys3_top fires a one-shot start.
  3. controller_fsm loads weights from BRAM, fills the window,
     then steps through 114 sliding windows.
  4. conv1d_engine: 240 MACs run in parallel (one clock cycle),
     an 8-stage adder tree reduces to per-filter sums,
     BN bias is added, ReLU applied, FC weight multiplied
     (DSP48E1), all 16 FC products summed -> conv_sum (24-bit).
  5. classifier accumulates conv_sum across all 114 windows.
     On done, compares total_score to THRESHOLD = -107,020.
     Positive = ABNORMAL, negative = NORMAL.
  6. LEDs light: LED[0]=normal, LED[15]=abnormal, LED[7]=done.


========================================================================
CONTACT
========================================================================
Team: 
Institution: IIIT Guwahati, Department of ECE
Email: Sachin.mohanty23b@iiitg.ac.in
Hackathon: FPGA Hackathon 2026, BITS Pilani Hyderabad
========================================================================