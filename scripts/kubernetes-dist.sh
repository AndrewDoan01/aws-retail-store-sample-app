#!/bin/bash

set -euo pipefail

if [ -z "${IMAGE_TAG:-}" ]; then
  echo "Error: Set IMAGE_TAG environment variable"
  exit 1
fi

workdir=$(mktemp -d)
outfile=$(mktemp)

trap 'rm -rf "$workdir" "$outfile"' EXIT

cp -R src/app/kustomize "$workdir"

sed -i "s/newTag: latest/newTag: ${IMAGE_TAG}/g" "$workdir/kustomize/overlays/release/kustomization.yaml"

kubectl kustomize "$workdir/kustomize/overlays/release" > "$outfile"

mkdir -p dist/kubernetes

cp "$outfile" dist/kubernetes/kubernetes.yaml
