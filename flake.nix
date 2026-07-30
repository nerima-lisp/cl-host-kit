{
  description = "Dependency-free host-environment toolkit for Common Lisp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.0.0";
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
      sourceRegistry = "${cl-weave}//:${self}//";

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

      coverageScriptFor =
        pkgs:
        pkgs.writeText "cl-host-kit-coverage.lisp" ''
          (require :asdf)
          (require :sb-cover)

          (declaim (optimize sb-cover:store-coverage-data))

          (asdf:initialize-source-registry
           '(:source-registry
             (:tree "${self}")
             :inherit-configuration))
          (asdf:operate 'asdf:test-op "cl-host-kit" :force t)
          (let ((source-directory (namestring #P"${self}/src/")))
            (sb-cover:report
             (or (sb-ext:posix-getenv "CL_HOST_KIT_COVERAGE_DIR") "coverage/")
             :if-matches
             (lambda (namestring)
               (and (<= (length source-directory) (length namestring))
                    (string= source-directory namestring
                             :end2 (length source-directory))))))
          (sb-ext:exit :code 0)
        '';

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
                mkdir -p "$HOME" "$out"
                timeout 120 sbcl --script ${self}/run-tests.lisp
                touch "$out/passed"
              '';

          # Fails `nix flake check` when any tracked file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # The docs package builds with `mkdocs --strict`, so a broken link
          # or a page missing from the nav fails the build here rather than
          # at deploy time after a merge to main.
          docs = self.packages.${system}.docs;

          coverage =
            let
              coverageScript = coverageScriptFor pkgs;
            in
            pkgs.runCommand "cl-host-kit-coverage"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                  pkgs.perl
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                export CL_HOST_KIT_COVERAGE_DIR="$TMPDIR/coverage/"
                mkdir -p "$HOME" "$out"
                timeout 120 sbcl --script ${coverageScript}
                perl -0777 -ne '
                  my ($expression_covered, $expression_total, $branch_covered, $branch_total);
                  s{</tr>}{\n}g;
                  s{<[^>]+>}{ }g;
                  s{&nbsp;}{ }g;
                  for (split /\n/) {
                    s{\s+}{ }g;
                    next unless / [^ ]+\.lisp (\d+) (\d+) [\d.]+ (\d+) (\d+) [\d.-]+/;
                    $expression_covered += $1;
                    $expression_total += $2;
                    $branch_covered += $3;
                    $branch_total += $4;
                  }
                  for my $requirement (
                    [expression => $expression_covered => $expression_total => 94],
                    [branch => $branch_covered => $branch_total => 90],
                  ) {
                    my ($kind, $covered, $total, $minimum) = @$requirement;
                    die "Coverage report does not contain $kind totals\n"
                      unless defined $covered && defined $total && $total > 0;
                    my $percentage = 100 * $covered / $total;
                    printf "%s coverage: %.1f%% (%d/%d), minimum: %d%%\n",
                      ucfirst($kind), $percentage, $covered, $total, $minimum;
                    die "$kind coverage is below $minimum%\n"
                      if $percentage < $minimum;
                  }
                ' "$CL_HOST_KIT_COVERAGE_DIR/cover-index.html"
                touch "$out/passed"
              '';
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
              exec timeout 120 sbcl --script ${self}/run-tests.lisp
            '';
          };
          coverageScript = coverageScriptFor pkgs;
          coverage = pkgs.writeShellApplication {
            name = "cl-host-kit-coverage";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              coverage_directory="''${CL_HOST_KIT_COVERAGE_DIR:-coverage/}"
              case "$coverage_directory" in
                */) ;;
                *) coverage_directory="$coverage_directory/" ;;
              esac
              export CL_HOST_KIT_COVERAGE_DIR="$coverage_directory"
              exec timeout 120 sbcl --script ${coverageScript}
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
