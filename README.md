# RunPod-compatible Text Embeddings Inference with idle auto-shutdown

Thin wrapper around [HuggingFace TEI](https://github.com/huggingface/text-embeddings-inference) that adds an idle-timeout watchdog. When no embedding requests are received for a configurable duration, the container self-terminates the RunPod pod via the REST API.

## Supported architectures

Based on TEI `1.9`. Each architecture has its own image tag.

| Tag | Compute Cap | Architecture | GPUs | Status |
|---|---|---|---|---|
| `default` | 8.0 | Ampere | A100, A30 | Stable |
| `86` | 8.6 | Ampere | A10, A40, A6000, RTX 3000 series | Stable |
| `89` | 8.9 | Ada Lovelace | RTX 4090, L4, L40, L40S | Stable |
| `hopper` | 9.0 | Hopper | H100 | Stable |
| `turing` | 7.5 | Turing | T4, RTX 2000 series | Experimental |
| `100` | 10.0 | Blackwell | B200, GB200 | Experimental |
| `120` | 12.0 | Blackwell | GeForce RTX 5000 series | Experimental |

Image format: `ghcr.io/renatoaraujoc/runpod-self-destroy-text-embeddings-inference:{arch}-{tei_version}-{version}`

Example: `ghcr.io/renatoaraujoc/runpod-self-destroy-text-embeddings-inference:86-1.9-v1.0.0`

## Usage

All standard TEI args are passed through. Add `--self-destroy-in-secs <seconds>` to enable the watchdog.

```
--model-id Qwen/Qwen3-Embedding-8B --port 8080 --dtype float16 --max-batch-tokens 131072 --max-client-batch-size 128 --self-destroy-in-secs 900
```

Without `--self-destroy-in-secs`, the container behaves identically to the upstream TEI image.

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `RUNPOD_POD_ID` | No (auto-injected) | Automatically set by RunPod inside every pod — do NOT set this manually. |
| `RUNPOD_API_KEY_OVERRIDE` | Yes (when watchdog enabled) | RunPod API key for pod self-deletion. Must be set as a template env var. **Do NOT use `RUNPOD_API_KEY`** — RunPod overrides it with an internal key. |

## How it works

1. `entrypoint.sh` parses `--self-destroy-in-secs` from the args, passes everything else to `text-embeddings-router`.
2. TEI starts normally in the background.
3. If watchdog is enabled, it waits for TEI's `/health` endpoint to return 200 before starting the idle countdown.
4. A background loop checks TEI's `/metrics` endpoint every 60s.
5. If `te_request_count` hasn't changed for the configured duration, the pod self-deletes via `DELETE https://rest.runpod.io/v1/pods/$RUNPOD_POD_ID` with 5 retries every 30s.
6. Both `--self-destroy-in-secs` and `RUNPOD_API_KEY_OVERRIDE` must be provided for the watchdog to activate. If only one is set, the watchdog logs a warning and stays disabled.
