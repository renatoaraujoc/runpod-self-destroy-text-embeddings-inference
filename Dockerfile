FROM ghcr.io/huggingface/text-embeddings-inference:86-1.9

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
