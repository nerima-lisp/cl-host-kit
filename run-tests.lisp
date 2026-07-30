;;;; run-tests.lisp
;;;;
;;;; Bootstrap script: register this checkout, inherit the caller's ASDF
;;;; configuration for dependencies, and run the test system.

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(defun configure-local-source-registry (root)
  (asdf:initialize-source-registry
    `(:source-registry
      (:directory ,root)
      :inherit-configuration)))

(let ((root (script-directory)))
  (configure-local-source-registry root)
  (asdf:test-system "cl-host-kit/test")
  ;; SB-EXT:EXIT rather than HOST-KIT:QUIT: the HOST-KIT package does not
  ;; exist until CL-HOST-KIT finishes loading above, and this whole LET is
  ;; one top-level form -- the reader would have to resolve HOST-KIT:QUIT
  ;; before any of the form has been evaluated. Unlike the other repos'
  ;; run-tests.lisp (which can reach for UIOP:QUIT, since uiop is already
  ;; loaded by ASDF itself), this is the one script that has to bootstrap the
  ;; very package it would otherwise dogfood.
  (sb-ext:exit :code 0))
