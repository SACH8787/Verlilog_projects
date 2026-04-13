# Complete Visual Data Flow Guide

## The Journey of One ECG Sample Through the FPGA

```
                    ┌─────────────────────────┐
                    │  UART INPUT (115,200)   │
                    │  128 bytes of ECG data  │
                    │  (int8 values)          │
                    └────────────┬────────────┘
                                 │ (11.11 ms transmission time)
                                 ▼
                    ┌─────────────────────────┐
                    │  SAMPLE BUFFER (RAM)    │
                    │  Store all 128 samples  │
                    │  Ready for processing   │
                    └────────────┬────────────┘
                                 │
                        ┌────────┴────────┐
                        │                 │
                        ▼                 ▼
         ┌──────────────────────┐  ┌──────────────────────┐
         │  CONTROLLER FSM      │  │  WEIGHT ROM          │
         │  ├─ LOAD_WEIGHTS     │  │  240 int8 weights    │
         │  ├─ FILL_WINDOW      │  │  (hardcoded)         │
         │  ├─ COMPUTE (114×)   │  │                      │
         │  └─ DRAIN_PIPELINE   │  └──────────────────────┘
         └────────┬─────────────┘
                  │
                  ▼
    ╔════════════════════════════════════════════════════╗
    ║     13-STAGE PIPELINE (THE COMPUTATIONAL CORE)    ║
    ║                                                    ║
    ║  Input: 15-sample window + 240 weights            ║
    ║  Output: 1 per-window classification score        ║
    ║  Time: 12 cycles (120 ns at 100 MHz)              ║
    ║                                                    ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGE 1-2: MAC UNITS (240 parallel)          │ ║
    ║  │                                              │ ║
    ║  │ Input:  15 ECG samples (int8) +              │ ║
    ║  │         240 weights (int8)                   │ ║
    ║  │                                              │ ║
    ║  │ For each weight:                             │ ║
    ║  │   MAC[i] = ECG_sample × Weight[i]            │ ║
    ║  │                                              │ ║
    ║  │ Output: 240 × int16 products                 │ ║
    ║  │                                              │ ║
    ║  │ Hardware: 240 dedicated multipliers (DSP48)  │ ║
    ║  │ Parallelism: ALL happen in SAME CYCLE        │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 1)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGE 3: ADDER TREE LEVEL 1 (240→128)       │ ║
    ║  │                                              │ ║
    ║  │ Input: 240 × int16 MAC outputs              │ ║
    ║  │                                              │ ║
    ║  │ For Filter 0 (15 values):                   │ ║
    ║  │   stg1[0] = MAC[0]  + MAC[1]   (sign ext)   │ ║
    ║  │   stg1[1] = MAC[2]  + MAC[3]                │ ║
    ║  │   stg1[2] = MAC[4]  + MAC[5]                │ ║
    ║  │   ...                                       │ ║
    ║  │   stg1[7] = MAC[14]  (single value)         │ ║
    ║  │                                              │ ║
    ║  │ For Filter 1-15: Similar process             │ ║
    ║  │                                              │ ║
    ║  │ Output: 128 × int24 partial sums             │ ║
    ║  │ Cost: 128 additions                         │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 2)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGES 4-5: ADDER TREE LEVELS 2-3 (128→32)  │ ║
    ║  │                                              │ ║
    ║  │ LEVEL 2 (128→64):                           │ ║
    ║  │   For each filter (16 times):               │ ║
    ║  │     stg2[0] = stg1[0] + stg1[1]             │ ║
    ║  │     stg2[1] = stg1[2] + stg1[3]             │ ║
    ║  │     stg2[2] = stg1[4] + stg1[5]             │ ║
    ║  │     stg2[3] = stg1[6] + stg1[7]             │ ║
    ║  │                                              │ ║
    ║  │   Output: 64 × int24 values                 │ ║
    ║  │                                              │ ║
    ║  │ LEVEL 3 (64→32):                            │ ║
    ║  │   stg3[0] = OLD_stg2[0] + OLD_stg2[1]       │ ║
    ║  │   stg3[1] = OLD_stg2[2] + OLD_stg2[3]       │ ║
    ║  │   ...                                       │ ║
    ║  │                                              │ ║
    ║  │   Output: 32 × int24 values                 │ ║
    ║  │                                              │ ║
    ║  │ NOTE: stg3 reads OLD stg2 (non-blocking!)   │ ║
    ║  │       This creates 2 real pipeline stages   │ ║
    ║  │       in one always block                   │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 3)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGE 6: FILTER SUMMATION (32→16)            │ ║
    ║  │                                              │ ║
    ║  │ For each filter (0-15):                     │ ║
    ║  │   filter_sum[f] = stg3[f*2+0] +             │ ║
    ║  │                   stg3[f*2+1]                │ ║
    ║  │                                              │ ║
    ║  │ Example (Filter 0):                         │ ║
    ║  │   filter_sum[0] = stg3[0] + stg3[1]         │ ║
    ║  │                 = -4084                      │ ║
    ║  │   (This is the FINAL dot product!)          │ ║
    ║  │                                              │ ║
    ║  │ Output: 16 × int24 values                   │ ║
    ║  │         (one per filter - the conv outputs) │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 4)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGE 7: BATCH NORM + ReLU                  │ ║
    ║  │                                              │ ║
    ║  │ For each filter (0-15):                     │ ║
    ║  │   1. Add BN bias:                           │ ║
    ║  │      biased = filter_sum[f] + BN_BIAS[f]    │ ║
    ║  │                                              │ ║
    ║  │   2. Apply ReLU (clamp negatives):          │ ║
    ║  │      relu_reg[f] = max(0, biased)           │ ║
    ║  │                                              │ ║
    ║  │ Example (Filter 0):                         │ ║
    ║  │   biased = -4084 + (-25) = -4109            │ ║
    ║  │   relu_reg[0] = max(0, -4109) = 0           │ ║
    ║  │   (Filter 0 doesn't detect its pattern)     │ ║
    ║  │                                              │ ║
    ║  │ Example (Filter 1, hypothetical):           │ ║
    ║  │   biased = 6200 + 5489 = 11689              │ ║
    ║  │   relu_reg[1] = max(0, 11689) = 11689       │ ║
    ║  │   (Filter 1 strongly detects its pattern)   │ ║
    ║  │                                              │ ║
    ║  │ Output: 16 × int24 ReLU activations         │ ║
    ║  │         (sparse - many are zero!)           │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 5)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGE 8: FULLY CONNECTED LAYER               │ ║
    ║  │                                              │ ║
    ║  │ For each filter (0-15):                     │ ║
    ║  │   weighted_reg[f] = relu_reg[f] × FC_W[f]   │ ║
    ║  │                                              │ ║
    ║  │ Hardware: 16 × DSP48E1 multipliers          │ ║
    ║  │ All multiplies happen in PARALLEL            │ ║
    ║  │                                              │ ║
    ║  │ Example:                                    │ ║
    ║  │   weighted_reg[0] = 0 × 32767 = 0           │ ║
    ║  │   weighted_reg[1] = 11689 × (-2743)         │ ║
    ║  │                   = -32,073,827              │ ║
    ║  │   weighted_reg[2] = relu_reg[2] × 1605      │ ║
    ║  │   ...                                       │ ║
    ║  │                                              │ ║
    ║  │ Output: 16 × int40 weighted products        │ ║
    ║  │         (all weighted by importance)        │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 6)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGES 9-12: GLOBAL SUM REDUCTION (16→1)     │ ║
    ║  │                                              │ ║
    ║  │ STAGE 9 (16→8):                             │ ║
    ║  │   gt_stg1[0] = weighted_reg[0] +            │ ║
    ║  │                weighted_reg[1]                │ ║
    ║  │   gt_stg1[1] = weighted_reg[2] +            │ ║
    ║  │                weighted_reg[3]                │ ║
    ║  │   ... (8 sums total)                        │ ║
    ║  │   Output: 8 × int40 values                  │ ║
    ║  │                                              │ ║
    ║  │ STAGE 10 (8→4):                             │ ║
    ║  │   gt_stg2[0] = gt_stg1[0] + gt_stg1[1]      │ ║
    ║  │   gt_stg2[1] = gt_stg1[2] + gt_stg1[3]      │ ║
    ║  │   ... (4 sums total)                        │ ║
    ║  │   Output: 4 × int40 values                  │ ║
    ║  │                                              │ ║
    ║  │ STAGE 11 (4→2):                             │ ║
    ║  │   gt_stg3[0] = gt_stg2[0] + gt_stg2[1]      │ ║
    ║  │   gt_stg3[1] = gt_stg2[2] + gt_stg2[3]      │ ║
    ║  │   Output: 2 × int40 values                  │ ║
    ║  │                                              │ ║
    ║  │ STAGE 12 (2→1):                             │ ║
    ║  │   final_total = gt_stg3[0] + gt_stg3[1]     │ ║
    ║  │   Output: 1 × int40 value                   │ ║
    ║  │            ≈ -36,819,487 (for normal ECG)   │ ║
    ║  │                                              │ ║
    ║  │ Binary tree structure:                      │ ║
    ║  │   Reduces 16 → 1 in O(log₂ 16) = 4 stages   │ ║
    ║  │   Each stage: parallel independent adds    │ ║
    ║  │   No bottleneck, all in 4 clock cycles      │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 7)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGE 13: SHIFT & CLAMP                      │ ║
    ║  │                                              │ ║
    ║  │ Input: 40-bit final_total                   │ ║
    ║  │                                              │ ║
    ║  │ Step 1 - Right shift by 10:                 │ ║
    ║  │   shifted = final_total >> 10                │ ║
    ║  │   (Divides by 1024, quantization scaling)   │ ║
    ║  │                                              │ ║
    ║  │ Step 2 - Clamp to 24-bit range:             │ ║
    ║  │   if (shifted > 8388607)  result = 8388607  │ ║
    ║  │   elif (shifted < -8388608) result = -8388608│ ║
    ║  │   else result = shifted                      │ ║
    ║  │                                              │ ║
    ║  │ Output: 24-bit conv_sum value                │ ║
    ║  │         (the FINAL per-window score)         │ ║
    ║  │                                              │ ║
    ║  │ Example:                                    │ ║
    ║  │   final_total = -36,819,487                 │ ║
    ║  │   shifted = -36,819,487 >> 10 = -35,957     │ ║
    ║  │   clamped = -35,957 (fits in 24-bit)        │ ║
    ║  │   Output: conv_sum = -35,957                │ ║
    ║  │                                              │ ║
    ║  │ Ready for CLASSIFIER!                       │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                      ▼ (CYCLE 8)                   ║
    ║  ┌──────────────────────────────────────────────┐ ║
    ║  │ STAGE 14: CLASSIFIER (accumulates)           │ ║
    ║  │                                              │ ║
    ║  │ classifier_valid = 1 (12 cycles after MAC)  │ ║
    ║  │                                              │ ║
    ║  │ if (valid_in):                              │ ║
    ║  │   total_score += conv_sum                    │ ║
    ║  │                                              │ ║
    ║  │ Example (Window 0):                         │ ║
    ║  │   Before: total_score = 0                   │ ║
    ║  │   Add:    conv_sum = -35,957                │ ║
    ║  │   After:  total_score = -35,957             │ ║
    ║  │                                              │ ║
    ║  │ This repeats for all 114 windows             │ ║
    ║  │ Final: total_score ≈ -550,551               │ ║
    ║  │                                              │ ║
    ║  │ THRESHOLD COMPARISON:                       │ ║
    ║  │   if (total_score > -107,020):              │ ║
    ║  │     is_abnormal = 1 ✓                       │ ║
    ║  │   else:                                     │ ║
    ║  │     is_normal = 1 ✓                         │ ║
    ║  │                                              │ ║
    ║  │ Example (NORMAL ECG):                       │ ║
    ║  │   -550,551 > -107,020? NO                   │ ║
    ║  │   → is_normal = 1 ✓                         │ ║
    ║  │                                              │ ║
    ║  │ Example (ABNORMAL ECG):                     │ ║
    ║  │   +1,181,310 > -107,020? YES                │ ║
    ║  │   → is_abnormal = 1 ✓                       │ ║
    ║  └──────────────────────────────────────────────┘ ║
    ║                                                    ║
    ║  Total Latency: 12 cycles = 120 ns                ║
    ║  Throughput: 1 window per cycle after warmup      ║
    ║  Power: Parallelism + pipelining = efficiency     ║
    ║                                                    ║
    ╚════════════════════════════════════════════════════╝
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  LED OUTPUT             │
                    ├─────────────────────────┤
                    │ LED[0]:  NORMAL         │
                    │ LED[15]: ABNORMAL       │
                    │ LED[7]:  DONE           │
                    └─────────────────────────┘
```

---

## Window Processing Timeline

```
Timeline showing how 3 windows flow through the pipeline:

Time:          0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24
              │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │
Window 0:     ├─MAC────────PIPELINE──────────────────┤
              │  MAC  ↓  ↓  ↓  ↓  ↓  ↓  ↓ Cls
              │       St1 St2 St3 St4  BN FC Gt  ✓
              │
Window 1:        │  ├─MAC────────PIPELINE──────────────────┤
                 │  │  MAC  ↓  ↓  ↓  ↓  ↓  ↓  ↓ Cls
                 │  │       St1 St2 St3 St4 BN FC Gt  ✓
                 │  │
Window 2:           │  ├─MAC────────PIPELINE──────────────────┤
                    │  │  MAC  ↓  ↓  ↓  ↓  ↓  ↓  ↓ Cls
                    │  │       St1 St2 St3 St4 BN FC Gt  ✓

Key observations:
  1. Window 0 starts at T=0
  2. Window 1 starts at T=2 (FSM delay)
  3. Window 2 starts at T=4
  4. Results appear at T=12, T=14, T=16 (every 2 cycles after warmup)
  5. Throughput: 1 result per cycle for 114 windows
  6. Total time: 114 windows + 12-cycle latency = 1,368 cycles
  7. At 100 MHz: 1,368 cycles = 13.68 microseconds
```

---

## Information Density Reduction

```
Information flowing through the pipeline:

ECG Input:       128 samples × 8-bit = 1,024 bits
                 ▼
Weights:         240 weights × 8-bit = 1,920 bits
                 ▼
MACs Output:     240 results × 16-bit = 3,840 bits
                 ▼ (compress by adding)
Adder Tree 1:    128 values × 24-bit = 3,072 bits (20% loss)
                 ▼ (compress by adding)
Adder Tree 2:    64 values × 24-bit = 1,536 bits (50% loss)
                 ▼ (compress by adding)
Adder Tree 3:    32 values × 24-bit = 768 bits (75% loss)
                 ▼ (compress by adding)
Filter Sum:      16 values × 24-bit = 384 bits (87.5% loss)
                 ▼ (ReLU sparsifies further)
ReLU Output:     16 values × 24-bit = 384 bits
                 │ (but ~50% are zero now!)
                 ▼
FC Multiply:     16 results × 40-bit = 640 bits
                 ▼ (compress by adding)
Final Sum:       1 value × 40-bit = 40 bits (99.99% loss!)
                 ▼ (shrink back to 24-bit range)
Output:          1 value × 24-bit = 24 bits
                 
                 ▼ (accumulate 114 times)

Total per ECG:   1 value × 32-bit = 32 bits (Final classification score)
```

This progressive compression of information is the **genius** of the architecture—it throws away redundancy while keeping the discriminative features!
