;;; evil-mc-command-record.el --- Record info for the currently running command

;;; Commentary:

;; This file contains functions for recording information about
;; the currently running command

(require 'cl)
(require 'evil)
(require 'evil-mc-common)

;;; Code:

(defun evil-mc-command-reset ()
  "Clear the currently saved command info."
  (setq evil-mc-command nil)
  (setq evil-mc-recording-command nil))

(defun evil-mc-get-evil-state ()
  "Get the current evil state."
  (cond ((evil-insert-state-p) :insert)
        ((evil-motion-state-p) :motion)
        ((evil-visual-state-p) :visual)
        ((evil-normal-state-p) :normal)
        ((evil-replace-state-p) :replace)
        ((evil-operator-state-p) :operator)
        ((evil-emacs-state-p) :emacs)))

(defun evil-mc-get-command-property (name)
  "Return the current command property with NAME."
  (evil-mc-get-object-property evil-mc-command name))

(defun evil-mc-set-command-property (&rest properties)
  "Set one or more command PROPERTIES and their values into `evil-mc-command'."
  (setq evil-mc-command (apply 'evil-mc-put-object-property
                           (cons evil-mc-command properties))))

(defun evil-mc-add-command-property (&rest properties)
  "Append to values of one or more PROPERTIES into `evil-mc-command'."
  (while properties
    (let* ((name (pop properties))
           (new-value (pop properties))
           (old-value (evil-mc-get-command-property name)))
      (cond ((null old-value)
             (evil-mc-set-command-property name new-value))
            ((vectorp old-value)
             (evil-mc-set-command-property name (vconcat old-value new-value)))
            ((listp old-value)
             (evil-mc-set-command-property name (nconc old-value new-value)))
            (t
             (error "Current value is not a sequence %s" old-value))))))

(defun evil-mc-get-command-keys-vector (&optional name)
  "Get the command keys, stored at the property with NAME as a vector."
  (evil-mc-get-command-property (or name :keys)))

(defun evil-mc-get-command-keys-count ()
  "Get the current command numeric prefix or one."
  (or (evil-mc-get-command-property :keys-count) 1))

(defun evil-mc-get-command-keys-string (&optional name)
  "Get the command keys, stored at the property with NAME, as a string."
  (when evil-mc-command
    (let* ((keys (evil-mc-get-command-property (or name :keys)))
           (keys-string (mapcar (lambda (k) (if (characterp k)
                                                (char-to-string k) ""))
                                keys)))
      (apply 'concat keys-string))))

(defun evil-mc-get-command-name ()
  "Return the current command name."
  (when evil-mc-command
    (evil-mc-get-command-property :name)))

(defun evil-mc-get-command-state ()
  "Return the current command end evil state."
  (when evil-mc-command
    (evil-mc-get-command-property :evil-state-end)))

(defun evil-mc-get-command-last-input ()
  "Return the last input for the current command."
  (when evil-mc-command
    (evil-mc-get-command-property :last-input)))

(defun evil-mc-save-keys (flag pre-name post-name keys)
  "Save KEYS at PRE-NAME or POST-NAME according to FLAG."
  (ecase flag
    (pre (evil-mc-add-command-property pre-name keys))
    (post (evil-mc-add-command-property post-name keys))))

(defun evil-mc-begin-command-save ()
  "Initialize all variables at the start of saving a command."
  (when (evil-mc-recording-debug-p) (message "Command %s %s" this-command (this-command-keys)))
  (when (and (not (evil-mc-executing-command-p))
             (not (evil-mc-recording-command-p)))
    (setq evil-mc-command nil)
    (when (and (evil-mc-has-cursors-p)
               (not (evil-emacs-state-p))
               (evil-mc-known-command-p this-command))
      (setq evil-mc-recording-command t)
      (evil-mc-set-command-property :name this-command
                                :keys-pre (this-command-keys-vector)
                                :evil-state-begin (evil-mc-get-evil-state))
      (when (evil-mc-recording-debug-p) (message "Record-begin %s" evil-mc-command)))))
(put 'evil-mc-begin-command-save 'permanent-local-hook t)

(defun evil-mc-save-keys-motion (flag)
  "Save the current evil motion key sequence."
  (when (evil-mc-recording-command-p)
    (evil-mc-save-keys flag
                   :keys-motion-pre
                   :keys-motion-post
                   (this-command-keys-vector))
    (when (evil-mc-recording-debug-p)
      (message "Record-motion %s %s %s %s"
               flag (this-command-keys) (this-command-keys-vector) evil-state))))

(defun evil-mc-save-keys-operator (flag)
  "Save the current evil operator key sequence."
  (when (and (evil-mc-recording-command-p)
             (memq evil-state '(operator)))
    (evil-mc-save-keys flag
                   :keys-operator-pre
                   :keys-operator-post
                   (this-command-keys-vector))
    (when (evil-mc-recording-debug-p)
      (message "Record-operator %s %s %s %s"
               flag (this-command-keys) (this-command-keys-vector) evil-state))))

(defun evil-mc-finish-command-save ()
  "Completes the save of a command."
  (when (evil-mc-recording-command-p)
    (evil-mc-set-command-property :evil-state-end (evil-mc-get-evil-state)
                              :last-input last-input-event
                              :keys-post (this-command-keys-vector)
                              :keys-post-raw (this-single-command-raw-keys))
    (when (evil-mc-recording-debug-p)
      (message "Record-finish %s %s" evil-mc-command this-command))
    (ignore-errors
      (condition-case error
          (evil-mc-finalize-command)
        (error (message "Saving command %s failed with %s"
                        (evil-mc-get-command-name)
                        (error-message-string error))
               nil))))
  (setq evil-mc-recording-command nil))
(put 'evil-mc-finish-command-save 'permanent-local-hook t)

(defun evil-mc-finalize-command ()
  "Make the command data ready for use, after a save."
  (let* ((keys-pre (evil-mc-get-command-property :keys-pre))
         (keys-pre-with-count (evil-extract-count keys-pre))
         (keys-pre-count (nth 0 keys-pre-with-count))
         (keys-pre-cmd (vconcat (nth 2 keys-pre-with-count)))
         (keys-post (evil-mc-get-command-property :keys-post))
         (keys-motion-pre (evil-mc-get-command-property :keys-motion-pre))
         (keys-motion-post (evil-mc-get-command-property :keys-motion-post))
         (keys-operator-pre (evil-mc-get-command-property :keys-operator-pre))
         (keys-operator-post (evil-mc-get-command-property :keys-operator-post)))
    (evil-mc-set-command-property :keys-count keys-pre-count)
    (evil-mc-set-command-property
     :keys (cond ((or keys-motion-post keys-motion-pre)
                  (or keys-motion-post keys-motion-pre))
                 ((or keys-operator-pre keys-operator-post)
                  (vconcat (if keys-pre-count keys-pre keys-pre-cmd)
                           (if (or (equal keys-operator-pre keys-pre-cmd)
                                   (and (equal keys-operator-pre
                                               keys-operator-post)
                                        (not (or
                                              (equal keys-operator-pre [?t])
                                              (equal keys-operator-pre [?f]))))
                                   (> (length keys-operator-pre) 1))
                               keys-operator-post
                             (vconcat keys-operator-pre
                                      keys-operator-post))))
                 (t (or keys-post keys-pre)))))
  (when (evil-mc-recording-debug-p)
    (message "Record-done %s pre %s post %s keys-motion %s keys-operator %s count %s keys %s"
             (evil-mc-get-command-name)
             (evil-mc-get-command-keys-string :keys-pre)
             (evil-mc-get-command-keys-string :keys-post)
             (evil-mc-get-command-keys-string :keys-motion-post)
             (evil-mc-get-command-keys-string :keys-operator-post)
             (evil-mc-get-command-keys-string :keys-count)
             (evil-mc-get-command-keys-string :keys))))

(provide 'evil-mc-command-record)

;;; evil-mc-command-record.el ends here