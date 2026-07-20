{
  description = "Actual Budget Server - Fork with per-file bank sync support";

  inputs = {
    # Pinned nixpkgs for stability - this revision is known to work
    # Update this if you need newer packages, but it may require adjusting the flake
    nixpkgs.url = "github:NixOS/nixpkgs/18b9261cb3294b6d2a06d03f96872827b8fe2698";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Read the yarn hash from a file if it exists, otherwise use fakeHash
      yarnHashFile = ./.yarn-hash;
      yarnHash = if builtins.pathExists yarnHashFile
        then builtins.readFile yarnHashFile
        else "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

      mkPackage = pkgs:
        let
          inherit (pkgs)
            lib
            stdenv
            cctools
            git
            jq
            makeBinaryWrapper
            nodejs_22
            python3
            xcbuild
            yarn-berry_4;

          nodejs = nodejs_22;
          yarn-berry = yarn-berry_4.override { inherit nodejs; };

          # Get the local source (this repo)
          # We filter to only include files needed for building
          src = lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let
                baseName = baseNameOf path;
                # Check if path is within these directories
                isInPackages = lib.hasPrefix (toString ./packages) path;
                isInBin = lib.hasPrefix (toString ./bin) path;
                isInYarn = lib.hasPrefix (toString ./.yarn) path;
              in
              # Always include specific build files
              lib.elem baseName [
                "package.json"
                "yarn.lock"
                ".yarnrc.yml"
                "tsconfig.json"
                "lage.config.js"
                "yarn.config.cjs"
              ]
              # Include contents of needed directories
              || isInPackages
              || isInBin
              || isInYarn;
          };

          # Fetch translations separately (same as upstream)
          translations = pkgs.fetchFromGitHub {
            name = "actualbudget-translations-source";
            owner = "actualbudget";
            repo = "translations";
            rev = "c26df422b50745085191721b1f078664daac947d";
            hash = "sha256-u3EVA8J0VCLPafidGHhDiySB2fQdibntN+6FfErQi70=";
          };

          # Missing hashes for platform-specific packages not in yarn.lock
          missingHashes = ./missing-hashes.json;

          # Create a patched source that applies yarn 4.14 compatibility changes
          # This needs to be done before fetchYarnBerryDeps to ensure lockfile consistency
          patchedSrc = stdenv.mkDerivation {
            pname = "actual-source-patched";
            version = "26.7.1-modded.4";
            inherit src;
            nativeBuildInputs = [ jq ];
            phases = [ "unpackPhase" "patchPhase" "installPhase" ];
            patchPhase = ''
              # Update version to show this is a modded build
              cat <<< $(jq '.version = "26.7.1-modded.4"' ./packages/sync-server/package.json) > ./packages/sync-server/package.json

              # Apply yarn 4.14 compatibility changes (from upstream nixpkgs)
              # Replace yarnPath with approvedGitRepositories and enableScripts
              cat > .yarnrc.yml << 'EOF'
              compressionLevel: mixed

              enableGlobalCache: false

              enableTransparentWorkspaces: false

              nodeLinker: node-modules

              approvedGitRepositories:
                - "**"

              # Secure default: don't run postinstall scripts.
              # If a new package requires them, add it to dependenciesMeta in package.json.
              enableScripts: true

              # Supply-chain defense: don't install package versions published less than 3
              # days ago, giving the community time to catch compromised releases. Trusted
              # packages that need immediate updates can be listed in npmPreapprovedPackages.
              npmMinimalAgeGate: '3d'
              EOF

              substituteInPlace yarn.lock \
                --replace-fail "version: 8" "version: 9"

              cat <<< $(jq '.dependenciesMeta."protoc-gen-js".built = false' ./package.json) > ./package.json
              cat <<< $(jq '.dependenciesMeta."@swc/core".built = false' ./package.json) > ./package.json
              cat <<< $(jq '.dependenciesMeta."sharp".built = false' ./package.json) > ./package.json
            '';
            installPhase = ''
              cp -r . $out
            '';
          };

          # Pre-computed yarn offline cache (uses patched src for lockfile consistency)
          offlineCache = yarn-berry.fetchYarnBerryDeps {
            src = patchedSrc;
            inherit missingHashes;
            hash = yarnHash;
          };

        in
        stdenv.mkDerivation (finalAttrs: {
          pname = "actual-server";
          version = "26.7.1-modded.4";

          src = patchedSrc;
          inherit missingHashes;

          nativeBuildInputs = [
            yarn-berry
            nodejs
            (yarn-berry.yarnBerryConfigHook.override { inherit nodejs; })
            (python3.withPackages (ps: [ ps.setuptools ]))
            makeBinaryWrapper
            git
            jq
          ]
          ++ lib.optionals stdenv.hostPlatform.isDarwin [
            cctools
            xcbuild
          ];

          inherit offlineCache;

          env = {
            ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
            NODE_JQ_SKIP_INSTALL_BINARY = "true";
            SHARP_IGNORE_GLOBAL_LIBVIPS = "1";
          };

          __darwinAllowLocalNetworking = true;

          postPatch = ''
            # Copy translations instead of symlinking to allow modifications
            cp -r ${translations} ./packages/desktop-client/locale
            chmod -R u+w ./packages/desktop-client/locale

            patchShebangs --build ./bin ./packages/*/bin

            substituteInPlace bin/package-browser \
              --replace-fail "git" "true"
          '';

          buildPhase = ''
            runHook preBuild

            export HOME=$(mktemp -d)

            git -c init.defaultBranch=main init -q
            git add -A
            git -c user.email=nix@localhost -c user.name=nix commit -q --allow-empty -m "snapshot"

            yarn build:server
            yarn workspace @actual-app/sync-server build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/{bin,lib,lib/actual/packages/sync-server,lib/actual/packages/desktop-client}
            cp -r ./packages/sync-server/build/. $out/lib/actual/packages/sync-server/
            cp ./packages/sync-server/package.json $out/lib/actual/packages/sync-server
            cp ./packages/desktop-client/package.json $out/lib/actual/packages/desktop-client
            cp -r packages/desktop-client/build $out/lib/actual/packages/desktop-client/build

            export HOME=$(mktemp -d)

            yarn workspaces focus @actual-app/sync-server --production
            rm -r node_modules/.bin 2>/dev/null || true
            cp -r ./node_modules $out/lib/actual/
            cp -r ./packages/crdt $out/lib/actual/packages/crdt

            makeBinaryWrapper ${lib.getExe nodejs} "$out/bin/actual-server" \
              --add-flags "$out/lib/actual/packages/sync-server/bin/actual-server.js" \
              --set NODE_PATH "$out/lib/actual/node_modules"

            runHook postInstall
          '';

          meta = {
            description = "Actual Budget Server - Fork with per-file bank sync support";
            homepage = "https://actualbudget.org/";
            license = lib.licenses.mit;
            mainProgram = "actual-server";
            platforms = with lib.platforms; linux ++ darwin;
          };
        });
    in
    {
      packages = forAllSystems (system: {
        default = self.packages.${system}.actual-server;
        actual-server = mkPackage nixpkgs.legacyPackages.${system};
      });

      # Overlay that replaces actual-server with this fork
      overlays.default = final: prev: {
        actual-server = mkPackage final;
      };

      # NixOS module that can be imported directly
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.actual;
        in
        {
          options.services.actual = {
            enable = mkEnableOption "Actual Budget server";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.system}.actual-server;
              defaultText = literalExpression "actual-server.packages.\${pkgs.system}.actual-server";
              description = "The Actual Budget server package to use.";
            };

            settings = mkOption {
              type = types.submodule {
                freeformType = with types; attrsOf (oneOf [ str int bool ]);

                options = {
                  hostname = mkOption {
                    type = types.str;
                    default = "127.0.0.1";
                    description = "The hostname to bind to.";
                  };

                  port = mkOption {
                    type = types.port;
                    default = 5006;
                    description = "The port to listen on.";
                  };

                  serverFiles = mkOption {
                    type = types.str;
                    default = "/var/lib/actual/server-files";
                    description = "Directory for server files (account.sqlite).";
                  };

                  userFiles = mkOption {
                    type = types.str;
                    default = "/var/lib/actual/user-files";
                    description = "Directory for user budget files.";
                  };

                  dataDir = mkOption {
                    type = types.str;
                    default = "/var/lib/actual";
                    description = "Base data directory.";
                  };
                };
              };
              default = {};
              description = "Server configuration options.";
            };

            openFirewall = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to open the firewall for the Actual server.";
            };

            user = mkOption {
              type = types.str;
              default = "actual";
              description = "User account under which Actual runs.";
            };

            group = mkOption {
              type = types.str;
              default = "actual";
              description = "Group under which Actual runs.";
            };
          };

          config = mkIf cfg.enable {
            users.users.${cfg.user} = {
              isSystemUser = true;
              group = cfg.group;
              home = cfg.settings.dataDir;
              createHome = true;
            };

            users.groups.${cfg.group} = {};

            systemd.services.actual = {
              description = "Actual Budget Server";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                Group = cfg.group;
                ExecStart = "${cfg.package}/bin/actual-server";
                Restart = "on-failure";
                RestartSec = 5;

                # Security hardening
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [
                  cfg.settings.dataDir
                  cfg.settings.serverFiles
                  cfg.settings.userFiles
                ];
              };

              environment = {
                ACTUAL_HOSTNAME = cfg.settings.hostname;
                ACTUAL_PORT = toString cfg.settings.port;
                ACTUAL_SERVER_FILES = cfg.settings.serverFiles;
                ACTUAL_USER_FILES = cfg.settings.userFiles;
              };
            };

            networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.settings.port ];
          };
        };

      # Development shell
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          buildInputs = with nixpkgs.legacyPackages.${system}; [
            nodejs_22
            yarn-berry_4
            git
            jq
          ];

          shellHook = ''
            echo "Actual Budget development shell"
            echo "Node version: $(node --version)"
            echo "Yarn version: $(yarn --version)"
            echo ""
            echo "This is a fork with per-file bank sync support."
          '';
        };
      });

      # Formatter
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
