;;; guix-sudoloop-pull-ups.el --- Guix pull and update with sudoloop  -*- lexical-binding: t; -*-

;; Guix Sudoloop Pull Ups

;; Copyright (C) 2025 Benjamin Slade

;; Author: Benjamin Slade <slade@lambda-y.net>
;; Maintainer: Benjamin Slade <slade@lambda-y.net>
;; URL: https://github.com/emacsomancer/emacs-guix-sudoloop-pull-ups
;; Package-Version: 0.1
;; Version: 0.1
;; Package-Requires: ((emacs "24.3"))
;; Created: 2025-04-07T11:51:15-05:00

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; Elisp code which creates and runs shell scripts to more efficiently update Guix.
;; With sudoloop (for `guix system reconfigure') and multiple attempts.

;;; Installation:
;; ADDME

;;; Usage:
;; ADDME

;;; Advice:
;; None currently.

;;; Code:

(defgroup guix-sudoloop-pull-ups nil
  "Guix pulls and updates the easy way."
  :group 'tools)

(defcustom guix-sudoloop-pull-ups--su "sudo"
  "Name of super-user do function.

Probably `sudo' is really the only choice.  Not sure
we can do everything with `doas', even if there were better
doas integration in Guix."
  :group 'guix-sudoloop-pull-ups
  :type 'string)

(defcustom guix-sudoloop-pull-ups--operations
  '(("guix" "pull")
    ("guix" "package" "-u")
    ("sudo" "guix" "system" "reconfigure" "$HOME/.config/guix/config.sushoma.scm")
    ("guix" "home" "reconfigure" "$HOME/src/guix-config/home-configuration.sushoma.scm"))
  "List of list of operations and arguments."
  :group 'guix-sudoloop-pull-ups
  :type 'sexp)

;; (setopt guix-sudoloop-pull-ups--operations '(("guix" "pull")
;;     ("sudo" "guix" "system" "reconfigure" "$HOME/.config/guix/config.sushoma.scm")
;;     ("guix" "home" "reconfigure" "$HOME/src/guix-config/home-configuration.sushoma.scm")))

(defcustom guix-sudoloop-pull-ups--conjoiner
  "&&"
  "How to conjoin operations."
  :group 'guix-sudoloop-pull-ups
  :type 'string)

(defcustom guix-sudoloop-pull-ups--max-iterations 5
  "How many times to try each update-related command."
  :group 'guix-sudoloop-pull-ups
  :type 'integer)

(defcustom guix-sudoloop-pull-ups--sudolooptime 60
  "Setting for SUDO_LOOP_TIME."
  :group 'guix-sudoloop-pull-ups
  :type 'integer)

(defcustom guix-sudoloop-pull-ups--directory "/tmp/guix-pull-ups/"
  "Directory for temporary shell files."
  :group 'guix-sudoloop-pull-ups
  :type 'string)

(defcustom guix-sudoloop-pull-ups--logfile "guix-sudoloop-pullups-"
  "Base-name for log-files."
  :group 'guix-sudoloop-pull-ups
  :type 'string)

(defcustom guix-sudoloop-pull-ups--conjoiner "&&"
  "Conjoiner between operations.

Defaults to `&&'; could be `;'."
  :group 'guix-sudoloop-pull-ups
  :type 'string)

(defcustom guix-sudoloop-pull-ups--shells
  `("spawn-external-terminal-emulator"
    ,(when (require 'vterm nil 'noerror) "vterm")
    ,(when (require 'eat nil 'noerror) "eat")
    "ansi-term"
    "term"
    "eshell"
    "shell")
  "List of available shells for guix-sudoloop-pull-ups."
  :group 'guix-sudoloop-pull-ups
  :type 'sexp)

;; TODO: maybe figure out better integration with detached.el
;; (con: less generalised code/system)
(defcustom guix-sudoloop-pull-ups--external-guard
  (cond
   ((executable-find "dtach") (list "dtach" "-A /tmp/dtach "))
   ((executable-find "screen") (list "screen" " -dmS guix_sudoloop_pullups && screen -S guix_sudoloop_pullups -dm "))
   ((executable-find "tmux") (list "tmux" "new-session -d "))
   (t nil))
  "Default external terminal emulator guard to use."
  :group 'guix-sudoloop-pull-ups--external-guard
  :type 'string)

(defcustom guix-sudoloop-pull-ups--default-external
  (getenv "TERMINAL")
  "Default external terminal emulator to use.
Defaults to value of $TERMINAL."
  :group 'guix-sudoloop-pull-ups
  :type 'string)

;; (setq guix-sudoloop-pull-ups--default-external "zutty")

(defcustom guix-sudoloop-pull-ups--shell "shell"
  "Choose from `guix-sudoloop-pull-ups--shells'."
  :options guix-sudoloop-pull-ups--shells
  :group 'guix-sudoloop-pull-ups
  :type 'string)

;; (defcustom guix-sudoloop-pull-ups--logging nil
;;   "Whether to write out a log file or not.

;; TODO: customisable location for log file,
;; independent of shell script location.

;; NOTE: Currently defaulting to nil because
;; the logs don't get written out in the most
;; useful/readable fashion.")

;; ;; (setopt guix-sudoloop-pull-ups--logging t)

;; TODO: check if external terminal is detached or not (i.e., if emacs dies, does it die?)

(defun guix-sudoloop-pull-ups--spawn-extterm ()
  (let ((tempbuff "*launch external term*"))
    (get-buffer-create tempbuff)
    ;; (detached-shell-command
    (start-process-shell-command
     ;; " "
     ;; " "
     "guix-pull-up"
     nil
     (concat 
      (car guix-sudoloop-pull-ups--external-guard)
      " "
      (mapconcat #'identity (cdr guix-sudoloop-pull-ups--external-guard) " ")
      " "
      guix-sudoloop-pull-ups--default-external
      " "
      "-e"
      " "
      "\"cd " guix-sudoloop-pull-ups--directory
      " && "
      "./guix-sudoloop-pull-up\"")))
     ;; )
  )

;; (defun guix-sudoloop-pull-ups--spawn-extterm ()
;;   (let ((tempbuff "*launch external term*"))
;;     (get-buffer-create tempbuff)
;;     (call-process
;;      (car guix-sudoloop-pull-ups--external-guard)
;;      nil 
;;      ;; guix-sudoloop-pull-ups--default-external
;;      0 ;; tempbuff
;;     nil
;;     (mapconcat #'identity (cdr guix-sudoloop-pull-ups--external-guard) " ")
;;     guix-sudoloop-pull-ups--default-external
;;     "-e"
;;     (concat "cd " guix-sudoloop-pull-ups--directory
;;                           " && "
;;                           "./"
;;                           "guix-sudoloop-pull-up")
;;     )))

;; (defun guix-sudoloop-pull-ups--spawn-extterm ()
;;   (let ((tempbuff "*launch external term*"))
;;     (get-buffer-create tempbuff)
;;     (call-process guix-sudoloop-pull-ups--default-external
;;                   nil
;;                   0 ;; tempbuff
;;                   nil
;;                   "-e"
;;                   (concat "cd " guix-sudoloop-pull-ups--directory
;;                           " && "
;;                           "./"
;;                           "guix-sudoloop-pull-up"))))


;; from: https://stackoverflow.com/a/23299809/570251
(defun guix-sudoloop-pull-ups--process-exit-code-and-output (program &rest args)
  "Run PROGRAM with ARGS and return the exit code and output in a list."
  (with-temp-buffer
    (list (apply 'call-process program nil (current-buffer) nil args)
          (buffer-string))))

(defun guix-sudoloop-pull-ups--close-file (file)
  (let ((buffer-modified-p nil)
        (buf (get-file-buffer file)))
    (when buf
      (kill-buffer buf))))

(defun guix-sudoloop-pull-ups--shell-script-writer (filename code)
  "Generalised shell script generator.

Write `FILENAME' containing `CODE'."
  (unless (file-exists-p guix-sudoloop-pull-ups--directory)
    (mkdir guix-sudoloop-pull-ups--directory))
  (guix-sudoloop-pull-ups--close-file (concat guix-sudoloop-pull-ups--directory filename))
  (with-temp-file (concat guix-sudoloop-pull-ups--directory filename)
    (insert code))
  (shell-command (concat "chmod +x " guix-sudoloop-pull-ups--directory filename)))
  
(defun guix-sudoloop-pull-ups--make-sudoloop-sh ()
  "Write up `sudoloop' shell script.

See: https://codeberg.org/clarfonthey/sudoloop "
  (guix-sudoloop-pull-ups--shell-script-writer
   "sudoloop"
   (concat 
    "#!/bin/sh
sudo --validate || exit $?

{
	test -n \"$SUDO_LOOP_TIME\" || SUDO_LOOP_TIME="
    (number-to-string guix-sudoloop-pull-ups--sudolooptime) "\n"
    "trap exit INT
	while true; do
		sudo --non-interactive --validate || exit $?
		sleep \"$SUDO_LOOP_TIME\" & wait $!
	done
} &

command \"$@\"
kill -INT %1
wait
")))

;; (guix-sudoloop-pull-ups--make-sudoloop-sh)

;; this addresses issues like:
;; substitute: looking for substitutes on 'https://substitutes.nonguix.org'...   0.0%guix substitute: error: TLS error in procedure 'write_to_session_record_port': Error in the push function.
;; guix home: error: `/gnu/store/kdxzcbwpv7dn4091xpn41qhm1y30lzyj-guix-1.4.0-34.5058b40/bin/guix substitute' died unexpectedly
;;
;; also guix pull trouble, e.g.:
;; Updating channel 'guix' from Git repository at 'https://git.savannah.gnu.org/git/guix.git'...
;; guix pull: error: Git error: unexpected http status code: 502
;; 
(defun guix-sudoloop-pull-ups--make-multiple-attempts-sh ()
    "Make shell script for multiple_attempts"
    (guix-sudoloop-pull-ups--shell-script-writer
     "multiple_attempts"
     (concat
      "#!/bin/sh

max_iterations="
      (number-to-string guix-sudoloop-pull-ups--max-iterations) "\n"
      "command=\"$*\"

RED='\e[0;31m'
GREEN='\e[0;32m'
PURPLE='\e[0;35m'
WHITE='\e[1;37m'
NORMAL='\e[0m' # normal colour

for i in $(seq 1 $max_iterations)
do
    eval \"${command}\"
    # $0 # $1
    result=$?
    if [ \"$result\" -eq 0 ]
    then
        printf \"${PURPLE}%s${NORMAL} ${GREEN}succeeded${NORMAL} after ${WHITE}%s${NORMAL} attempts with ${GREEN}exit code %s${NORMAL}\n\" \"$command\" \"$i\" \"$result\"
        break
        # return 1
    else
        printf \"${PURPLE}%s${NORMAL} ${RED}failed${NORMAL} with ${RED}exit code %s${NORMAL} ${WHITE}(%s of %s attempts remaining)${NORMAL}\n\" \"$command\" \"$result\" $((max_iterations - i)) \"$max_iterations\"
        sleep 1
    fi
done

if [ \"$result\" -ne 0 ]
then
    printf \"${PURPLE}%s${NORMAL} ${RED}failed finally${NORMAL} after ${WHITE}%s${NORMAL} attempts.\n\"  \"$command\" \"$i\"
fi")))
      
(defun guix-sudoloop-pull-ups--commands ()
  "Make shell script for commands to do in sequence."
  (let ((first-ops (mapconcat #'identity (car guix-sudoloop-pull-ups--operations) " "))
        (rest-ops
         (let ((conjoined ""))
           (dolist (item (cdr guix-sudoloop-pull-ups--operations))
             (setq conjoined
                   (concat
                    conjoined
                    " " guix-sudoloop-pull-ups--conjoiner " "
                    "./multiple_attempts "
                    (mapconcat 'identity item " "))))
           conjoined)))
    (guix-sudoloop-pull-ups--shell-script-writer
     "guix-commands"
     (concat                                            
      "#!/bin/sh\n"
      "./multiple_attempts "
      first-ops
      rest-ops))))

(defun guix-sudoloop-pull-ups--wrapper ()
  "Make shell script for main wrapper."
  (guix-sudoloop-pull-ups--shell-script-writer
   "guix-sudoloop-pull-up"  
   (concat   "#!/bin/sh\n"
             ;; "echo \"Guix Sudoloop Pull Ups initialising....\n\""
             ;; "echo \"Enter password for sudoloop:\n\""
             ;; (if guix-sudoloop-pull-ups--logging 
             ;;     (concat "exec script -q -c \"./sudoloop ./guix-commands\" -O "
             ;;             guix-sudoloop-pull-ups--directory guix-sudoloop-pull-ups--logfile
             ;;             (format-time-string "%Y-%m-%d_%H-%M-%S" (current-time)) ".log && ")
             "sudoloop ./guix-commands\n"
             ;; )
             ;; "sudoloop ./guix-commands\n"
             "echo 'Operations completed successfully. Press RETURN to exit.' && read -r _")))

(defun guix-sudoloop-pull-ups-run-all ()
  "Run Guix System pulls and updates."
  (interactive)
       (guix-sudoloop-pull-ups--make-sudoloop-sh)
       (guix-sudoloop-pull-ups--make-multiple-attempts-sh)
       (guix-sudoloop-pull-ups--commands)
       (guix-sudoloop-pull-ups--wrapper)
       ;; (guix-sudoloop-pull-ups--run-in-vterm)
       (guix-sudoloop-pull-ups--spawn-extterm)
       )

(defun guix-sudoloop-pull-up-single-run (command-number)
  "Run a specific Guix operation under `multiple_attempts'."
  (interactive)
  ;; (if command-number
  ;;
  ;; (completing-read
  ;; "Which dataset of info: "
  ;; (cl-loop for (key . _) in choices
  ;;          collect key))
  ;; (guix-sudoloop-pull-ups--make-sudoloop-sh)
  ;; (guix-sudoloop-pull-ups--make-multiple-attempts-sh)
  ;; (guix-sudoloop-pull-ups--commands)
  ;; (guix-sudoloop-pull-ups--wrapper)
  ;; ;; (guix-sudoloop-pull-ups--run-in-vterm)
  ;; (guix-sudoloop-pull-ups--spawn-extterm)
  )


;; functions
(defun guix-sudoloop-pull-ups--run-in-vterm ()
  (interactive)
  (let ((command (concat "cd " guix-sudoloop-pull-ups--directory
                         " && "
                         "./"
                         "guix-sudoloop-pull-up")))
    (with-current-buffer (vterm (concat "*" command "*"))
      ;; (set-process-sentinel vterm--process #'run-in-vterm-kill)
      (vterm-send-string command)
      (vterm-send-return))))

(defun guix-sudoloop-pull-ups--run-in-eat ()
  (interactive)
  (let ((command (concat " cd " guix-sudoloop-pull-ups--directory
                         " && "
                         "./"
                         "guix-sudoloop-pull-up")))
    (get-buffer-create "*guix-pull-ups*")
    ;; (with-current-buffer
    (eat command nil)
    ;; (set-process-sentinel vterm--process #'run-in-vterm-kill)
    ;; (eat-send-string command)
    ;; (eat-send-return)
    ;; )
    ))

(provide 'guix-sudoloop-pull-ups)
;;; guix-sudoloop-pull-ups.el ends here
