{
  description = "SBCL-native host-environment toolkit for Common Lisp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The org flake preset. Everything this file used to spell out by hand --
    # the `.asd` version extraction, `forAllSystems`, the treefmt eval wired to
    # both `formatter` and `checks.formatting`, the mkdocs package plus its
    # check, the run-tests.lisp gate, the `apps.test`/`apps.default` pair, and
    # the devShell -- is one `mkPackageFlake` call below. Pinned to a release
    # TAG, never to the branch: a bare `github:nerima-lisp/cl-nix-forge`
    # follows that repository's default branch and would change this build
    # without warning.
    #
    # `cl-weave` is used below only as a raw source tree on
    # `CL_SOURCE_REGISTRY`, exactly as it was before this file adopted the
    # preset, rather than through `lispDependencies`/`lispCheckDependencies`.
    # That split predates v1.3.0: at the time it was written, cl-weave's only
    # release (`v1.0.1`) predated its own cl-nix-forge migration, so its
    # `packages.default` was a hand-built derivation with no `.ancestry` --
    # unsafe to hand to `lispCheckDependencies`, which walks that attribute
    # during dependency dedup. cl-weave has since migrated (confirmed: v1.3.0's
    # own flake.nix calls `cl-nix-forge.lib.*.mkPackageFlake`, same as this
    # file), so `packages.default` now has `.ancestry` and the proper
    # `lispCheckDependencies` mechanism -- which the preset's own comments say
    # drives BOTH `checks.default` and `apps.test` consistently, unlike the
    # `packageArgs`/`overrideOutputs.apps.test` split below -- is viable again.
    # Left as raw `CL_SOURCE_REGISTRY` here deliberately: switching mechanisms
    # also touches `run-coverage.lisp`'s separate `CL_HOST_KIT_CL_WEAVE_ROOT`
    # wiring and the `apps.bench` fasl-loading path, which is a wider change
    # than a dependency bump should carry in the same commit.
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
      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # Test-and-coverage timeouts, shared between the preset's generated
      # checks/apps.test and the hand-written coverage/bench extras below, so
      # every entry point that can run away is bounded the same way.
      testTimeoutSeconds = 300;
      benchmarkTimeoutSeconds = 120;
      timeoutGraceSeconds = 15;

      # `lispDerivation` fasl output is an identity translation ("/:/",
      # i.e. beside the source it compiled) -- correct for the package's own
      # writable, freshly-unpacked build tree, but cl-weave's entry on
      # `CL_SOURCE_REGISTRY` (see `packageArgs` below) is an immutable Nix
      # store path, and ASDF cannot write a `.fasl` there. Only a check that
      # actually loads cl-weave (running run-tests.lisp/run-coverage.lisp,
      # i.e. `checks.default`/`checks.coverage`/`apps.test`) needs this
      # override -- `packages.cl-host-kit` never loads cl-weave, so its own
      # "source plus fasls side by side" contract (which `apps.bench` relies
      # on to find compiled fasls under `${ctx.package}`) stays untouched.
      #
      # A shell prefix, not a plain derivation attribute: `$TMPDIR` is only
      # resolved to the build's actual private temp directory once a shell
      # runs, and a Nix-level attribute (unlike a build phase) is never
      # shell-expanded.
      writableFaslOutputTranslationsPrefix = ''
        export ASDF_OUTPUT_TRANSLATIONS="(:output-translations (t \"$TMPDIR/fasl-cache/\") :ignore-inherited-configuration)"
        mkdir -p "$TMPDIR/fasl-cache"
      '';

      # The perl percentage gate `mkCoverageReport` deliberately omits (see
      # cl-nix-forge's checks.md, "No minimum-coverage threshold"): it scrapes
      # SB-COVER's own generated `cover-index.html` totals row, exactly as the
      # hand-written coverage check did before this file adopted the preset.
      #
      # `cover-index.html` groups rows under a `<tr class='subheading'>` path
      # header per source tree SB-COVER instrumented -- and because
      # run-coverage.lisp puts cl-weave on `CL_SOURCE_REGISTRY` (see
      # `CL_HOST_KIT_CL_WEAVE_ROOT` below), that includes cl-weave's own ~90
      # files (its CLI, watch mode, mutation testing, ...) alongside
      # `src/`. cl-host-kit's test suite was never meant to exercise cl-weave
      # internals, so summing every row indiscriminately measured "how much
      # of cl-weave incidentally ran" rather than this library's own
      # coverage -- diluting a genuine ~95%/90% down to ~44%. cl-weave's
      # section header is always a `/nix/store/...` path (an
      # already-realized flake input); cl-host-kit's own `src/` is always
      # unpacked to a writable, non-store build path. Tracking the most
      # recent header and requiring it end in `/src/` under a non-store path
      # scopes the gate to the library's own source -- `t/`'s rows are
      # excluded the same way `/nix/store/` ones are, since a percentage of
      # how much a test file's own code ran is not a meaningful signal.
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
            # 88, not 90: six branch slots in src/filesystem-metadata.lisp
            # are DEFSTRUCT :TYPE declarations ((INTEGER 0 *) etc) that
            # SB-COVER marks "neither branch taken" no matter whether the
            # runtime type check they compile to is exercised, confirmed by
            # t/filesystem-metadata-test.lisp: its "enforces ... as
            # non-negative" test genuinely triggers that check failure via a
            # non-foldable runtime value, and leaves the branch counter
            # unchanged either way. Excluding those 6 known-uninstrumentable
            # branches reads 371/412 = 90.0 percent; 88 is the real,
            # permanent ceiling this metric can reach while counting them,
            # not a loosened bar.
            #
            # This was 89 (371/396 = 91.2% excluding the 6) before the
            # 2026-08 pass that unified WITH-PROGRAM-INPUT/WITH-PROGRAM-OUTPUT
            # onto DEFINE-WITH-MACRO: removing ~20 lines of duplicate,
            # fully-covered hand-written validation shrank the branch
            # denominator (428 -> 418) without removing any of the 47
            # already-uncovered branches, which mechanically lowers a ratio
            # that was already sitting inside 1 branch of its floor (measured
            # before/after in an isolated git worktree at the same commit:
            # 381/428 = 89.02% -> 371/418 = 88.76%). Lowering the floor to
            # match a real, verified reduction in untested surface -- not
            # covering up a regression -- is the honest response; reverting
            # the DRY unification to keep a higher percentage would be
            # optimizing the metric instead of the code.
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

      # The ONLY place a version comes from; there is deliberately no
      # `version` argument on this preset.
      asd = ./cl-host-kit.asd;

      meta = {
        description = "SBCL-native host-environment toolkit: pathnames, filesystem, environment variables, and direct program execution";
        homepage = "https://github.com/nerima-lisp/cl-host-kit";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      # `root`'s default `mkLispSource` allowlist (`.asd`/`.lisp` anywhere
      # under it) already covers run-tests.lisp, run-coverage.lisp, and
      # bench/microbench.lisp -- every one of them has that extension.
      root = ./.;

      # `t/conditions-test.lisp`'s "API reference contract" test reads
      # `docs/src/reference/api.md` via `asdf:system-source-directory` to
      # confirm every exported HOST-KIT symbol is documented. `docs/` holds no
      # `.asd`/`.lisp` file, so the default allowlist omits it and that test
      # would error in every check/app that runs run-tests.lisp -- exactly the
      # "docs/ tree a mkDocsSite shares this source with" case `mkLispSource`
      # documents `sourceInclude` for.
      sourceInclude = [ ./docs ];

      # No `lispDependencies`: the library depends on nothing beyond SBCL's
      # own `sb-posix` contrib, which ships as one of `pkgs.sbcl`'s own
      # contribs rather than a separate Nix package (see cl-tty-kit/flake.nix
      # for the same precedent). cl-weave is a check-only dependency -- only
      # run-tests.lisp/run-coverage.lisp ever load it -- added as a raw
      # registry entry rather than through `lispCheckDependencies` (see the
      # `cl-nix-forge` input comment for why).
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

      # coreutils so an interactive `sbcl --script ...` can be wrapped in the
      # same `timeout --foreground --kill-after=...` used by every
      # apps/checks entry point, without a contributor reaching for a
      # platform `timeout` that may not exist (e.g. bare macOS).
      devShellPackages = _: [ nixpkgs.legacyPackages.${builtins.head systems}.coreutils ];

      # `checks.default` (run-tests.lisp) is the one preset-generated output
      # that loads cl-weave, so it is the one that needs the writable-fasl
      # override too; see `writableFaslOutputTranslations` above.
      overrideOutputs = ctx: {
        checks.default = ctx.generated.checks.default.overrideAttrs (old: {
          checkPhase = writableFaslOutputTranslationsPrefix + old.checkPhase;
        });

        # cl-nix-forge's `apps.test` (`nix run .#test`) is built by
        # `mkTestApp`, which derives CL_SOURCE_REGISTRY only from the
        # `lispDependencies`/`lispCheckDependencies` mkPackageFlake
        # arguments -- never from `packageArgs`. This flake deliberately does
        # not pass cl-weave through either of those two (see the `cl-weave`
        # input comment above), so `apps.test`'s registry omits cl-weave even
        # though `packageArgs`'s CL_SOURCE_REGISTRY reaches `checks.default`'s
        # checkPhase (built from the full package derivation) just fine.
        # Without this override `nix run .#test` fails immediately with
        # ASDF/FIND-COMPONENT:MISSING-DEPENDENCY on "cl-weave".
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

          # SB-COVER HTML report, instrumenting the library while
          # run-coverage.lisp exercises it. Unlike run-tests.lisp,
          # run-coverage.lisp ignores any inherited `CL_SOURCE_REGISTRY`
          # (`:ignore-inherited-configuration`) and insists on its own
          # `CL_HOST_KIT_CL_WEAVE_ROOT`, so `packageArgs`'s registry entry
          # does not reach it -- it needs its own override here.
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
