# Creating custom LVFS instance

Before proceding make sure you have [Nix](https://nixos.org/download/) installed.
As a next step generate secrets required by LVFS server:

```shell
nix run .#gen-secrets
```

Then, build the container and copy it to Docker

```shell
nix run .#container-lvfs.copyToDockerDaemon
```

Run it

```shell
docker compose up
```
