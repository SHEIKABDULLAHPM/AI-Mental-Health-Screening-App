#!/usr/bin/env python3
"""Lightweight FER model evaluation + quantization tooling.

Covers pipeline steps 6 (model size), 7 (quantization) and 11 (threshold
justification data) of the Camera Mood Check-in production plan.

Subcommands:
  report    Offline static analysis. Needs only the manifest + model file.
            Verifies manifest metrics, requotes the INT8 rejection, prints the
            candidate decision matrix and the BEFORE/AFTER benchmark skeleton.
  convert   Build FP16 (+ optional INT8) TFLite from a trained lightweight
            checkpoint. Needs tensorflow. The checkpoint must come from a
            model TRAINED/EXPORTED for the target resolution -- never a
            resized ViT.
  evaluate  Score a TFLite artifact on a labeled validation dir
            (<class>/*.jpg) and time inference. Needs tensorflow (or
            tflite_runtime) + numpy + pillow.

Replacement policy (enforced by this script's exit codes, not by opinion):
a candidate replaces the 172 MB ViT only when evaluate shows BOTH
  accuracy within the acceptance gate AND latency/size within budget
on representative hardware. File size alone never qualifies a model.

Threshold policy: this script reports raw per-class recall/precision; any
minimumConfidence/minimumMargin change must cite these numbers.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

CANONICAL = ["anger", "disgust", "fear", "happy", "neutral", "sad", "surprise"]

# Production budgets (see task steps 6/7/16).
SIZE_MB_PREFERRED = 30.0
SIZE_MB_IDEAL = 15.0
INFER_MS_BUDGET = 200.0
# Accuracy gate for a replacement vs the incumbent ViT (macro-F1 on the same
# 175-image stratified validation split, seed 42).
MACRO_F1_GATE = 0.58
WORST_RECALL_GATE = 0.35


def load_manifest(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def cmd_report(args: argparse.Namespace) -> int:
    m = load_manifest(args.manifest)
    model_path = os.path.join(os.path.dirname(args.manifest),
                               m["productionArtifact"])
    size_mb = os.path.getsize(model_path) / (1024 * 1024)

    print("=== INCUMBENT (current production model) ===")
    print(f"modelId        : {m['modelId']} v{m['version']}")
    print(f"architecture   : {m['architecture']}")
    print(f"artifact       : {m['productionArtifact']} "
          f"({size_mb:.1f} MB, precision={m['precision']})")
    print(f"input          : {m['inputWidth']}x{m['inputHeight']}x{m['channels']} "
          f"{m['colorSpace']} {m['normalization']} {m['tensorLayout']}")
    print(f"params         : "
          f"{m.get('provenance', {}).get('parameterCount', '?')}")

    # Verify manifest test metrics from the raw confusion matrix (trust, but
    # verify -- these numbers justify the confidence thresholds).
    cm = m["testConfusionMatrix"]
    total = sum(sum(row) for row in cm)
    trace = sum(cm[i][i] for i in range(7))
    acc = trace / total
    print(f"\n=== VALIDATION (n={total}, 25/class, seed 42) ===")
    print(f"reported acc   : {m['testAccuracy']:.4f}")
    print(f"recomputed acc : {acc:.4f} "
          f"({'OK' if abs(acc - m['testAccuracy']) < 1e-9 else 'MISMATCH'})")
    print("per-class recall (row) / precision (col):")
    per = m["testPerClass"]
    ok = True
    for i, c in enumerate(CANONICAL):
        row_sum = sum(cm[i])
        col_sum = sum(cm[r][i] for r in range(7))
        recall = cm[i][i] / row_sum
        prec = cm[i][i] / col_sum
        r_ok = abs(recall - per[c]["recall"]) < 1e-9
        p_ok = abs(prec - per[c]["precision"]) < 1e-3
        ok &= r_ok and p_ok
        print(f"  {c:8s} recall={recall:.3f} (manifest {per[c]['recall']:.3f} "
              f"{'OK' if r_ok else 'MISMATCH'}) "
              f"precision={prec:.3f} (manifest {per[c]['precision']:.3f} "
              f"{'OK' if p_ok else 'MISMATCH'})")
    print(f"macro-F1       : {m['testMacroF1']:.4f} "
          f"(gate >= {MACRO_F1_GATE}: "
          f"{'PASS' if m['testMacroF1'] >= MACRO_F1_GATE else 'FAIL'})")
    worst = min(per[c]["recall"] for c in CANONICAL)
    print(f"worst recall   : {worst:.3f} "
          f"(gate >= {WORST_RECALL_GATE}: "
          f"{'PASS' if worst >= WORST_RECALL_GATE else 'FAIL'})")
    if not ok:
        print("ERROR: manifest metrics do not match confusion matrix.")
        return 2

    print("\n=== QUANTIZATION (manifest parity record) ===")
    print(f"int8 note      : {m['parity']['int8_note']}")
    print("decision       : INT8 REJECTED (12.0% acc, happy recall 0.000). "
          "Keep FP16. Re-test INT8 only with quantization-aware training.")

    print("\n=== ROOT CAUSE (why inference takes seconds on SM-M325F) ===")
    print("ViT-B/16 = 85.8M params, ~17.6 GFLOP/forward @224, 197-token "
          "attention (O(n^2) per layer x12). Exynos 850 CPU has no vector "
          "throughput for this: measured host latency is already "
          f"{m['testSet']['hostLatencyMsPerImage']}ms/image on a desktop CPU; "
          "a phone CPU is several x slower => seconds/frame. GPU delegate "
          "fails (Mali-G52, unsupported ops) => CPU fallback. The model "
          "architecture -- not the app code -- dominates end-to-end latency.")

    print("\n=== CANDIDATE MATRIX (evaluate before adopting) ===")
    print(f"{'candidate':28s} {'params':>8s} {'est MB':>8s} "
          f"{'input':>9s} {'status'}")
    print(f"{'MobileNetV3-Small FER':28s} {'2.5M':>8s} {'~10':>8s} "
          f"{'112x112':>9s} PENDING eval")
    print(f"{'EfficientNet-Lite0 FER':28s} {'4.7M':>8s} {'~18':>8s} "
          f"{'112x112':>9s} PENDING eval")
    print(f"{'ViT-B/16 (incumbent)':28s} {'85.8M':>8s} "
          f"{size_mb:8.1f} {'224x224':>9s} SHIPPED (slow)")
    print(f"\nbudgets: size < {SIZE_MB_PREFERRED:.0f} MB "
          f"(ideal < {SIZE_MB_IDEAL:.0f}), infer < {INFER_MS_BUDGET:.0f} ms, "
          f"macro-F1 >= {MACRO_F1_GATE}, worst recall >= {WORST_RECALL_GATE}")

    print("\n=== BEFORE/AFTER SKELETON (fill ON-DEVICE on SM-M325F) ===")
    print("run: flutter test integration_test/fer_bench_test.dart -d <id>")
    print("     + collect FER_PERF / FER_PROFILE / FER_BENCH logcat lines")
    rows = [
        ("Model size", f"{size_mb:.1f} MB", "?"),
        ("Input size", "224x224", "?"),
        ("Backend", "cpu (gpu fails)", "?"),
        ("Inference latency", "? ms (seconds, unmeasured)", "? ms"),
        ("Total latency", "? ms", "? ms"),
        ("Effective FPS", "?", "?"),
        ("Memory", "? MB", "? MB"),
        ("Dropped frames", "?", "?"),
    ]
    for c in CANONICAL:
        rows.append((f"{c.capitalize()} recall",
                     f"{per[c]['recall']:.3f}", "?"))
    w = max(len(r[0]) for r in rows)
    print(f"  {'metric':<{w}}  {'CURRENT':>10s}  {'OPTIMIZED':>10s}")
    for name, cur, opt in rows:
        print(f"  {name:<{w}}  {cur:>10s}  {opt:>10s}")
    print("\nDo NOT claim production-ready until the OPTIMIZED column has "
          "measured SM-M325F numbers.")
    return 0


def _require_tf():
    try:
        import tensorflow as tf  # type: ignore
        return tf
    except ImportError:
        print("ERROR: convert/evaluate need tensorflow "
              "(pip install tensorflow-cpu) or tflite_runtime.",
              file=sys.stderr)
        sys.exit(3)


def cmd_convert(args: argparse.Namespace) -> int:
    tf = _require_tf()
    # Lazy import: only needed for the conversion path.
    from tensorflow import keras  # type: ignore
    res = args.resolution
    print(f"loading checkpoint {args.checkpoint} (resolution {res}x{res}) ...")
    model = keras.models.load_model(args.checkpoint)
    # Sanity: refuse to convert a 224-model relabeled as lightweight.
    ih, iw = model.input_shape[1], model.input_shape[2]
    if (ih, iw) != (res, res):
        print(f"ERROR: checkpoint input is {iw}x{ih}, not {res}x{res}. "
              "Only models TRAINED for the target resolution qualify.",
              file=sys.stderr)
        return 2
    out = args.out or f"fer_mobilenetv3_{res}.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_fp16 = converter.convert()
    with open(out, "wb") as f:
        f.write(tflite_fp16)
    print(f"wrote {out} ({len(tflite_fp16) / 1e6:.1f} MB, fp16)")
    if len(tflite_fp16) / 1e6 > SIZE_MB_PREFERRED:
        print(f"WARNING: exceeds {SIZE_MB_PREFERRED:.0f} MB budget.")
    if args.int8:
        if not args.representative:
            print("ERROR: --int8 needs --representative <dir> "
                  "(calibration images).", file=sys.stderr)
            return 2
        converter2 = tf.lite.TFLiteConverter.from_keras_model(model)
        converter2.optimizations = [tf.lite.Optimize.DEFAULT]
        converter2.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter2.inference_input_type = tf.uint8
        converter2.inference_output_type = tf.uint8
        rep_dir = args.representative

        def rep_data():
            import numpy as np
            from PIL import Image
            files = [os.path.join(dp, f) for dp, _, fs in os.walk(rep_dir)
                     for f in fs if f.lower().endswith((".jpg", ".png"))]
            for fp in files[:300]:
                img = Image.open(fp).convert("RGB").resize((res, res))
                yield [np.expand_dims(np.asarray(img, dtype=np.float32), 0)]
        converter2.representative_dataset = rep_data
        tflite_int8 = converter2.convert()
        out8 = out.replace(".tflite", "_int8.tflite")
        with open(out8, "wb") as f:
            f.write(tflite_int8)
        print(f"wrote {out8} ({len(tflite_int8) / 1e6:.1f} MB, int8)")
        print("INT8 MUST pass `evaluate` (accuracy gate) before use -- "
              "the ViT int8 attempt scored 12% and was rejected.")
    return 0


def _load_interpreter(tflite_path: str):
    try:
        from tflite_runtime.interpreter import Interpreter  # type: ignore
    except ImportError:
        tf = _require_tf()
        Interpreter = tf.lite.Interpreter
    return Interpreter(model_path=tflite_path)


def cmd_evaluate(args: argparse.Namespace) -> int:
    import numpy as np
    from PIL import Image
    interp = _load_interpreter(args.tflite)
    interp.allocate_tensors()
    inp, outp = interp.get_input_details()[0], interp.get_output_details()[0]
    _, h, w, _ = inp["shape"]
    print(f"model input: {w}x{h}, classes: {outp['shape']}")
    # Confusion over <val-dir>/<class>/*.jpg (class names = CANONICAL ids).
    cm = [[0] * 7 for _ in range(7)]
    lat = []
    for ci, c in enumerate(CANONICAL):
        d = os.path.join(args.val_dir, c)
        if not os.path.isdir(d):
            print(f"WARNING: missing class dir {d}, skipping.")
            continue
        files = [os.path.join(d, f) for f in sorted(os.listdir(d))
                 if f.lower().endswith((".jpg", ".jpeg", ".png"))]
        for fp in files:
            img = Image.open(fp).convert("RGB").resize((w, h))
            x = np.expand_dims(np.asarray(img), 0)
            if inp["dtype"] == np.uint8:
                feed = x.astype(np.uint8)
            else:
                feed = (x.astype(np.float32) / 255.0) * 2.0 - 1.0  # [-1,1]
                if inp["dtype"] == np.float16:
                    feed = feed.astype(np.float16)
            interp.set_tensor(inp["index"], feed)
            import time
            t0 = time.perf_counter()
            interp.invoke()
            lat.append((time.perf_counter() - t0) * 1000)
            y = np.asarray(interp.get_tensor(outp["index"])[0], dtype=float)
            # Logits-or-probs safe decode (mirrors decodeOutput in Dart).
            if y.min() < 0 or abs(y.sum() - 1.0) > 1e-3:
                e = np.exp(y - y.max())
                y = e / e.sum()
            pred = int(np.argmax(y))
            cm[ci][pred] += 1
    total = sum(sum(r) for r in cm)
    trace = sum(cm[i][i] for i in range(7))
    acc = trace / max(total, 1)
    prec = []
    rec = []
    for i in range(7):
        rs, cs = sum(cm[i]), sum(cm[r][i] for r in range(7))
        rec.append(cm[i][i] / rs if rs else 0.0)
        prec.append(cm[i][i] / cs if cs else 0.0)
    f1 = [2 * p * r / (p + r) if (p + r) else 0.0
          for p, r in zip(prec, rec)]
    macro = sum(f1) / 7
    lat.sort()
    med = lat[len(lat) // 2] if lat else float("nan")
    size_mb = os.path.getsize(args.tflite) / 1e6
    print(f"\naccuracy={acc:.4f} macroF1={macro:.4f} "
          f"worstRecall={min(rec):.3f} medianInferMs={med:.1f} "
          f"sizeMB={size_mb:.1f}")
    for i, c in enumerate(CANONICAL):
        print(f"  {c:8s} recall={rec[i]:.3f} prec={prec[i]:.3f} f1={f1[i]:.3f}")
    gates = (macro >= MACRO_F1_GATE and min(rec) >= WORST_RECALL_GATE
             and size_mb <= SIZE_MB_PREFERRED and med <= INFER_MS_BUDGET)
    print(f"\nACCEPT: macroF1>={MACRO_F1_GATE} worstRecall>={WORST_RECALL_GATE} "
          f"size<={SIZE_MB_PREFERRED:.0f}MB inferMs<={INFER_MS_BUDGET:.0f}ms "
          f"=> {'PASS' if gates else 'FAIL'}")
    # JSON for the benchmark table.
    print(json.dumps({"accuracy": acc, "macroF1": macro,
                      "worstRecall": min(rec), "medianInferMs": med,
                      "sizeMB": size_mb,
                      "perClass": {c: {"recall": rec[i], "precision": prec[i],
                                       "f1": f1[i]}
                                   for i, c in enumerate(CANONICAL)}}))
    return 0 if gates else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("report", help="offline static analysis")
    r.add_argument("--manifest", default="app/assets/models/"
                   "vit_fer_manifest.json")
    c = sub.add_parser("convert", help="checkpoint -> TFLite fp16[/int8]")
    c.add_argument("--checkpoint", required=True)
    c.add_argument("--resolution", type=int, default=112)
    c.add_argument("--out", default=None)
    c.add_argument("--int8", action="store_true")
    c.add_argument("--representative", default=None)
    e = sub.add_parser("evaluate", help="score a TFLite on a val dir")
    e.add_argument("--tflite", required=True)
    e.add_argument("--val-dir", required=True)
    args = ap.parse_args()
    if args.cmd == "report":
        return cmd_report(args)
    if args.cmd == "convert":
        return cmd_convert(args)
    return cmd_evaluate(args)


if __name__ == "__main__":
    sys.exit(main())
