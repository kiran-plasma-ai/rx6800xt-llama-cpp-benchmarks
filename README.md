# RX 6800 XT llama.cpp Vulkan benchmarks

![llama.cpp](https://img.shields.io/badge/llama.cpp-b12669-blue)
![backend](https://img.shields.io/badge/backend-Vulkan%20%2F%20RADV-red)
![GPU](https://img.shields.io/badge/GPU-RX%206800%20XT%2016%20GB-orange)

**A 26.4B Mixture-of-Experts model writing 52 tokens a second on a 2020 consumer card —
through Vulkan. No ROCm, no CUDA, no cloud.**

Measured llama.cpp Vulkan benchmarks for Inkling 2 Mini (26.4B MoE, 3.4B active) on an AMD
RX 6800 XT 16 GB (RDNA2, `gfx1030`): what the engine build is worth, which quantization fits,
and why the usual "offload experts to CPU" recipe loses on this card. Raw `llama-bench` logs
included.

**Hardware:** Ryzen 5 5600X, 32 GB RAM, AMD Radeon RX 6800 XT 16 GB.
**Models:** Inkling 2 Mini UD-Q3_K_XL (12.68 GiB) and IQ4_NL (16.41 GiB), Unsloth Dynamic.
**Software:** llama.cpp b12669 and e6d624b, `GGML_VULKAN=ON`, Vulkan/RADV. HIP disabled:
ROCm 10.1 segfaults on `hipStreamCreate` here, and Vulkan does not need it.

## Headline

Same weights, same flags, two engine builds:

| llama.cpp | model | pp512 t/s | tg128 t/s |
|---|---|---:|---:|
| e6d624b | Inkling 2 Mini UD-Q3_K_XL, 12.68 GiB | 537.87 | 27.40 |
| **b12669** | Inkling 2 Mini UD-Q3_K_XL, 12.68 GiB | **810.33** | **52.17** |

**+50.7% prompt processing, +90.4% generation from the rebuild alone.** One engine upgrade
nearly doubled what the silicon does.

The 16.41 GiB IQ4_NL does not fit in 16 GB; the driver spills to system RAM and prefill
collapses to 114.73 t/s. On a 16 GB card the 12.68 GiB file is the one that stays resident.
Full tables, method and caveats: [RESULTS.md](RESULTS.md).

## The expert-offload recipe, measured

A published recipe for 12–16 GB cards keeps the looped expert blocks on the GPU and pushes
only the prelude experts to the CPU (`-ot "blk\.([0-5])\.ffn_.*_exps.*=CPU"`). Measured here:

- On the file that **doesn't fit** (IQ4_NL): +13% generation, −13% prefill versus letting the
  driver spill. Marginal.
- On the file that **already fits** (Q3_K_XL): a straight loss — prefill −26%, generation
  −35%. Do not CPU-offload experts on a 16 GB card with a resident 12.68 GiB model.
- The recipe's headline number (46 t/s with a 16.6 GB file) does not reproduce on RDNA2.

## Reproduce

```sh
# build llama.cpp with Vulkan into ~/.local/share/llama.cpp
bench/build-llama-vulkan.sh b12669 ~/.local/share/llama.cpp

# bench every GGUF with the same flags, keeping the full log
bench/bench.sh ~/models/inkling2/Inkling-2-Mini-UD-Q3_K_XL.gguf
```

The build script fetches Vulkan headers into `/tmp` when the distro has none, clones
`--depth 1 --branch <tag>`, configures `-G Ninja -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
-DLLAMA_CURL=OFF`, and installs. Installs strip RUNPATH, so binaries need
`LD_LIBRARY_PATH=<prefix>/lib`; both scripts set it.

## Serve it

[`systemd/llama-server-inkling.service`](systemd/llama-server-inkling.service) is a systemd
user unit: OpenAI-compatible endpoint on port 8882, `-ngl 99`, `-c 131072` with `q8_0` KV
cache, `--jinja`. It binds `127.0.0.1` because llama-server has no authentication.

Inkling-specific flags and the dead ends (the stripped-RUNPATH "build failure", the empty
`llama-bench | grep`, gated model repos, why Strata does not help on RDNA2) are in
[docs/SETUP-NOTES.md](docs/SETUP-NOTES.md).

## Next

llama.cpp b12669 exposes `--spec-type draft-dspark` and Inkling 2 Mini ships a small DSpark
drafter (`dspark-*.gguf`). Speculative drafting is the obvious next multiplier on top of
52 t/s — untested here so far.

## Scope

One machine, one model family, one GPU, no per-tensor overrides or thread tuning. These are
not claims about other cards; on RDNA3/RDNA4 the matrix cores and a hipBLASLt or Vulkan
tuning table change the picture substantially.

## License

[MIT](LICENSE)
