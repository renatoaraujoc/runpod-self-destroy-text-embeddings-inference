ARG BASE_IMAGE=ghcr.io/huggingface/text-embeddings-inference:86-1.9

FROM ${BASE_IMAGE}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
