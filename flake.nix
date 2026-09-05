{
  description = "SBCL-native host-environment toolkit for Common Lisp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pin the preset to a release rather than its moving default branch.
    # cl-weave remains a raw source-tree dependency because the test, coverage,
    # and benchmark entry points use separate source and FASL wiring.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
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
      cl-nix-forge,
      cl-weave,
      treefmt-nix,
      ...
    }:
    let
      # CI runs on Linux; local development runs on aarch64-darwin.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # Bound every test, coverage, and benchmark entry point.
      testTimeoutSeconds = 300;
      benchmarkTimeoutSeconds = 120;
      timeoutGraceSeconds = 15;

      # Checks load cl-weave from an immutable store path, so its FASLs need a
      # writable cache. This is a shell prefix because TMPDIR is runtime state.
      writableFaslOutputTranslationsPrefix = ''
        export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$TMPDIR/fasl-cache/\") :ignore-inherited-configuration)"
        mkdir -p "$TMPDIR/fasl-cache"
      '';

      # `mkCoverageReport` does not enforce a minimum, so scrape SB-COVER's
      # report and enforce the library's thresholds here. Include only the
      # non-store `/src/` section: cl-weave is instrumented as a dependency,
      # while test-file coverage is not part of the library's signal.
      coverageThresholdCheckScript = ''
        perl -0777 -ne '
          my ($expression_covered, $expression_total, $branch_covered, $branch_total) = (0, 0, 0, 0);
          my $include = 0;
          s{</tr>}{\n}g;
          s{<[^>]+>}{ }g;
          s{&nbsp;}{ }g;
          for (split /\n/) {
            s{\s+}{ }g;
            if (/^\s*(\/\S+\/)\s*$/) {
              $include = ($1 !~ m{^/nix/store/} && $1 =~ m{/src/\s*$}) ? 1 : 0;
              next;
            }
            next unless $include;
            next unless / [^ ]+\.lisp (\d+) (\d+) [\d.]+ (\d+) (\d+) [\d.-]+/;
            $expression_covered += $1;
            $expression_total += $2;
            $branch_covered += $3;
            $branch_total += $4;
          }
          for my $requirement (
            # SB-COVER cannot exercise six type-declaration branch slots in
            # filesystem-metadata.lisp, so the branch floor reflects that
            # instrumentation limit rather than a relaxed test requirement.
            [expression => $expression_covered => $expression_total => 94],
            [branch => $branch_covered => $branch_total => 88],
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
        ' "$report/cover-index.html"
      '';
    in
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;
      pname = "cl-host-kit";

      # The package version is read from the ASDF system definition.
      asd = ./cl-host-kit.asd;

      meta = {
        description = "SBCL-native host-environment toolkit: pathnames, filesystem, environment variables, and direct program execution";
        homepage = "https://github.com/nerima-lisp/cl-host-kit";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      root = ./.;

      # The API contract test reads the documentation from the source tree.
      sourceInclude = [ ./docs ];

      # cl-weave is needed only by checks and coverage, not by the library.
      packageArgs = _: {
        CL_SOURCE_REGISTRY = "${cl-weave}/";
      };

      runner = "run-tests.lisp";
      timeoutSeconds = testTimeoutSeconds;
      killAfterSeconds = timeoutGraceSeconds;

      docs = {
        root = ./docs;
      };

      treefmt = {
        evalModule = treefmt-nix.lib.evalModule;
      };

      # Provide the GNU timeout used by the entry points on macOS as well.
      devShellPackages = _: [ nixpkgs.legacyPackages.${builtins.head systems}.coreutils ];

      # `checks.default` (run-tests.lisp) is the one preset-generated output
      # that loads cl-weave, so it is the one that needs the writable-fasl
      # override too; see `writableFaslOutputTranslations` above.
      overrideOutputs = ctx: {
        checks.default = ctx.generated.checks.default.overrideAttrs (old: {
          checkPhase = writableFaslOutputTranslationsPrefix + old.checkPhase;
        });

        # The generated test app does not inherit packageArgs' registry.
        apps.test = {
          type = "app";
          program = "${
            ctx.pkgs.writeShellApplication {
              name = "cl-host-kit-test";
              text = ''
                export CL_SOURCE_REGISTRY="${cl-weave}/''${CL_SOURCE_REGISTRY:+:$CL_SOURCE_REGISTRY}"
                exec ${ctx.generated.apps.test.program} "$@"
              '';
            }
          }/bin/cl-host-kit-test";
        };
      };

      extraOutputs =
        ctx:
        let
          pkgs = ctx.pkgs;

          # Coverage uses its own cl-weave source-root environment variable.
          coverageReport =
            (ctx.cl.mkCoverageReport {
              drv = ctx.package;
              name = "cl-host-kit-coverage";
              entryPoint = "run-coverage.lisp";
              timeoutSeconds = testTimeoutSeconds;
              killAfterSeconds = timeoutGraceSeconds;
            }).overrideAttrs
              (old: {
                CL_HOST_KIT_CL_WEAVE_ROOT = "${cl-weave}";
                checkPhase = writableFaslOutputTranslationsPrefix + old.checkPhase;
              });

          coverageThresholdCheck = pkgs.runCommand "cl-host-kit-coverage-thresholds" {
            report = coverageReport;
            nativeBuildInputs = [ pkgs.perl ];
          } (coverageThresholdCheckScript + "\ntouch \"$out\"\n");

          coverageApp = pkgs.writeShellApplication {
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

          benchApp = pkgs.writeShellApplication {
            name = "cl-host-kit-bench";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
              ctx.package
            ];
            text = ''
              home_dir="$(mktemp -d "''${TMPDIR:-/tmp}/cl-host-kit-bench.XXXXXX")"
              trap 'rm -rf "$home_dir"' EXIT
              export HOME="$home_dir"
              export XDG_CACHE_HOME="$home_dir/cache"
              export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$home_dir/fasl/\") :ignore-inherited-configuration)"
              export CL_HOST_KIT_FASL_ROOT="${ctx.package}/"
              mkdir -p "$XDG_CACHE_HOME" "$home_dir/fasl"
              timeout --foreground --kill-after=${toString timeoutGraceSeconds}s ${toString benchmarkTimeoutSeconds}s sbcl \
                --eval '(let ((fasl-root (or (sb-ext:posix-getenv "CL_HOST_KIT_FASL_ROOT") (error "CL_HOST_KIT_FASL_ROOT is not set")))) (dolist (component (quote ("package" "conditions" "with-macros" "strings" "pathnames" "environment" "process-result" "process-io" "process" "working-directory" "filesystem-metadata" "directory-operations" "temporary-resources" "file-io" "file-locking"))) (load (merge-pathnames (format nil "src/~A.fasl" component) fasl-root))))' \
                --script ${self}/bench/microbench.lisp
            '';
          };
        in
        {
          checks = {
            coverage = coverageThresholdCheck;
          };
          apps = {
            coverage = {
              type = "app";
              program = "${coverageApp}/bin/cl-host-kit-coverage";
            };
            bench = {
              type = "app";
              program = "${benchApp}/bin/cl-host-kit-bench";
            };
          };
        };
    };
}
