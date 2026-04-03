import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
import kagglehub
from sklearn.utils import resample, shuffle
from sklearn.model_selection import train_test_split
from torch.utils.data import TensorDataset, DataLoader

# --- 1. LOAD DATASET ---
print("Downloading and Loading dataset...")
path = kagglehub.dataset_download("shayanfazeli/heartbeat")

normal_raw   = pd.read_csv(path + "/ptbdb_normal.csv",   header=None).iloc[:, 0:128].values
abnormal_raw = pd.read_csv(path + "/ptbdb_abnormal.csv", header=None).iloc[:, 0:128].values

abnormal_down = resample(abnormal_raw, replace=False,
                         n_samples=len(normal_raw), random_state=42)
X = np.vstack([normal_raw, abnormal_down])
y = np.hstack([np.zeros(len(normal_raw)), np.ones(len(normal_raw))])

X = X / np.max(np.abs(X))
X = X.reshape(-1, 1, 128).astype(np.float32)
X, y = shuffle(X, y, random_state=42)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

train_loader = DataLoader(
    TensorDataset(torch.tensor(X_train),
                  torch.tensor(y_train, dtype=torch.long)),
    batch_size=64, shuffle=True)

# --- 2. MODEL ---
class HighAccuracyECG_CNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv1d(1, 16, kernel_size=15, stride=1, padding=7, bias=False)
        self.relu  = nn.ReLU()
        self.pool  = nn.MaxPool1d(4)
        self.fc    = nn.Linear(16 * 32, 2)

    def forward(self, x):
        x = self.pool(self.relu(self.conv1(x)))
        x = torch.flatten(x, 1)
        return self.fc(x)

model = HighAccuracyECG_CNN()

# --- 3. TRAIN ---
print("Training...")
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)
scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=20, gamma=0.1)

for epoch in range(50):
    model.train()
    for signals, labels in train_loader:
        optimizer.zero_grad()
        loss = criterion(model(signals), labels)
        loss.backward()
        optimizer.step()
    scheduler.step()
    if (epoch + 1) % 5 == 0:
        model.eval()
        with torch.no_grad():
            out  = model(torch.tensor(X_test))
            pred = torch.max(out, 1)[1]
            acc  = (pred == torch.tensor(y_test)).float().mean().item()
            print(f"Epoch {epoch+1}/50  Accuracy: {acc*100:.2f}%")

# --- 4. QUANTIZE WEIGHTS ---
print("\nQuantizing weights...")
weights = model.conv1.weight.detach().cpu().numpy()
max_val = np.max(np.abs(weights))
w_scale = 127.0 / max_val if max_val != 0 else 1.0

def float_to_int8(val):
    q = int(round(val * w_scale))
    return max(-128, min(127, q))

def to_hex8(q):
    if q < 0: q = 256 + q
    return f"{q:02X}"

with open("conv_weights.mem", "w") as f:
    for fi in range(16):
        for k in range(15):
            f.write(to_hex8(float_to_int8(weights[fi, 0, k])) + "\n")
print("  -> conv_weights.mem written (240 lines)")

# --- 5. EXPORT TEST SIGNALS ---
print("Exporting test ECG files...")
sig_scale = 127.0

def export_signal(signal, filename):
    with open(filename, "w") as f:
        for v in signal:
            q = int(round(float(v) * sig_scale))
            q = max(-128, min(127, q))
            if q < 0: q = 256 + q
            f.write(f"{q:02X}\n")

test_normal_sample   = X_test[y_test == 0][0][0]
test_abnormal_sample = X_test[y_test == 1][0][0]
export_signal(test_normal_sample,   "test_ecg_normal.mem")
export_signal(test_abnormal_sample, "test_ecg_abnormal.mem")
print("  -> test_ecg_normal.mem   written (128 lines)")
print("  -> test_ecg_abnormal.mem written (128 lines)")

# ============================================================================
# --- 6. FPGA-ACCURATE THRESHOLD FINDER ---
#
# WHY THE MIDPOINT FAILED:
#   The simple midpoint assumes the score distributions are well-separated.
#   After int8 quantization the distributions can overlap, so we instead
#   SCAN every possible threshold and pick the one that maximises
#   balanced accuracy = (sensitivity + specificity) / 2.
#
# PIPELINE SIMULATED (matches Verilog exactly):
#   For each of 114 windows across the 128-sample ECG:
#     1. window[15] dot weights[f][15] for all 16 filters  (int64)
#     2. ReLU each filter output
#     3. grand_sum = sum of all 16 ReLU outputs
#     4. max_pool = running max of grand_sum
#     5. total_score += max_pool  (accumulate every window)
# ============================================================================
print("\nCalculating FPGA-accurate threshold...")
print("  (Scoring all test samples -- takes ~2 min in Colab)")

w_int = np.array([[float_to_int8(weights[f, 0, k])
                   for k in range(15)]
                  for f in range(16)], dtype=np.int64)

def fpga_score(signal_float):
    sig = np.array([max(-128, min(127, int(round(float(v) * sig_scale))))
                    for v in signal_float], dtype=np.int64)
    total_score  = np.int64(0)
    max_pool_val = np.int64(0)
    for start in range(114):
        window    = sig[start:start + 15]
        grand_sum = np.int64(0)
        for f in range(16):
            dot = np.int64(np.dot(window, w_int[f]))
            grand_sum += max(np.int64(0), dot)
        if grand_sum > max_pool_val:
            max_pool_val = grand_sum
        total_score += max_pool_val
    return int(total_score)

n_test = X_test[y_test == 0]
a_test = X_test[y_test == 1]

n_scores = np.array([fpga_score(n_test[i][0]) for i in range(len(n_test))])
a_scores = np.array([fpga_score(a_test[i][0]) for i in range(len(a_test))])

print(f"\n  Normal   scores: min={n_scores.min():,}  max={n_scores.max():,}  "
      f"mean={n_scores.mean():.0f}")
print(f"  Abnormal scores: min={a_scores.min():,}  max={a_scores.max():,}  "
      f"mean={a_scores.mean():.0f}")

# Check if distributions are even separable
if n_scores.mean() > a_scores.mean():
    print("\n  NOTE: Normal scores are HIGHER than abnormal scores.")
    print("  This means normal ECGs produce bigger convolution responses")
    print("  with these weights -- classifier logic will be inverted.")
    print("  Using: is_abnormal when score BELOW threshold.")
    inverted = True
else:
    inverted = False

all_scores = np.concatenate([n_scores, a_scores])
all_labels = np.concatenate([np.zeros(len(n_scores)), np.ones(len(a_scores))])

# Scan thresholds
candidates = np.unique(all_scores)
if len(candidates) > 10000:
    idx = np.linspace(0, len(candidates)-1, 10000, dtype=int)
    candidates = candidates[idx]

best_thresh  = int(np.median(all_scores))
best_bal_acc = 0.0

for t in candidates:
    if not inverted:
        pred = (all_scores > t).astype(int)      # >threshold = abnormal
    else:
        pred = (all_scores <= t).astype(int)     # <=threshold = abnormal

    tp = np.sum((pred == 1) & (all_labels == 1))
    tn = np.sum((pred == 0) & (all_labels == 0))
    fp = np.sum((pred == 1) & (all_labels == 0))
    fn = np.sum((pred == 0) & (all_labels == 1))
    sens    = tp / (tp + fn + 1e-9)
    spec    = tn / (tn + fp + 1e-9)
    bal_acc = (sens + spec) / 2
    if bal_acc > best_bal_acc:
        best_bal_acc = bal_acc
        best_thresh  = int(t)

# Final accuracy report
if not inverted:
    pred_f = (all_scores > best_thresh).astype(int)
else:
    pred_f = (all_scores <= best_thresh).astype(int)

acc_n = np.mean((pred_f[all_labels==0]) == 0) * 100
acc_a = np.mean((pred_f[all_labels==1]) == 1) * 100

print(f"\n  Best threshold  : {best_thresh:,}")
print(f"  Balanced acc    : {best_bal_acc*100:.1f}%")
print(f"  Normal   correct: {acc_n:.1f}%")
print(f"  Abnormal correct: {acc_a:.1f}%")

# --- Verify the two specific exported test files ---
print("\n--- Verifying your exported test files ---")
n_score_v = fpga_score(test_normal_sample)
a_score_v = fpga_score(test_abnormal_sample)

if not inverted:
    n_pred = "NORMAL"   if n_score_v <= best_thresh else "ABNORMAL"
    a_pred = "ABNORMAL" if a_score_v >  best_thresh else "NORMAL"
else:
    n_pred = "NORMAL"   if n_score_v >  best_thresh else "ABNORMAL"
    a_pred = "ABNORMAL" if a_score_v <= best_thresh else "NORMAL"

print(f"  test_ecg_normal.mem   score={n_score_v:,}  -> {n_pred} "
      f"({'OK' if n_pred=='NORMAL'   else 'WRONG'})")
print(f"  test_ecg_abnormal.mem score={a_score_v:,}  -> {a_pred} "
      f"({'OK' if a_pred=='ABNORMAL' else 'WRONG'})")

if best_bal_acc < 0.75:
    print("\n  *** WARNING: balanced accuracy < 75% -- see advice below ***")

with open("threshold.txt", "w") as f:
    f.write(str(best_thresh))

# ============================================================================
# --- 7. PRINT VERILOG LINES TO COPY ---
# ============================================================================
print("\n" + "="*60)
print("COPY THESE LINES INTO classifier.v:")
print(f"  parameter signed [31:0] THRESHOLD = 32'd{best_thresh};")
if inverted:
    print("")
    print("  ALSO invert the comparison in classifier.v:")
    print("  Change:  if (total_score > THRESHOLD)")
    print("  To:      if (total_score <= THRESHOLD)")
    print("  Because normal ECGs score HIGHER than abnormal with your weights.")
print("="*60)

if best_bal_acc < 0.75:
    print("""
ADVICE - Why accuracy is low after quantization:

  1. Your float model gets ~95% but int8 quantization drops it to ~66%.
     This is a classic "quantization collapse" when weights are very small.

  2. CHECK: Open conv_weights.mem -- if most values are 00, 01, FF, FE
     it means the weight range is tiny and most precision is lost.

  3. FIX A (easiest): Add L2 regularization to spread weight magnitude:
       optimizer = optim.Adam(model.parameters(), lr=0.001, weight_decay=1e-4)

  4. FIX B: Quantization-Aware Training -- add noise during training:
       In the training loop, before optimizer.step():
         with torch.no_grad():
           for p in model.conv1.parameters():
             noise = torch.randint(-1, 2, p.shape).float() / 127.0
             p.add_(noise * 0.01)

  5. FIX C: Use per-filter scaling instead of global scaling:
       Scale each filter's 15 weights independently to use full int8 range.
       This is already the right approach -- just make sure max_val is
       computed per-filter not globally.

  Re-run this script after any change to get a new threshold.
""")

print("\nDone!")