# Actual Budget Server - Nix Flake

This flake provides the Actual Budget server with per-file bank sync support, packaged for NixOS.

## Quick Start

```bash
# Build the package
nix build .#actual-server

# Run the server
./result/bin/actual-server
```

## Using in Your NixOS Configuration

Add this flake to your inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    actual-fork.url = "git+https://github.com/yourusername/actual-fork.git";
  };

  outputs = { self, nixpkgs, actual-fork, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Apply the overlay (optional - replaces nixpkgs actual-server)
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ actual-fork.overlays.default ];
        })

        # Import the NixOS module
        actual-fork.nixosModules.default

        # Your configuration
        {
          services.actual = {
            enable = true;
            openFirewall = true;
            settings = {
              hostname = "0.0.0.0";
              port = 5006;
            };
          };
        }
      ];
    };
  };
}
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `services.actual.enable` | `false` | Enable the Actual Budget server |
| `services.actual.package` | `actual-server` | The package to use |
| `services.actual.settings.hostname` | `"127.0.0.1"` | Hostname to bind to |
| `services.actual.settings.port` | `5006` | Port to listen on |
| `services.actual.openFirewall` | `false` | Open firewall port |

## Important: Committed Files

**The following files are committed to the repo and required for the flake to work:**

- `.yarn-hash` - Hash of the Yarn offline cache (based on yarn.lock)
- `missing-hashes.json` - SHA512 hashes for platform-specific npm packages
- `flake.lock` - Locks the nixpkgs revision for reproducibility

**You should NOT need to regenerate these under normal circumstances.**

## Longevity & Stability

### Will this keep working?

**Yes, for at least a year,** with these caveats:

1. **Nixpkgs is pinned** to a specific revision in `flake.nix` (not using `nixos-unstable`). This ensures the build infrastructure doesn't change unexpectedly.

2. **The yarn hash** is committed. As long as `yarn.lock` in this repo doesn't change, the hash remains valid.

3. **The missing-hashes.json** contains content hashes of specific npm package versions. These remain valid as long as those package versions exist on npm.

### When would it break?

- If you update `yarn.lock` or `package.json` in this repo, you'll need to regenerate `.yarn-hash` using `./generate-yarn-hash.sh`
- If npm removes old package versions (rare, usually only for security issues)
- If you want to use a different nixpkgs revision, you may need to adjust the flake

### To update this flake to newer nixpkgs:

```bash
# Update nixpkgs input
nix flake update

# Test the build
nix build .#actual-server

# If it fails, you may need to adjust the flake or regenerate hashes
```

## Development

Enter the development shell:

```bash
nix develop
```

## Regenerating Hashes (Only if updating dependencies)

If you modify `yarn.lock` or `package.json`:

```bash
./generate-yarn-hash.sh
```

Then commit the updated `.yarn-hash` file.
