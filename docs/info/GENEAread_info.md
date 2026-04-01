# GENEAread: Reading GENEActiv .bin Files

Source script: `data/raw/GENEActiv/12615468/read_a_binFile_share.R`

This is a utility script that converts a raw GENEActiv `.bin` file into a `.csv`. It was shared as an example from a different study. The CSVs Veerle will provide for SchoolMove have likely already gone through an equivalent step.

---

## Step 1 — Read the binary file

```r
contentFile = read.bin(filename, calibrate=TRUE)
data = data.frame(contentFile$data.out)
```

Uses the `GENEAread` R package to read the raw `.bin` file. `calibrate=TRUE` applies basic hardware calibration. Then strips out everything except the actual sensor data rows, and removes the `button` column (unused on the devices in this study).

---

## Step 2 — Group into 1-second epochs

```r
epoch = 1
recordFreq = 60   # 60 Hz device
frequency = epoch * recordFreq  # = 60 samples per epoch
```

The sensor records at 60 Hz (60 raw samples per second). This block creates a grouping variable `arr` that numbers each 1-second block — like `np.repeat(range(n_epochs), 60)` in Python.

> **Note:** SchoolMove devices record at **100 Hz**, so this script would need adjustment before use on that data.

---

## Step 3 — Compute ENMO and fix timestamps

```r
svmg = abs((svm(data, sqrt=TRUE) - 1))
```

Computes **SVMg** — the vector magnitude of acceleration minus 1g (gravity):

```
SVMg = |sqrt(x² + y² + z²) - 1|
```

This is essentially ENMO. The `abs()` clamps any negative values to 0.

Also converts the raw Unix timestamp to a proper datetime object.

---

## Step 4 — Aggregate to 1-second epochs

```r
groupingData = data %>%
  group_by(arr) %>%
  summarize(
    timestamp = min(timestamp_good),
    xm = mean(x), ym = mean(y), zm = mean(z),
    svmgsum = sum(svmg),
    sdx = sd(x), sdy = sd(y), sdz = sd(z)
  )
```

For each 1-second window, computes:

| Output column | Meaning |
|---|---|
| `timestamp` | Start of the epoch |
| `xm`, `ym`, `zm` | Mean acceleration per axis |
| `svmgsum` | Sum of ENMO across the epoch (equivalent to `SVMgs` in the CSV) |
| `sdx`, `sdy`, `sdz` | Axis standard deviations (used later for non-wear detection) |

These columns map directly to what appears in the GENEActiv CSVs: `SVMgs`, `x_std`, `y_std`, `z_std`.

---

## Step 5 — Export to CSV

```r
write.csv(groupingData, file = paste0(substr(currentFile, 1, nchar(currentFile)-4), ".csv"))
```

Writes one CSV per input file, named after the original `.bin` file.

---

## Relevance to SchoolMove

This script shows **how raw `.bin` files become the epoch-level CSVs** — confirming where the CSV columns come from and what they represent. For SchoolMove, Veerle will likely provide data that has already been through this conversion step, so running this script directly should not be necessary. It is useful as format documentation.
