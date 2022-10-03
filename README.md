Add gcroots for all inputs of a flake.\
Also supports zipball inputs (introduced in
[Nix#6530](https://github.com/NixOS/nix/pull/6530)).

**Note:** Non-flake inputs are currently not supported because they can't be fetched
with `builtins.getFlake`

### Usage
```bash
# Add binary to PATH
nix shell github:erikarvstedt/flake-create-gcroots

flake-create-gcroots /my/flake/flake.lock

# Alternative: Use flake in PWD
cd /my/flake; flake-create-gcroots

# Output:
# Created 3 links in /nix/var/nix/gcroots/per-user/me/flake-inputs/home/me/src/myflake:
# systemlib:   /nix/store/051qb8iss8h279lsp4bpqxj2s7qkda93-source
# nixpkgs:     /nix/store/jvbmqbp01zcri5a6h1s797w0m2px548h-source (zipball)
# flake-utils: /nix/store/mx2d8rbgsmqhcb45ns58bsmz8hv3cvsn-source (zipball)
```

### How it works
1. Parse `flake.lock`
2. Retrieve store paths that should be gcrooted:\
   Fetch flake input data via `builtins.getFlake` in a single call to `nix eval --expr`.

   - For inputs that are always added to the store when they are accessed (like type
    `git`), the store path is directly retrieved from the evaluation.
   - zipball inputs are referenced via `toString`, so that the backing zip files are
     added to the store without getting extracted.\
     The zip file store paths are then retrieved by querying
    `~/.cache/nix/fetcher-cache-v2.sqlite`.
3. Create dir `/nix/var/nix/gcroots/per-user/${current user}/${path to flake}` and
   add gcroots to it.
