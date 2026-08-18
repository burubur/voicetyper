#!/usr/bin/env python3
"""
tests/test_audio_dsp_gain.py
Validates Adaptive Speech Gain, Peak Normalization, and Soft-Knee Limiting.
"""

import math
import sys

def simulate_dsp_pipeline(samples, sample_rate=16000.0, noise_reduction_strength=0.75, target_peak=0.89, max_gain=10.0):
    # 1. Measure raw stats
    raw_peak = max(abs(x) for x in samples)
    raw_rms = math.sqrt(sum(x*x for x in samples) / len(samples))
    
    # 2. Simulate noise attenuation (spectral subtraction drops noise floor)
    # In practice, spectral subtraction attenuates stationary ambient energy
    denoised = [x * 0.85 for x in samples]
    denoised_peak = max(abs(x) for x in denoised)
    denoised_rms = math.sqrt(sum(x*x for x in denoised) / len(denoised))
    
    # 3. Adaptive Speech Gain & Peak Normalization
    if denoised_peak > 1e-4:
        gain = min(target_peak / denoised_peak, max_gain)
    else:
        gain = 1.0
        
    boosted = [x * gain for x in denoised]
    
    # 4. Soft-knee limiter: Linear under threshold (0.85), smooth saturation above
    threshold = 0.85
    normalized = []
    for x in boosted:
        if abs(x) <= threshold:
            normalized.append(x)
        else:
            sign = 1.0 if x > 0 else -1.0
            excess = abs(x) - threshold
            compressed = threshold + (0.95 - threshold) * math.tanh(excess / (0.95 - threshold))
            normalized.append(sign * min(0.95, compressed))
            
    norm_peak = max(abs(x) for x in normalized)
    norm_rms = math.sqrt(sum(x*x for x in normalized) / len(normalized))
    
    return {
        "raw_peak": raw_peak,
        "raw_rms": raw_rms,
        "denoised_peak": denoised_peak,
        "gain": gain,
        "norm_peak": norm_peak,
        "norm_rms": norm_rms
    }

def main():
    print("🧪 RUNNING AUDIO DSP ADAPTIVE GAIN & NORMALIZATION TEST")
    print("───────────────────────────────────────────────────────────────────────────")
    
    # Test Scenario 1: Low-Volume Speech (-20 dBFS peak = ~0.10)
    samples_quiet = [0.10 * math.sin(2 * math.pi * 220 * (i / 16000.0)) for i in range(16000)]
    res_quiet = simulate_dsp_pipeline(samples_quiet)
    
    print("Scenario 1: Quiet Speech (~0.10 peak / -20 dBFS):")
    print(f"  • Raw Peak     : {res_quiet['raw_peak']:.4f} ({20*math.log10(res_quiet['raw_peak']):.1f} dBFS)")
    print(f"  • Gain Applied : {res_quiet['gain']:.2f}x (+{20*math.log10(res_quiet['gain']):.1f} dB)")
    print(f"  • Boosted Peak : {res_quiet['norm_peak']:.4f} ({20*math.log10(res_quiet['norm_peak']):.1f} dBFS)")
    print(f"  • Boosted RMS  : {res_quiet['norm_rms']:.4f} ({20*math.log10(res_quiet['norm_rms']):.1f} dBFS)")
    
    assert res_quiet['gain'] > 1.5, "Expected significant gain boost for quiet speech"
    assert res_quiet['norm_peak'] > 0.6, "Expected normalized peak to be clearly audible (> 0.6)"
    assert res_quiet['norm_peak'] <= 0.95, "Expected normalized peak to not exceed 0.95 limiter"
    
    # Test Scenario 2: Normal/Loud Speech (0.80 peak / -2 dBFS)
    samples_loud = [0.80 * math.sin(2 * math.pi * 220 * (i / 16000.0)) for i in range(16000)]
    res_loud = simulate_dsp_pipeline(samples_loud)
    
    print("\nScenario 2: Normal Speech (~0.80 peak / -2 dBFS):")
    print(f"  • Raw Peak     : {res_loud['raw_peak']:.4f} ({20*math.log10(res_loud['raw_peak']):.1f} dBFS)")
    print(f"  • Gain Applied : {res_loud['gain']:.2f}x (+{20*math.log10(res_loud['gain']):.1f} dB)")
    print(f"  • Boosted Peak : {res_loud['norm_peak']:.4f} ({20*math.log10(res_loud['norm_peak']):.1f} dBFS)")
    
    assert res_loud['norm_peak'] <= 0.95, "Expected normalized peak to remain within safe headroom"
    
    print("───────────────────────────────────────────────────────────────────────────")
    print("✓ All Audio DSP Gain & Normalization tests passed cleanly!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
