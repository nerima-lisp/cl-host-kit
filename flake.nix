{
  description = "SBCL-native host-environment toolkit for Common Lisp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      cl-weave,
      treefmt-nix,
      ...
    }:
    let
      # Only what is verified: x86_64-linux by CI, aarch64-darwin by the
      # maintainer's local `nix flake check`. See PACKAGE_STANDARD.md
      # "systems" and ADR-0078.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      sourceRegistry = "${cl-weave}/:${self}/";
      testTimeoutSeconds = 300;
      benchmarkTimeoutSeconds = 120;
      timeoutGraceSeconds = 15;

      # Single source of truth for the package version: the `:version` form
      # in cl-host-kit.asd. Nix regexes are whole-string anchored and `.`
      # never spans newlines, so the version is extracted line-by-line
      # rather than with one multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-host-kit.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only, for the same reason as every other repo in this
      # org: YAML formatters mangle the GitHub Actions `on:` key and
      # Markdown reformatting would churn the whole docs tree.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          # No lispLibs argument: the main system's only dependency is
          # sb-posix, which ships as one of pkgs.sbcl's own contribs rather
          # than a separate Nix package (see cl-tty-kit/flake.nix for the
          # same precedent).
          cl-host-kit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-host-kit";
            inherit version;
            src = self;
            systems = [ "cl-host-kit" ];
          };
          default = cl-host-kit;

          # Rendered documentation site (Material for MkDocs), built fully
          # offline. --strict promotes broken links and unlisted pages to
          # build failures.
          docs = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-host-kit-docs";
            inherit version;
            src = pkgs.lib.fileset.toSource {
              root = ./docs;
              fileset = pkgs.lib.fileset.unions [
                ./docs/mkdocs.yml
                ./docs/src
              ];
            };
            nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
            buildPhase = ''
              runHook preBuild
              mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "Rendered MkDocs (Material) documentation for cl-host-kit";
              homepage = "https://github.com/nerima-lisp/cl-host-kit";
              license = pkgs.lib.licenses.mit;
            };
          };
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default =
            pkgs.runCommand "cl-host-kit-tests"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                export XDG_CACHE_HOME="$HOME/cache"
                export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$HOME/fasl/\") :ignore-inherited-configuration)"
                mkdir -p "$XDG_CACHE_HOME" "$HOME/fasl" "$out"
                timeout --foreground --kill-after=${toString timeoutGraceSeconds}s ${toString testTimeoutSeconds}s sbcl --script ${self}/run-tests.lisp
                touch "$out/passed"
              '';

          coverage =
            pkgs.runCommand "cl-host-kit-coverage"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                ];
                CL_HOST_KIT_CL_WEAVE_ROOT = "${cl-weave}";
              }
              ''
                unset CL_SOURCE_REGISTRY
                export HOME="$TMPDIR/home"
                export XDG_CACHE_HOME="$HOME/cache"
                export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$HOME/fasl/\") :ignore-inherited-configuration)"
                mkdir -p "$XDG_CACHE_HOME" "$HOME/fasl" "$out/coverage"
                export CL_HOST_KIT_COVERAGE_DIR="$out/coverage"
                timeout --foreground --kill-after=${toString timeoutGraceSeconds}s ${toString testTimeoutSeconds}s sbcl --script ${self}/run-coverage.lisp
                test -f "$out/coverage/cover-index.html"
              '';

          # Fails `nix flake check` when any tracked file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # The docs package builds with `mkdocs --strict`, so a broken link
          # or a page missing from the nav fails the build here rather than
          # at deploy time after a merge to main.
          docs = self.packages.${system}.docs;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "cl-host-kit-test";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              home_dir="$(mktemp -d "''${TMPDIR:-/tmp}/cl-host-kit-test.XXXXXX")"
              trap 'rm -rf "$home_dir"' EXIT
              export HOME="$home_dir"
              export XDG_CACHE_HOME="$home_dir/cache"
              export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$home_dir/fasl/\") :ignore-inherited-configuration)"
              mkdir -p "$XDG_CACHE_HOME" "$home_dir/fasl"
              timeout --foreground --kill-after=${toString timeoutGraceSeconds}s ${toString testTimeoutSeconds}s sbcl --script ${self}/run-tests.lisp
            '';
          };
          coverage = pkgs.writeShellApplication {
            name = "cl-host-kit-coverage";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              unset CL_SOURCE_REGISTRY
              export CL_HOST_KIT_CL_WEAVE_ROOT="${cl-weave}"
              coverage_dir="$(mktemp -d "''${TMPDIR:-/tmp}/cl-host-kit-coverage.XXXXXX")"
              export HOME="$coverage_dir/home"
              export XDG_CACHE_HOME="$HOME/cache"
              export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$HOME/fasl/\") :ignore-inherited-configuration)"
              mkdir -p "$XDG_CACHE_HOME" "$HOME/fasl"
              export CL_HOST_KIT_COVERAGE_DIR="$coverage_dir"
              timeout --foreground --kill-after=${toString timeoutGraceSeconds}s ${toString testTimeoutSeconds}s sbcl --script ${self}/run-coverage.lisp
              printf 'Coverage report: %s\\n' "$coverage_dir/cover-index.html"
            '';
          };
          bench = pkgs.writeShellApplication {
            name = "cl-host-kit-bench";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
              self.packages.${system}.cl-host-kit
            ];
            text = ''
              home_dir="$(mktemp -d "''${TMPDIR:-/tmp}/cl-host-kit-bench.XXXXXX")"
              trap 'rm -rf "$home_dir"' EXIT
              export HOME="$home_dir"
              export XDG_CACHE_HOME="$home_dir/cache"
              export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$home_dir/fasl/\") :ignore-inherited-configuration)"
              export CL_HOST_KIT_FASL_ROOT="${self.packages.${system}.cl-host-kit}/"
              mkdir -p "$XDG_CACHE_HOME" "$home_dir/fasl"
              timeout --foreground --kill-after=${toString timeoutGraceSeconds}s ${toString benchmarkTimeoutSeconds}s sbcl \
                --eval '(let ((fasl-root (or (sb-ext:posix-getenv "CL_HOST_KIT_FASL_ROOT") (error "CL_HOST_KIT_FASL_ROOT is not set")))) (dolist (component (quote ("package" "conditions" "strings" "pathnames" "environment" "working-directory" "filesystem"))) (load (merge-pathnames (format nil "src/~A.fasl" component) fasl-root))))' \
                --script ${self}/bench/microbench.lisp
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${test}/bin/cl-host-kit-test";
          };
          test = {
            type = "app";
            program = "${test}/bin/cl-host-kit-test";
          };
          coverage = {
            type = "app";
            program = "${coverage}/bin/cl-host-kit-coverage";
          };
          bench = {
            type = "app";
            program = "${bench}/bin/cl-host-kit-bench";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.sbcl ];
            CL_SOURCE_REGISTRY = sourceRegistry;
          };
        }
      );
    };
}
