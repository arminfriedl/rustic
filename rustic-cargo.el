;;; rustic-cargo.el --- Cargo based commands -*-lexical-binding: t-*-

;;; Code:

(require 'tabulated-list)

;;;;;;;;;;;;;;;;;;
;; Customization

(defcustom rustic-cargo-bin "cargo"
  "Path to cargo executable.")


;;;;;;;;;;;
;; Clippy

(defvar rustic-clippy-process-name "rustic-cargo-clippy-process"
  "Process name for clippy processes.")

(defvar rustic-clippy-buffer-name "*cargo-clippy*"
  "Buffer name for clippy buffers.")

(define-derived-mode rustic-cargo-clippy-mode rustic-compilation-mode "cargo-clippy"
  :group 'rustic)

;;;###autoload
(defun rustic-cargo-clippy ()
  "Run `cargo clippy'."
  (interactive)
  (let ((command (list rustic-cargo-bin "clippy"))
        (buffer-name rustic-clippy-buffer-name)
        (proc-name rustic-clippy-process-name)
        (mode 'rustic-cargo-clippy-mode)
        (root (rustic-buffer-workspace)))
    (rustic-compilation-process-live)
    (rustic-compilation-start command buffer-name proc-name mode root)))


;;;;;;;;;
;; Test

(defvar rustic-test-process-name "rustic-cargo-test-process"
  "Process name for test processes.")

(defvar rustic-test-buffer-name "*cargo-test*"
  "Buffer name for test buffers.")

(define-derived-mode rustic-cargo-test-mode rustic-compilation-mode "cargo-test"
  :group 'rustic)

;;;###autoload
(defun rustic-cargo-test ()
  "Run `cargo test'."
  (interactive)
  (let ((command (list rustic-cargo-bin "test"))
        (buffer-name rustic-test-buffer-name)
        (proc-name rustic-test-process-name)
        (mode 'rustic-cargo-test-mode)
        (root (rustic-buffer-workspace)))
    (rustic-compilation-process-live)
    (rustic-compilation-start command buffer-name proc-name mode root)))


;;;;;;;;;;;;;
;; Outdated

(defcustom rustic-cargo-outdated-face "red"
  "Face for upgradeable crates."
  :type 'face
  :group 'rustic)

(defvar rustic-cargo-outdated-process-name "rustic-cargo-outdated-process")

(defvar rustic-cargo-oudated-buffer-name "*cargo-outdated*")

(defvar rustic-cargo-outdated-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "m") 'rustic-cargo-menu-mark-unmark)
    (define-key map (kbd "u") 'rustic-cargo-mark-upgrade)
    (define-key map (kbd "U") 'rustic-cargo-mark-all-upgrades)
    (define-key map (kbd "x") 'rustic-cargo-upgrade-execute)
    (define-key map (kbd "r") 'rustic-cargo-reload-outdated)
    (define-key map (kbd "c") 'rustic-compile)
    (define-key map (kbd "q") 'quit-window)
    map)
  "Local keymap for `rustic-cargo-outdated-mode' buffers.")

(define-derived-mode rustic-cargo-outdated-mode tabulated-list-mode "cargo-outdated"
  "Major mode for viewing outdated crates in the current workspace."
  (setq truncate-lines t)
  (setq tabulated-list-format
        `[("Name" 25 nil)
          ("Project" 10 nil)
          ("Compat" 10 nil)
          ("Latest" 10 nil)
          ("Kind" 10 nil)
          ("Platform" 0 nil)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

(defun rustic-cargo-list-outdated (&optional path)
  (interactive)
  (let* ((dir (or path (rustic-buffer-workspace)))
        (buf (get-buffer-create rustic-cargo-oudated-buffer-name))
        (default-directory dir)
        (inhibit-read-only t))
    (make-process :name rustic-cargo-outdated-process-name
                  :buffer buf
                  :command '("cargo" "outdated" "--depth" "1")
                  :filter #'rustic-cargo-outdated-filter
                  :sentinel #'rustic-cargo-outdated-sentinel)
    (with-current-buffer buf
      (setq-local default-directory dir)
      (erase-buffer))))

(defun rustic-cargo-reload-outdated ()
  (interactive)
  (rustic-cargo-list-outdated default-directory))

(defun rustic-cargo-outdated-filter (proc output)
  (let ((inhibit-read-only t))
    (with-current-buffer (process-buffer proc)
      (insert output))))

(defun rustic-cargo-outdated-sentinel (proc output)
  (let ((buf (process-buffer proc))
        (inhibit-read-only t)
        (exit-status (process-exit-status proc)))
    (if (zerop exit-status)
        (with-current-buffer buf
          (goto-char (point-min))
          (forward-line 2)
          (rustic-cargo-outdated-generate-menu (buffer-substring (point) (point-max)) buf))
      (with-current-buffer buf
        (let ((out (buffer-string)))
          (if (= exit-status 101)
              (rustic-cargo-install-crate "outdated")
            (message out)))))))

(defun rustic-cargo-install-crate (crate)
  (let ((cmd (format "cargo install cargo-%s" crate)))
    (when (yes-or-no-p (format "Cargo-%s missing. Install ? " crate))
      (async-shell-command cmd "cargo" "cargo-error"))))

(defun rustic-cargo-outdated-generate-menu (output buf)
  (let ((inhibit-read-only t))
    (with-current-buffer buf
      (rustic-cargo-outdated-mode)
      (erase-buffer)
      (goto-char (point-min))
      (setq tabulated-list-entries
            (mapcar #'rustic-cargo-outdated-menu-entry (split-string output "\n" t)))
      (tabulated-list-print t)
      (pop-to-buffer buf))))

(defun rustic-cargo-outdated-menu-entry (crate)
  (let* ((fields (split-string crate "\s\s+" ))
         (name (nth 0 fields))
         (project (nth 1 fields))
         (compat (nth 2 fields)))
    (list name `[,name
                 ,project
                 ,(if (when (not (string= "---" compat))
                          (version< project compat))
                      (propertize compat 'font-lock-face `(:foreground ,rustic-cargo-outdated-face))
                    compat)
                 ,(nth 3 fields)
                 ,(nth 4 fields)
                 ,(nth 5 fields)])))

(defun rustic-cargo-mark-upgrade ()
  "Mark an upgradable package."
  (interactive)
  (let ((project (aref (tabulated-list-get-entry) 1))
        (compat (aref (tabulated-list-get-entry) 2)))
    (unless (or (string= "---" compat)
                (not (version< project compat)))
      (tabulated-list-put-tag "U" t))))

(defun rustic-cargo-mark-all-upgrades ()
  "Mark all upgradable packages in the Package Menu."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (let ((project (aref (tabulated-list-get-entry) 1))
            (compat (aref (tabulated-list-get-entry) 2)))
        (if (or (string= "---" compat)
                (not (version< project compat)))
            (forward-line)
          (tabulated-list-put-tag "U" t))))))

(defun rustic-cargo-menu-mark-unmark ()
  "Clear any marks on a package."
  (interactive)
  (tabulated-list-put-tag " " t))

(defun rustic-cargo-upgrade-execute ()
  (interactive)
  (let (crates)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let ((cmd (char-after))
              (crate (tabulated-list-get-id)))
          (when (eq cmd ?U)
            (push (substring-no-properties crate) crates)))
        (forward-line)))
    (if crates
        (let ((msg (format "Upgrade %s ?" (mapconcat 'identity crates " "))))
          (when (yes-or-no-p msg)
            (rustic-cargo-upgrade-crates crates)))
      (user-error "No operations specified"))))

(defun rustic-cargo-upgrade-crates (crates)
  (let (upgrade
        update)
    (dolist (crate crates)
      (setq upgrade (concat upgrade (format " -d %s" crate)))
      (setq update (concat update (format " -p %s" crate))))
    (let ((output (shell-command-to-string (format "cargo upgrade %s" upgrade))))
      (if (string-match "error: no such subcommand:" output)
          (rustic-cargo-install-crate "edit")
        (and (shell-command-to-string (format "cargo update %s" update))
             (rustic-cargo-reload-outdated))))))


;;;;;;;;;;;;;;;;
;; Interactive

;;;###autoload
(defun rustic-cargo-build ()
  (interactive)
  (call-interactively 'rustic-compile "cargo build"))

;;;###autoload
(defun rustic-cargo-run ()
  (interactive)
  (call-interactively 'rustic-compile "cargo run"))

(provide 'rustic-cargo)
;;; rustic-cargo.el ends here