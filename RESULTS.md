# Results

All numbers measured on the machine described in the [README](README.md), on 2026-11-25,
with an idle GPU (no server process holding VRAM).

## Method

- `llama-bench -m <gguf> -ngl 99 -p 512 -n 128 -r 3`, i.e. full offload, 512-token prompt
  processing, 128-token generation, 3 repetitions; `±` is llama-bench's own standard
  deviation across repetitions.
- Same GGUF files for both builds; only the engine changed.
- One model family (Inkling 2 Mini), one GPU, one quant set. No per-tensor overrides, no
  thread tuning, no `--no-mmap`.

## Inkling 2 Mini, llama.cpp Vulkan, RX 6800 XT 16 GB

| llama.cpp | model | size | pp512 t/s | tg128 t/s |
|---|---|---|---:|---:|
| e6d624b (0.6.0 line) | `Inkling-2-Mini-UD-Q3_K_XL.gguf` | 12.68 GiB | 537.87 ± 3.69 | 27.40 ± 0.04 |
| **b12669** | `Inkling-2-Mini-UD-Q3_K_XL.gguf` | 12.68 GiB | **810.33 ± 4.17** | **52.17 ± 0.31** |
| **b12669** | `Inkling-2-Mini-IQ4_NL.gguf` | 16.41 GiB | 114.73 ± 0.49 | 29.62 ± 0.02 |

Same weights, same flags: **+50.7% prompt, +90.4% generation** from the engine upgrade.

`IQ4_NL` is 16.41 GiB — larger than the card's 16 GB — so the driver spills to system RAM and
prompt processing collapses (114.73 vs 810.33 tok/s). Generation loses less because it is
bandwidth-bound rather than compute-bound. On a 16 GB card the 12.68 GiB file is the one that
stays resident.

Raw logs: [bench/logs](bench/logs/). Re-run with [`bench/bench.sh`](bench/bench.sh).

Run-to-run spread on this box is a few percent between sessions (an earlier run of the same
two configurations gave 780.69 / 44.94 for b12669 and 552.89 / 27.11 for e6d624b). Compare
numbers from one session, not across sessions.

## Engines considered

**Strata** (HIP/CUDA engine, own `.strata` packs, built-in DSpark speculative drafting) was
checked and rejected for this hardware:

- No Vulkan backend; AMD means HIP, which needs ROCm 7+ — and ROCm 10.1 on this machine
  segfaults on `hipStreamCreate`.
- Its RDNA2 path (`gfx1030`) has no matrix cores and no hipBLASLt kernels: the prompt path's
  FP16-in/FP32-out and BF16 GEMMs fall back to generic rocBLAS kernels, which its own docs
  put at ~6.6x slower. Measured RDNA2 prefill in its documentation: 246 tok/s at 2K and
  330–339 tok/s at 8K on an RX 6900 XT — against 810 tok/s here on Vulkan.
- Its Inkling numbers on AMD: RX 6700 XT 12 GB at 17.8 tok/s decode / 68.5 prompt; RX 7900 XT
  at 54.7 / 2,685; R9700 at 99–106 / 3,982. There is no RX 6800/6900 row.
- Its large wins over llama.cpp come from CPU-spill regimes (70 GiB models on 12–16 GB
  cards, where llama.cpp managed ~9 tok/s). With the model fully resident that regime does
  not apply.

The one idea worth borrowing is speculative drafting. llama.cpp b12669 exposes
`--spec-type draft-dspark` and Inkling 2 Mini ships a small DSpark drafter (`dspark-*.gguf`);
that is untested here and would be the next thing to measure.
