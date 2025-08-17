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

To login into LVFS instance use user `sign-test@fwupd.org` and password `Pa$$w0rd`.

> Note: default user and password is initialized from `lvfs/dbutils.py:init_db`
> and is always as above.

![](img/lvfs_welcome_screen.png)

## Updating LVFS release

First, you need to manually edit `nix/lvfs.nix`. In the section:

```nix
src = deps.fetchFromGitLab {
  owner = "fwupd";
  repo = "lvfs-website";
  rev = "ed377f14b8e51d8bbe6edd57d2aa2201622bf732";
  hash = "sha256-jrSQwxZcyBxy+wZ8spRUL+MPr1JXozOdBzVGjOt7GNg=";
};
```

set `rev` to latest commit and `hash` to `sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`:

```nix
src = deps.fetchFromGitLab {
  owner = "fwupd";
  repo = "lvfs-website";
  rev = "ed377f14b8e51d8bbe6edd57d2aa2201622bf732";
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
};
```

Run

```shell
nix run .#default.lock
```

And look valid hash in build output

```
error: hash mismatch in fixed-output derivation '/nix/store/fiajb23j5ancvz7gaibhq6ba8jidywg4-source.drv':
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    sha256-jrSQwxZcyBxy+wZ8spRUL+MPr1JXozOdBzVGjOt7GNg=
```

Update `nix/lvfs.nix` with the correct hash and once again run

```shell
nix run .#default.lock
```

The command should succeed now. Before committing changes make sure the
container does build:

```shell
nix build -L --no-link
```
