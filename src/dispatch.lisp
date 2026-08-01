;;;; src/dispatch.lisp
;;;;
;;;; SYMBOL-CALL exists for exactly one recurring org pattern: a .asd file's
;;;; :perform (test-op ...) clause invoking its own test system's entry
;;;; point, which the enclosing system cannot reference directly because the
;;;; test system is not yet defined when :depends-on is written. It is
;;;; HOST-KIT's one deliberate exception to being a host-operation-only
;;;; library, kept narrow and signature-compatible with UIOP:SYMBOL-CALL so
;;;; the org-wide uiop migration has exactly one call to make here.
(in-package #:host-kit)

(defun symbol-call (package name &rest arguments)
  "Call the function named NAME in PACKAGE with ARGUMENTS, and return its
values. PACKAGE and NAME are string designators. Signals a PACKAGE-ERROR when
PACKAGE does not exist, and a plain ERROR when NAME does not name a function
in it."
  (let* ((resolved-package (or (find-package package)
                               (error 'package-error :package package)))
         (symbol (find-symbol (string name) resolved-package)))
    (unless (and symbol (fboundp symbol))
      (error "~S does not name a function in package ~A."
             name (package-name resolved-package)))
    (apply (symbol-function symbol) arguments)))
