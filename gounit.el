;;; gounit.el --- `Go test' runner -*- lexical-binding: t -*-

;; Copyright (C) 2024 Manfred Bergmann.

;; Author: Manfred Bergmann <manfred.bergmann@me.com>
;; URL: http://github.com/mdbergmann/emacs-gounit
;; Version: 0.1
;; Keywords: processes go test
;; Package-Requires: ((emacs "24.3"))

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Provides commands to run test cases in a Go project.

;;; Code:

(require 'ansi-color)
(require 'cl-lib)

(make-variable-buffer-local
 (defvar gounit-mode))

(defvar-local *last-test* nil)
(defvar-local *gounit--cwd* nil)
(defvar-local *go-process* nil)

(defvar gounit-test-failure-hook nil)
(defvar gounit-test-success-hook nil)

(defvar gounit-go-executable "go")

(defvar *gounit-output-buf-name* "*gounit output*")

(defun gounit--find-package (buffer-text)
  "Generate the package for the test run.
This is usually the full designated class.
BUFFER-TEXT is a string where the matching should take place."
  (let ((package-string (progn
                          (string-match "^package[ ]+\\(.+\\).*$"
                                        buffer-text)
                          (match-string 1 buffer-text))))
    (message "Package: %s" package-string)
    package-string))

(defun gounit--find-test-method (buffer-text curr-position)
  "Find a single test case for the test run in fun spec format.
BUFFER-TEXT is a string where the matching should take place.
CURR-POSITION is the current position of the curser in the buffer."
  (message "Finding test case in func starting: %s" curr-position)
  (with-temp-buffer
    (insert buffer-text)
    (goto-char curr-position)
    (let ((found-point (search-backward "func Test" nil t)))
      (message "point: %s" found-point)
      (if found-point
          (let ((matches (string-match "func \\(.+\\)(.*$"
                                       buffer-text
                                       (- found-point 1))))
            (message "matches: %s" matches)
            (match-string 1 buffer-text))))))

(defun gounit--project-root-dir ()
  "Return the project root directory."
  (locate-dominating-file default-directory "go.mod"))

(defun gounit--process-filter (proc string)
  "Process filter function. Takes PROC as process.
And STRING as the process output.
The output as STRING is enriched with text sttributes from ansi escape commands."
  (with-current-buffer (process-buffer proc)
    (let ((moving (= (point) (process-mark proc))))
      (save-excursion
        (goto-char (process-mark proc))
        (insert string)
        (set-marker (process-mark proc) (point)))
      (if moving (goto-char (process-mark proc))))))

(defun gounit--process-sentinel (proc signal)
  "Go process sentinel.
PROC is the process. SIGNAL the signal from the process."
  (ignore signal)
  (let ((process-rc (process-exit-status proc)))
    (with-current-buffer (process-buffer proc)
      (ansi-color-apply-on-region (point-min) (point-max)))
    (if (= process-rc 0)
        (gounit--handle-successful-test-result)
      (gounit--handle-unsuccessful-test-result)))
  (when (not (process-live-p proc))
    (setq *go-process* nil)))

(defun gounit--execute-test-in-context (test-args)
  "Call specific test. TEST-ARGS specifies a test to run."
  (message "Run with test args: %s" test-args)
  (let ((test-cmd-args (append
                        (list gounit-go-executable "test")
                        test-args)))
    (message "calling: %s" test-cmd-args)
    (let ((default-directory *gounit--cwd*))
      (message "cwd: %s" default-directory)
      (setq *go-process*
            (make-process :name "gounit"
                          :buffer *gounit-output-buf-name*
                          :command test-cmd-args
                          :filter 'gounit--process-filter
                          :sentinel 'gounit--process-sentinel))
      (message "Running: %s" test-args))))

(defun gounit--compute-test-args (test-spec single buffer-text current-point)
  "Calculates test-args as used in execute-in-context.
TEST-SPEC is a given, previously executed test.
When this is not null, it'll be used.
Otherwise we calculate a new test-spec, from package
and (maybe) single test case if SINGLE is T.
BUFFER-TEXT contains the buffer text as string without properties.
CURRENT-POINT is the current cursor position.
Only relevant if SINGLE is specified."
  (if (not (null test-spec))
      test-spec
    (let* ((test-package (gounit--find-package buffer-text))
           (single-test (if single
                            (gounit--find-test-method buffer-text current-point)))
           (test-args '()))
      (if (and single-test single)
          (append test-args
                  (list "--run" (format "^%s$" single-test)))
        test-args))))

(cl-defun gounit--get-buffer-text (&optional (beg 1) (end (point-max)))
  "Retrieve the buffer text. Specify BEG and END for specific range."
  (buffer-substring-no-properties beg end))

(defun gounit--handle-successful-test-result ()
  "Do some stuff when the test ran OK."
  (message "GOUNIT: running commit hook.")
  (run-hooks 'gounit-test-success-hook)
  (message "%s" (propertize "Tests OK" 'face '(:foreground "green"))))

(defun gounit--handle-unsuccessful-test-result ()
  "Do some stuff when the test ran NOK."
  (message "GOUNIT: running revert hook.")
  (run-hooks 'gounit-test-failure-hook)
  (message "%s" (propertize "Tests failed!" 'face '(:foreground "red"))))

(cl-defun gounit--run-test (&optional (test-spec nil) (single nil))
  "Execute the test.
Specify optional TEST-SPEC if a specific test should be run.
Specify optional SINGLE (T)) to try to run only a single test case."
  (message "gounit: run-test")

  (unless *gounit--cwd*
    (error "Please define package directory!"))
  
  (unless (string-equal "go-mode" major-mode)
    (error "Need 'go-mode' to run!"))
  
  (get-buffer-create *gounit-output-buf-name*)
  (with-current-buffer *gounit-output-buf-name*
    (erase-buffer))
  (display-buffer *gounit-output-buf-name*)
  
  (let ((test-args (gounit--compute-test-args
                    test-spec
                    single
                    (gounit--get-buffer-text)
                    (point))))
    (gounit--execute-test-in-context test-args)
    (setq-local *last-test* test-args)))

(defun gounit-run-all ()
  "Save buffers and execute all test cases in the context."
  (interactive)
  (when (gounit--run-preps)
    (gounit--run-test)))

(defun gounit-run-single ()
  "Save buffers and execute a single test in the context."
  (interactive)
  (when (gounit--run-preps)
    (gounit--run-test nil t)))

(defun gounit-run-last ()
  "Save buffers and execute command to run the test."
  (interactive)
  (when (gounit--run-preps)
    (gounit--run-test *last-test*)))

(defun gounit-cd ()
  "Change the directory to a package directory."
  (interactive)
  (let ((current-dir (if *gounit--cwd*
                         *gounit--cwd*
                       (gounit--project-root-dir))))
    (setq *gounit--cwd*
          (read-file-name
           (format "Package path [%s]: " current-dir)
           current-dir nil nil nil nil))))

(defun gounit--run-preps ()
  "Save buffers."
  (if (not (process-live-p *go-process*))
      (progn
        (save-buffer)
        (save-some-buffers)
        t)
    (progn
      (message "Test still running. Try again when finished!")
      nil)))

(define-minor-mode gounit-mode
  "Go unit - test runner. Runs Go to execute tests."
  :lighter " GU"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-t") 'gounit-run-all)
            (define-key map (kbd "C-c C-s") 'gounit-run-single)
            (define-key map (kbd "C-c C-r") 'gounit-run-last)
            (define-key map (kbd "C-c C-d") 'gounit-cd)
            map))

(provide 'gounit)

;; ---------------------------------------------
;; tests ;; more tests
;; ---------------------------------------------

(defvar gounit--run-tests nil)

(eval-when-compile
  (setq gounit--run-tests t))

(defun gounit--test--find-package ()
  "Test finding the package, calling full \"go test\"."
  (let ((buffer-text "package foo_test

func Foo() {
}"))
    (cl-assert (string= "foo_test"
                        (gounit--find-package buffer-text)))))

(defun gounit--test--find-test-method ()
  "Test finding the test-case context - fun spec."
  (let ((buffer-text "some stuff
  func TestXyz_foo(t *testing.T) {
in test
}"))
    (let ((found (gounit--find-test-method buffer-text 50)))
      (message "found: %s" found)
      (cl-assert (string= "TestXyz_foo" found)))))

(defun gounit--test--compute-test-args ()
  "Test computing test args."
  (let ((buffer-text ""))
    ;; return given test spec
    (cl-assert (string= "my-given-test-spec"
                        (gounit--compute-test-args "my-given-test-spec" nil buffer-text 0))))
  ;; func only test
  (let ((buffer-text "package foo_test\nfunc TestFooBar(t *testing.T) { blah }"))
    ;; return full class test
    (cl-assert (cl-equalp nil
                          (let ((args (gounit--compute-test-args nil nil buffer-text 0)))
                            (message "args: %s" args)
                            args)))
    ;; cursor pos in 'test' block - returns single test
    (cl-assert (cl-equalp (list "--run" "^TestFooBar$")
                          (gounit--compute-test-args nil t buffer-text 50)))
    ;; cursor pos outside of 'test' block
    (cl-assert (cl-equalp nil
                          (gounit--compute-test-args nil t buffer-text 10)))
    )
  )

(when gounit--run-tests
  (gounit--test--find-package)
  (gounit--test--find-test-method)
  (gounit--test--compute-test-args)
  )

;;; gounit.el ends here
