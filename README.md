# libertai-iac

Less IaC than it is collection of scripts.
Allows you to easily:

- Download and manage Gguf models from Hugging Face
- Push models to Aleph as immutable SquashFs images
- Build and deploy Llama.Cpp on an Aleph VM, loading models from as immutable volumes

## Requirements

- docker OR podman
- huggingface-cli
- git
- jq
- aleph cli, available on pip!
- squashfs-tools, including mksquashfs and unsquashfs

## Setup

All you need to get started is to copy `.env.example` to `.env`.

```bash
cp .env.example .env
```

The repository comes with suitable defaults for deploying a
simple Llama.Cpp server on Aleph, but you can modify these to
suit your needs. See the `.env.example` file for more information.

## Usage

Pull the configured model so its available locally

```bash
./bin/lib.sh pull-model
```

Push the configured model to Aleph as an object

```bash
./bin/lib.sh push-model
```

Pull a suitable runtime locally to build and deploy Llama.Cpp

```bash
./bin/lib.sh pull-runtime
```

And finally, push the runtime to Aleph, loading our configured model as a volume

```bash
./bin/lib.sh push-engine
```
