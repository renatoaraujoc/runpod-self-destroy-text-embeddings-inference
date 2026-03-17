# RunPod-compatible Text Embeddings Inference with idle auto-shutdown

Thin wrapper around [HuggingFace TEI](https://github.com/huggingface/text-embeddings-inference) that adds an idle-timeout watchdog. When no embedding requests are received for a configurable duration, the container self-terminates the RunPod pod via the REST API.

## Usage

All standard TEI args are passed through. Add `--self-destroy-in-secs <seconds>` to enable the watchdog.

```
--model-id Qwen/Qwen3-Embedding-8B --port 8080 --dtype float16 --max-batch-tokens 131072 --max-client-batch-size 128 --self-destroy-in-secs 1800
```

Without `--self-destroy-in-secs`, the container behaves identically to the upstream TEI image.

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `RUNPOD_POD_ID` | No (auto-injected) | Automatically set by RunPod inside every pod — do NOT set this manually. |
| `RUNPOD_API_KEY` | Yes (when watchdog enabled) | RunPod API key. Must be set as a template env var in the RunPod console. |

## How it works

1. `entrypoint.sh` parses `--self-destroy-in-secs` from the args, passes everything else to `text-embeddings-router`.
2. TEI starts normally in the background.
3. If watchdog is enabled, a background loop checks TEI's `/metrics` endpoint every 60s.
4. If `te_request_count` hasn't changed for the configured duration, the pod self-deletes via `DELETE https://rest.runpod.io/v1/pods/$RUNPOD_POD_ID`.

