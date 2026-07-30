# Installation

## Nix

```sh
nix build github:nerima-lisp/cl-host-kit
```

To pin it as a flake input, follow the same pattern the rest of the
nerima-lisp org uses for sibling packages: pull the source only
(`flake = false`) and pin to a release tag rather than the default branch.

```nix
inputs.cl-host-kit = {
  url = "github:nerima-lisp/cl-host-kit/v0.2.1";
  flake = false;
};
```

## ASDF

Put the repository somewhere ASDF can find it and load it:

```lisp
(asdf:load-system "cl-host-kit")
```

## Dependencies

The main `cl-host-kit` system depends on nothing outside of SBCL's own
`sb-posix` contrib, which is not a separate library to install — it ships
with SBCL itself. The `cl-host-kit/test` system additionally depends on
[`cl-weave`](https://github.com/nerima-lisp/cl-weave), the org's test
framework; that dependency does not affect the shipped library.

## Supported implementation

SBCL only. The system depends directly on SBCL's bundled `sb-posix` contrib,
and is intentionally not loadable on other Common Lisp implementations.
