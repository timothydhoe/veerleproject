"""
generate_ggir_outputs.py
────────────────────────
Generates synthetic GGIR output CSVs for ~390 participants (65 per school,
both metings) plus a segment_summary.csv for the School Day dashboard tab.

Run from the repo root:
    python data/example/dummy_data/generate_ggir_outputs.py

Outputs land in:
    data/processed/ggir/meting_1/ and meting_2/   ← GGIR result files
    data/processed/segment_summary.csv             ← segment labels
"""

import csv
import os
import random
from datetime import date, datetime, timedelta
from pathlib import Path

random.seed(42)

# ── Paths ──────────────────────────────────────────────────────────────────────
REPO_ROOT   = Path(__file__).resolve().parents[3]
OUT_BASE    = REPO_ROOT / "data" / "processed" / "ggir"
SEG_OUT     = REPO_ROOT / "data" / "processed" / "segment_summary.csv"

# Participants per school — realistic spread summing to ~390
N_PER_SCHOOL = {
    "school_1": 70,
    "school_2": 80,
    "school_3": 60,
    "school_4": 65,
    "school_5": 55,
    "school_6": 60,
}

# ~15% of participants will have insufficient valid days (excluded)
EXCLUSION_RATE = 0.15

METINGS = {
    "meting_1": {
        "school_1": date(2026, 2, 23),
        "school_2": date(2026, 3,  3),
        "school_3": date(2026, 1, 19),
        "school_4": date(2026, 2,  5),
        "school_5": date(2026, 1,  9),
        "school_6": date(2026, 3,  2),
    },
    "meting_2": {
        "school_1": date(2026, 6,  1),
        "school_2": date(2026, 5, 26),
        "school_3": date(2026, 4, 20),
        "school_4": date(2026, 5, 21),
        "school_5": date(2026, 3, 11),
        "school_6": date(2026, 5,  4),
    },
}

# ~8% of participants only have meting_1 (device not returned for meting_2)
METING2_DROPOUT_RATE = 0.08

WEEKDAY_NAMES = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

# ── School activity profiles ───────────────────────────────────────────────────
# Each segment: (SB_min, LPA_min, MPA_min, VPA_min) — means, with per-pupil noise.
#
# Narrative for the demo:
#   School 5  — strong PA programme, most active during recess
#   School 2  — good facilities, active recess
#   School 1  — average
#   School 4  — average/slightly above, long lunch break
#   School 3  — most sedentary (no structured break activities)
#   School 6  — sedentary in class, but active after school

SCHOOL_PROFILES = {
    "school_1": {
        "in_class":      (175, 42,  8, 1),
        "recess":        ( 10,  8,  5, 2),
        "lunch":         ( 28, 18,  9, 3),
        "after_school":  (115, 52, 28, 8),
        "before_school": ( 22, 10,  4, 1),
    },
    "school_2": {
        "in_class":      (170, 44,  9, 1),
        "recess":        (  8,  8,  7, 3),
        "lunch":         ( 25, 18, 11, 4),
        "after_school":  (110, 55, 30, 9),
        "before_school": ( 22, 10,  4, 1),
    },
    "school_3": {   # most sedentary — unconfirmed schedule (fallback)
        "in_class":      (185, 38,  4, 0),
        "recess":        ( 13,  7,  3, 1),
        "lunch":         ( 35, 16,  6, 2),
        "after_school":  (125, 48, 20, 5),
        "before_school": ( 25,  9,  2, 0),
    },
    "school_4": {   # slightly above average, long lunch — unconfirmed schedule (fallback)
        "in_class":      (172, 43,  9, 1),
        "recess":        ( 10,  8,  6, 2),
        "lunch":         ( 40, 25, 15, 5),
        "after_school":  (118, 52, 27, 8),
        "before_school": ( 22, 10,  4, 1),
    },
    "school_5": {   # strong PA programme — star of the show
        "in_class":      (165, 46, 12, 2),
        "recess":        (  6,  7,  8, 4),
        "lunch":         ( 22, 18, 15, 6),
        "after_school":  (108, 57, 33, 11),
        "before_school": ( 21, 11,  5,  1),
    },
    "school_6": {   # sedentary in class, very active after school
        "in_class":      (182, 40,  5, 0),
        "recess":        ( 11,  7,  4, 1),
        "lunch":         ( 27, 16,  8, 2),
        "after_school":  (105, 58, 35, 12),
        "before_school": ( 23,  9,  3,  0),
    },
}

# Sleep profiles per school: (mean_min, sd_min, mean_efficiency_pct, sd_efficiency)
# Children 6-12 years, recommended 8-10h (480-600 min)
SCHOOL_SLEEP = {
    "school_1": (510, 40, 88, 5),
    "school_2": (525, 35, 90, 4),
    "school_3": (495, 50, 86, 6),   # slightly less sleep (more sedentary lifestyle)
    "school_4": (515, 38, 89, 5),
    "school_5": (530, 32, 91, 4),   # best PA programme → better sleep
    "school_6": (505, 45, 87, 5),
}

# Meting 2 is spring — slightly more active (+10% MVPA), slightly better sleep
METING2_MVPA_BOOST  = 1.10
METING2_SLEEP_BOOST = 1.02   # +2% sleep duration in spring

# ── Helpers ───────────────────────────────────────────────────────────────────

def jitter(value, pct=0.20):
    """Add ±pct relative noise, floored at 0."""
    return max(0.0, value * (1 + random.uniform(-pct, pct)))


def gauss_pos(mean, sd):
    """Gaussian noise, floored at 0."""
    return max(0.0, random.gauss(mean, sd))


def weekday_name(d: date) -> str:
    return WEEKDAY_NAMES[d.weekday()]


def is_weekend(d: date) -> bool:
    return d.weekday() >= 5


def get_participants(school: str) -> list[str]:
    """Return participant IDs for a school, e.g. school_2 → ['2001', '2002', ...]."""
    s   = int(school.split("_")[1])
    n   = N_PER_SCHOOL[school]
    return [f"{s}{str(i).zfill(3)}" for i in range(1, n + 1)]


# ── Dropout mask ──────────────────────────────────────────────────────────────

def build_dropout_mask(school: str) -> set[str]:
    """~8% of participants only appear in meting_1 (dropout for meting_2)."""
    pids    = get_participants(school)
    n_drop  = max(0, round(len(pids) * METING2_DROPOUT_RATE))
    return set(random.sample(pids, n_drop))


# Global dropout masks (built once so they're consistent across meting_1 / meting_2)
DROPOUT_MASKS = {school: build_dropout_mask(school) for school in SCHOOL_PROFILES}


# ── Part 2 daysummary ─────────────────────────────────────────────────────────

def make_part2_rows(school: str, meting: str) -> list[dict]:
    start_date   = METINGS[meting][school]
    participants = get_participants(school)
    rows         = []

    for pid in participants:
        # Skip dropouts for meting_2
        if meting == "meting_2" and pid in DROPOUT_MASKS[school]:
            continue

        fname = f"{pid}.csv"

        # ~15% of participants are "non-compliant" — too many invalid days
        non_compliant = random.random() < EXCLUSION_RATE
        # 0-1 random invalid days for compliant pupils, 3-5 for non-compliant
        if non_compliant:
            n_invalid = random.randint(3, 5)
        else:
            n_invalid = random.choice([0, 0, 0, 1, 1])
        invalid_days = set(random.sample(range(1, 8), min(n_invalid, 7)))

        for day_i in range(8):   # 8 days including partial first/last
            d        = start_date + timedelta(days=day_i)
            is_wkend = is_weekend(d)

            if day_i == 0:
                valid_h = round(jitter(5.0, 0.25), 2)   # partial first day — just below 5h threshold for some
            elif day_i in invalid_days:
                valid_h = round(jitter(3.0, 0.25), 2)   # clearly invalid (below 5h threshold)
            elif is_wkend:
                valid_h = round(jitter(13.5, 0.12), 2)
            else:
                valid_h = round(jitter(15.2, 0.08), 2)  # good compliance

            total_h = 24.0 if day_i > 0 else round(jitter(6.75, 0.1), 2)

            rows.append({
                "ID":            fname,
                "filename":      fname,
                "start_time":    f"{d.isoformat()}T{'17:15' if day_i == 0 else '00:00'}:00+0100",
                "calendar_date": d.isoformat(),
                "bodylocation":  "not extracted",
                "N valid hours": valid_h,
                "N hours":       total_h,
                "weekday":       weekday_name(d),
                "measurementday": day_i + 1,
            })
    return rows


# ── Part 5 personsummary ──────────────────────────────────────────────────────

def make_part5_pers_rows(school: str, meting: str) -> list[dict]:
    start_date   = METINGS[meting][school]
    participants = get_participants(school)
    prof         = SCHOOL_PROFILES[school]
    boost        = METING2_MVPA_BOOST  if meting == "meting_2" else 1.0
    sleep_boost  = METING2_SLEEP_BOOST if meting == "meting_2" else 1.0
    sleep_mu, sleep_sd, eff_mu, eff_sd = SCHOOL_SLEEP[school]
    rows         = []

    for pid in participants:
        if meting == "meting_2" and pid in DROPOUT_MASKS[school]:
            continue

        fname = f"{pid}.csv"

        # Aggregate across segments for whole-day totals
        segs    = ["in_class", "recess", "lunch", "after_school", "before_school"]
        tot_IN = tot_LIG = tot_MOD = tot_VIG = 0.0
        for seg in segs:
            sb, lpa, mpa, vpa = prof[seg]
            tot_IN  += jitter(sb,           0.15)
            tot_LIG += jitter(lpa,          0.15)
            tot_MOD += jitter(mpa * boost,  0.20)
            tot_VIG += jitter(vpa * boost,  0.25)

        mvpa_total   = tot_MOD + tot_VIG
        mvpa_bts_10  = round(jitter(mvpa_total * 0.45, 0.20), 1)  # bouts ≥10 min

        # Sedentary bouts: 30-min bouts (most interesting for research)
        sb_bts_30    = round(jitter(tot_IN * 0.30, 0.25), 1)
        sb_bts_20_30 = round(jitter(tot_IN * 0.15, 0.25), 1)
        sb_bts_10_20 = round(jitter(tot_IN * 0.10, 0.25), 1)

        # Sleep
        sleep_min = round(max(300, gauss_pos(sleep_mu * sleep_boost, sleep_sd)), 1)
        sleep_eff = round(min(100, max(70, gauss_pos(eff_mu, eff_sd))), 1)

        acc_mg   = round((tot_MOD * 300 + tot_VIG * 700 + tot_LIG * 100 + tot_IN * 20)
                         / (tot_IN + tot_LIG + tot_MOD + tot_VIG + 0.001), 1)
        m60      = round(acc_mg * jitter(3.2, 0.15), 1)
        nonwear  = round(jitter(8.5, 0.30), 1)

        non_compliant = random.random() < EXCLUSION_RATE
        n_valid  = random.randint(1, 3) if non_compliant else random.randint(4, 7)
        n_wd     = min(n_valid, random.randint(3, 5))
        n_we     = n_valid - n_wd

        rows.append({
            "filename":                  fname,
            "ID":                        fname,
            "startday":                  weekday_name(start_date),
            "calendar_date":             start_date.isoformat(),
            "Nvaliddays":                n_valid,
            "Nvaliddays_WD":             n_wd,
            "Nvaliddays_WE":             max(0, n_we),
            # Activity intensity totals
            "dur_day_total_IN_min_pla":  round(tot_IN,  1),
            "dur_day_total_LIG_min_pla": round(tot_LIG, 1),
            "dur_day_total_MOD_min_pla": round(tot_MOD, 1),
            "dur_day_total_VIG_min_pla": round(tot_VIG, 1),
            # Sedentary bouts (counts per day)
            "dur_day_IN_bts_30_min_pla":   sb_bts_30,
            "dur_day_IN_bts_20_30_min_pla":sb_bts_20_30,
            "dur_day_IN_bts_10_20_min_pla":sb_bts_10_20,
            # MVPA bouts
            "dur_day_MVPA_bts_10_min_pla": mvpa_bts_10,
            # Sleep
            "dur_spt_sleep_min_pla":       sleep_min,
            "sleep_efficiency_pla":        sleep_eff,
            # Summaries
            "ACC_day_mg_pla":              acc_mg,
            "quantile_mostactive60min_mg_pla": m60,
            "nonwear_perc_day_pla":        nonwear,
            "boutcriter.in":               "0.9",
            "boutcriter.lig":              "0.8",
            "boutcriter.mvpa":             "0.8",
            "boutdur.in":                  "30_20_10",
            "boutdur.lig":                 "10_5_1",
            "boutdur.mvpa":                "10_5_1",
            "GGIRversion":                 "3.3.4",
            "lastDate":                    (start_date + timedelta(days=7)).isoformat(),
        })
    return rows


# ── Part 5 daysummary ─────────────────────────────────────────────────────────

def make_part5_day_rows(school: str, meting: str) -> list[dict]:
    start_date   = METINGS[meting][school]
    participants = get_participants(school)
    prof         = SCHOOL_PROFILES[school]
    boost        = METING2_MVPA_BOOST if meting == "meting_2" else 1.0
    rows         = []

    for pid in participants:
        if meting == "meting_2" and pid in DROPOUT_MASKS[school]:
            continue

        fname = f"{pid}.csv"
        win   = 1
        for day_i in range(1, 7):
            d = start_date + timedelta(days=day_i)
            if is_weekend(d):
                sb  = jitter(280, 0.15)
                lpa = jitter(160, 0.15)
                mod = jitter(35 * boost, 0.25)
                vpa = jitter(8  * boost, 0.30)
            else:
                segs = ["in_class", "recess", "lunch", "after_school", "before_school"]
                sb = lpa = mod = vpa = 0.0
                for seg in segs:
                    s, l, m, v = prof[seg]
                    sb  += jitter(s,        0.15)
                    lpa += jitter(l,        0.15)
                    mod += jitter(m * boost, 0.20)
                    vpa += jitter(v * boost, 0.25)

            mvpa_bts = jitter((mod + vpa) * 0.45, 0.20)
            sed_bts  = jitter(sb * 0.35, 0.20)
            acc_mg   = round((mod * 300 + vpa * 700 + lpa * 100 + sb * 20)
                             / (sb + lpa + mod + vpa + 0.001), 1)
            m60      = round(acc_mg * jitter(3.2, 0.15), 1)
            nonwear  = round(jitter(8.5, 0.30), 1)

            rows.append({
                "ID":              fname,
                "filename":        fname,
                "weekday":         weekday_name(d),
                "calendar_date":   d.isoformat(),
                "window_number":   win,
                "start_end_window":"06:00:00-06:00:00",
                "dur_day_total_IN_min":  round(sb,  1),
                "dur_day_total_LIG_min": round(lpa, 1),
                "dur_day_total_MOD_min": round(mod, 1),
                "dur_day_total_VIG_min": round(vpa, 1),
                "dur_day_MVPA_bts_10_min": round(mvpa_bts, 1),
                "dur_day_IN_bts_30_min":   round(sed_bts,  1),
                "ACC_day_mg":              acc_mg,
                "quantile_mostactive60min_mg": m60,
                "nonwear_perc_day":        nonwear,
                "boutcriter.in":           "0.9",
                "boutcriter.lig":          "0.8",
                "boutcriter.mvpa":         "0.8",
                "boutdur.in":              "30_20_10",
                "boutdur.lig":             "10_5_1",
                "boutdur.mvpa":            "10_5_1",
                "GGIRversion":             "3.3.4",
                "daytype":                 "WE" if is_weekend(d) else "WD",
            })
            win += 1
    return rows


# ── Segment summary ────────────────────────────────────────────────────────────

def make_segment_rows(school: str, meting: str) -> list[dict]:
    start_date   = METINGS[meting][school]
    participants = get_participants(school)
    prof         = SCHOOL_PROFILES[school]
    boost        = METING2_MVPA_BOOST if meting == "meting_2" else 1.0
    is_fallback  = school in ("school_3", "school_4")
    segments     = ["before_school", "in_class", "recess", "lunch", "after_school"]
    rows         = []

    for pid in participants:
        if meting == "meting_2" and pid in DROPOUT_MASKS[school]:
            continue

        fname = f"{pid}.csv"
        for day_i in range(1, 7):
            d = start_date + timedelta(days=day_i)
            if is_weekend(d):
                continue
            for seg in segments:
                sb, lpa, mpa, vpa = prof[seg]
                dur_IN  = round(jitter(sb,           0.18), 1)
                dur_LIG = round(jitter(lpa,          0.18), 1)
                dur_MOD = round(jitter(mpa * boost,  0.22), 1)
                dur_VIG = round(jitter(vpa * boost,  0.28), 1)
                dur_tot = round(dur_IN + dur_LIG + dur_MOD + dur_VIG, 1)
                rows.append({
                    "ID":              fname,
                    "school":          school,
                    "meting":          meting,
                    "calendar_date":   d.isoformat(),
                    "weekday":         weekday_name(d),
                    "segment":         seg,
                    "dur_IN_min":      dur_IN,
                    "dur_LIG_min":     dur_LIG,
                    "dur_MOD_min":     dur_MOD,
                    "dur_VIG_min":     dur_VIG,
                    "dur_total_min":   dur_tot,
                    "fallback_schedule": str(is_fallback).upper(),
                })
    return rows


# ── Write helpers ──────────────────────────────────────────────────────────────

def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"  wrote {len(rows):>6} rows → {path.relative_to(REPO_ROOT)}")


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    CUTLABEL         = "L56.3M191.6V695.8_T5A5"
    all_segment_rows = []
    total_participants = 0

    for meting in ("meting_1", "meting_2"):
        results_dir = OUT_BASE / meting / f"output_{meting}" / "results"

        p2_rows  = []
        p5d_rows = []
        p5p_rows = []

        for school in [f"school_{i}" for i in range(1, 7)]:
            p2_rows  += make_part2_rows(school, meting)
            p5d_rows += make_part5_day_rows(school, meting)
            p5p_rows += make_part5_pers_rows(school, meting)
            all_segment_rows += make_segment_rows(school, meting)

        write_csv(results_dir / "part2_daysummary.csv",                       p2_rows)
        write_csv(results_dir / f"part5_daysummary_WW_{CUTLABEL}.csv",        p5d_rows)
        write_csv(results_dir / f"part5_personsummary_WW_{CUTLABEL}.csv",     p5p_rows)

        n = len(set(r["ID"] for r in p2_rows))
        print(f"  {meting}: {n} participants")
        if meting == "meting_1":
            total_participants = n

    # Segment summary — one file for both metings, alongside processed/ not in ggir/
    write_csv(SEG_OUT, all_segment_rows)

    total_schools = len(N_PER_SCHOOL)
    print(f"\nDone. {total_participants} participants × {total_schools} schools.")
    print(f"Segment rows: {len(all_segment_rows)}")
    print(f"\nNext: run Rscript --vanilla r/pipeline/03_build_summaries.R")
    print(f"      (or run the full pipeline: Rscript --vanilla r/pipeline/run_all.R)")


if __name__ == "__main__":
    main()
