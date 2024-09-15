# emacs-gounit

This is a Emacs minor mode to run tests in a Go project/package.

Tests are run with `go test`. The plugin tries to figure out the context of the test to run. Run `gounit-run-all` to run all tests in a package (use `gounit-cd` to set a package). Use `gounit-run-single` to run only a single test case. This requires the cursor to be with a `func TestXyz(t *testing.T) {}` block (test names starting with 'Test' are mandatory), otherwise the parsing might be off.

There is no package on Elpa or Melpa.
To install it clone this to some local folder and initialize like this in Emacs:

```
(use-package gounit
  :load-path "~/.emacs.d/plugins/gounit"
  ;; those are default bindings. :bind is only necessary if you want to change them. 
  :bind (:map gounit-mode-map
              ("C-c C-t" . gounit-run-all)
              ("C-c C-s" . gounit-run-single)
              ("C-c C-r" . gounit-run-last)
              ("C-c C-d" . gounit-cd))
  :commands
  (gounit-mode))
```

The default key binding is `C-c C-<*>`.

When done you have a minor mode called `gounit-mode`.

This mode can be enabled for basically every buffer but only `go-mode` buffers are supported.
On other major modes it just saves the buffer.

The key sequence: `C-c C-t` (or a custom defined one) will first save the buffer and then run the tests using `go`.

After the first execution of `gounit-run-*` you can view the "\*GoUnit output\*" buffer for test output. It should be mentioned that this is a synchronous process in order to collect the tools return code and show a `Tests OK` or `Tests failed!` as message. So the test class should be the largest context to run this is, otherwise it will just take to long to block up Emacs.

Go test are run per package. Use `gounit-cd` to set the current package path.

