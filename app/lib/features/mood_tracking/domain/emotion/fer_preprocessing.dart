import 'dart:typed_data';

import 'fer_manifest.dart';

/// Preprocessing contract for the 224x224x3 ViT model.
///
/// Mirrors the training pipeline exactly: an already-aligned interleaved RGB
/// crop -> float32 NCHW, rescaled to [0,1] then normalised with mean/std 0.5,
/// which maps the input range to [-1,1].
///
/// * FP32/FP16 weights: float32 input, NCHW.
/// * INT8/uint8: only valid if a quantized artifact is ever shipped; the
///   current production artifact is fp16, so this path exists only to keep a
///   contract error instead of a silent misread if a different model is set.
///
/// Any shape/dtype mismatch vs the manifest is a thrown [FerContractError] —
/// the regression guard for the legacy 48/64 bug.
class FerPreprocessing {
  const FerPreprocessing(this.manifest);
  final FerManifest manifest;

  int get _hw => manifest.inputWidth * manifest.inputHeight;

  /// Convert an aligned interleaved RGB crop of exactly
  /// `inputWidth * inputHeight * 3` bytes to the float32 NCHW tensor the
  /// interpreter expects.
  Object toTensorInput(Uint8List alignedRgb, {required bool quantized}) {
    final out = Float32List(_hw * manifest.channels);
    toTensorInputInto(alignedRgb, out, quantized: quantized);
    return out;
  }

  /// Same conversion written into a caller-owned [out] buffer of exactly
  /// `inputWidth * inputHeight * channels` floats. The hot path reuses one
  /// buffer across frames instead of allocating ~600 KB per inference.
  void toTensorInputInto(Uint8List alignedRgb, Float32List out,
      {required bool quantized,}) {
    final hw = _hw;
    if (alignedRgb.length != hw * 3) {
      throw FerContractError(
          'aligned RGB crop ${alignedRgb.length} != ${manifest.inputWidth}x${manifest.inputHeight}x3',);
    }
    if (out.length != hw * manifest.channels) {
      throw FerContractError(
          'tensor buffer ${out.length} != ${manifest.inputWidth}x${manifest.inputHeight}x${manifest.channels}',);
    }
    if (quantized) {
      // The shipped model is not quantized; a uint8 path would be wrong for
      // it. Reject loudly rather than feed a 3-channel uint8 buffer.
      throw FerContractError(
          'quantized input requested but the RGB/NCHW contract requires float32',);
    }

    for (var i = 0; i < hw; i++) {
      final r = alignedRgb[i * 3];
      final g = alignedRgb[i * 3 + 1];
      final b = alignedRgb[i * 3 + 2];
      // (x/255 - 0.5) / 0.5 == (x/255)*2 - 1, inlined for the hot loop.
      out[i] = r * (2.0 / 255.0) - 1.0;
      out[hw + i] = g * (2.0 / 255.0) - 1.0;
      out[2 * hw + i] = b * (2.0 / 255.0) - 1.0;
    }
  }

  /// Validate a live interpreter tensor against the manifest contract.
  void validateTensor(
      {required List<int> shape,
      required String dtype,
      required bool quantized,}) {
    final want = [
      1,
      manifest.channels,
      manifest.inputHeight,
      manifest.inputWidth,
    ];
    if (shape.length != 4 ||
        shape[0] != 1 ||
        shape[1] != want[1] ||
        shape[2] != want[2] ||
        shape[3] != want[3]) {
      throw FerContractError(
          'interpreter input $shape != manifest $want (NCHW) — refusing to run',);
    }
    if (quantized && dtype != 'uint8' && dtype != 'int8') {
      throw FerContractError(
          'quant model expects uint8/int8 input, got $dtype',);
    }
    if (!quantized && dtype != 'float32' && dtype != 'float16') {
      throw FerContractError('float model expects float input, got $dtype');
    }
  }
}

class FerContractError extends Error {
  FerContractError(this.message);
  final String message;
  @override
  String toString() => 'FerContractError: $message';
}
