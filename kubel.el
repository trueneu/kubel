;;; kubel.el --- Control Kubernetes with limited permissions -*- lexical-binding: t; -*-

;; Copyright (C) 2018, Adrien Brochard

;; This file is NOT part of Emacs.

;; This  program is  free  software; you  can  redistribute it  and/or
;; modify it  under the  terms of  the GNU  General Public  License as
;; published by the Free Software  Foundation; either version 2 of the
;; License, or (at your option) any later version.



;; This program is distributed in the hope that it will be useful, but
;; WITHOUT  ANY  WARRANTY;  without   even  the  implied  warranty  of
;; MERCHANTABILITY or FITNESS  FOR A PARTICULAR PURPOSE.   See the GNU
;; General Public License for more details.

;; You should have  received a copy of the GNU  General Public License
;; along  with  this program;  if  not,  write  to the  Free  Software
;; Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
;; USA

;; Version: 1.0
;; Author: Adrien Brochard
;; Keywords: kubernetes k8s tools processes
;; URL: https://github.com/abrochard/kubel
;; License: GNU General Public License >= 3
;; Package-Requires: ((transient "0.1.0") (emacs "25.3") (dash "2.12.0") (s "1.2.0") (yaml-mode "0.0.14") (ht "2.4") (asoc "0.6.1"))

;;; Commentary:

;; Emacs extension for controlling Kubernetes with limited permissions.

;;; Usage:

;; To list the pods in your current context and namespace, call
;;
;; M-x kubel
;;
;; To set the path to the kubectl config file, call:
;; M-x kubel-set-kubectl-config-file
;;
;; or
;;
;; (kubel-set-kubectl-config-file <path to desired config file>)
;; ex: (kubel-set-kubectl-config-file "~/.kube/another-config")
;;
;; To set said namespace and context, respectively call
;;
;; M-x kubel-set-namespace
;; M-x kubel-set-context
;;
;; Note that namespace will autocomplete but not context,
;; this is because I interact with kubernetes through a user who
;; does not have permissions to list namespaces.
;;
;; To switch to showing a different resource, use the `R` command or
;;
;; M-x kubel-set-resource
;;
;; This will let you select a resource and re-display the kubel buffer.

;;; Shortcuts:

;; On the kubel screen, place your cursor on a resource
;;
;; enter => get resource details
;; C-u enter => describe resource
;; h => help popup
;; ? => help popup
;; E => quick edit any resource
;; g => refresh
;; k => delete popup
;; r => see the rollout history for resource
;; p => port forward pod
;; l => log popup
;; e => exec popup
;; j => jab deployment to force rolling update
;; S => scale replicas
;; C => set context
;; n => set namespace
;; R => set resource
;; K => set kubectl config file
;; F => set output format
;; f => set a substring filter for resource name
;; M-n => jump to the next highlighted resource
;; M-p => jump to previous highlighted resource
;; m => mark item
;; u => unmark item
;; M => mark all items
;; U => unmark all items
;; c => copy popup
;; $ => show process buffer
;; s => show only resources with specified label value

;;; Customize:

;; By default, kubel log tails from the last 100 lines, you can change the `kubel-log-tail-n` variable to set another line number.

;;; Code:

(require 'transient)
(require 'dash)
(require 's)
(require 'yaml-mode)
(require 'tramp)
(require 'subr-x)
(require 'eshell)
(require 'dired)
(require 'json)
(require 'ht)
(require 'asoc)

(defgroup kubel nil "Customisation group for kubel."
  :group 'extensions)

(defconst kubel--list-sort-key
  '("NAME" . nil)
  "Sort table on this key.")

(defface kubel-status-running
  '((default . (:inherit success)))
  "The face to use for the Running status.")

(defface kubel-status-healthy
  '((default . (:inherit success)))
  "The face to use for the Healthy status.")

(defface kubel-status-active
  '((default . (:inherit success)))
  "The face to use for the Active status.")

(defface kubel-status-ready
  '((default . (:inherit success)))
  "The face to use for the Ready status.")

(defface kubel-status-true
  '((default . (:inherit success)))
  "The face to use for the True status.")

(defface kubel-status-unknown
  '((default . (:inherit warning)))
  "The face to use for the Unknown status.")

(defface kubel-status-error
  '((default . (:inherit error)))
  "The face to use for the Error status.")

(defface kubel-status-evicted
  '((default . (:inherit error)))
  "The face to use for the Evicted status.")

(defface kubel-status-memory-pressure
  '((default . (:inherit error)))
  "The face to use for the Memory Pressure status.")

(defface kubel-status-pid-pressure
  '((default . (:inherit error)))
  "The face to use for the PID Pressure status.")

(defface kubel-status-disk-pressure
  '((default . (:inherit error)))
  "The face to use for the Disk Pressure status.")

(defface kubel-status-revision-missing
  '((default . (:inherit error)))
  "The face to use for the Revision Missing status.")

(defface kubel-status-revision-failed
  '((default . (:inherit error)))
  "The face to use for the Revision Failed status.")

(defface kubel-status-network-unavailable
  '((default . (:inherit error)))
  "The face to use for the Network Unavailable status.")

(defface kubel-status-completed
  '((default . (:foreground "yellow")))
  "The face to use for the Completed status.")

(defface kubel-status-crash-loop-backoff
  '((default . (:inherit error)))
  "The face to use for the Crash Loop Backoff status.")

(defface kubel-status-terminating
  '((default . (:foreground "blue")))
  "The face to use for the Terminating status.")

(defcustom kubel-status-faces
  '(("Running" . kubel-status-running)
    ("Healthy" . kubel-status-healthy)
    ("Active" . kubel-status-active)
    ("Ready" . kubel-status-ready)
    ("True" . kubel-status-true)
    ("Unknown" . kubel-status-unknown)
    ("Error" . kubel-status-error)
    ("Evicted" . kubel-status-evicted)
    ("MemoryPressure" . kubel-status-memory-pressure)
    ("PIDPressure" . kubel-status-pid-pressure)
    ("DiskPressure" . kubel-status-disk-pressure)
    ("RevisionMissing" . kubel-status-revision-missing)
    ("RevisionFailed" . kubel-status-revision-failed)
    ("NetworkUnavailable" . kubel-status-network-unavailable)
    ("Completed" . kubel-status-completed)
    ("CrashLoopBackOff" . kubel-status-crash-loop-backoff)
    ("Terminating" . kubel-status-terminating))
  "Associative list of status to face."
  :type '(alist :key-type string
                :value-type face)
  :group 'kubel)

(defface kubel-percentage-warning-face
  '((default . (:inherit warning)))
  "The face to use for warning percentages.")

(defface kubel-percentage-critical-face
  '((default . (:inherit error)))
  "The face to use for critical percentages.")

(defcustom kubel-percentage-critical-threshold 90
  "Threshold for critical percentage values."
  :type 'integer
  :group 'kubel)

(defcustom kubel-percentage-warning-threshold 70
  "Threshold for warning percentage values."
  :type 'integer
  :group 'kubel)

(defcustom kubel-kubectl "kubectl"
  "Kubectl binary path."
  :type '(file :must-match t)
  :group 'kubel)

(defconst kubel--process-buffer "*kubel-process*"
  "Kubel process buffer name.")

(defcustom kubel-output "yaml"
  "Format for output: json|yaml|wide|custom-columns=..."
  :type 'string
  :group 'kubel)

(defcustom kubel-log-tail-n 100
  "Default number of lines to tail."
  :type 'integer
  :group 'kubel)

(defcustom kubel-log-max-log-requests 50
  "Max number of parallel log tails."
  :type 'integer
  :group 'kubel)

(defcustom kubel-list-wide nil
  "Control whether list views show additional colums.

true   - use '-o wide' for list views to show additional columns
false  - do not use '-o wide' for list views, hiding additional columns"
  :type 'boolean
  :group 'kubel)

(defcustom kubel-use-namespace-list 'auto
  "Control behavior for namespace completion.

auto - default, use `kubectl auth can-i list namespace` to determine if we can
       list namespaces
on   - always assume we can list namespaces
off  - always assume we cannot list namespaces"
  :type '(choice (const :tag "Auto" auto)
                 (const :tag "On" on)
                 (const :tag "Off" off))
  :group 'kubel)

(defcustom kubel-shell-buffer-name-format "kubel:%C:%n:%t:%c@%p"
  "Define the name format used for pod shell buffers.

This is a format string with %-sequences that will be substituted
with information about the shell's connection. The following
%-sequences are defined:

%t: The shell type. Examples of this are `shell` and `eshell`
%c: The container name
%p: The pod name
%n: The current namespace
%C: The current context"
  :type 'string
  :group 'kubel)

(defcustom kubel-kill-buffer-query t
  "Non-nil means that killing a modified resource buffer has to be confirmed.
This is used by `kubel-kill-buffer'."
  :type 'boolean
  :group 'kubel)

(defcustom kubel-filter-hides nil
  "Non-nil means that if filter is applied, non-matching lines are hidden."
  :type 'boolean
  :group 'kubel)

(defun kubel--append-to-process-buffer (str)
  "Append string STR to the process buffer."
  (with-current-buffer (get-buffer-create kubel--process-buffer)
    (read-only-mode -1)
    (goto-char (point-max))
    (insert (format "%s\n" str))))

(defvar-local kubel--global-resources-set-cached (ht)
  "Hashset of resources that are global, i.e. not namespaced")

(defvar-local kubel--last-command nil)

;; TODO fill this in
(defvar kubel--internal-type-ownership-alist
  '((deployments . pods)
    (replicasets . pods)
    (daemonsets . pods)
    (cronjobs . jobs)
    (statetfulsets . pods))
  "Maps a resource type to its children.")

;; TODO fill this in
(defvar kubel--internal-type-resource-type-alias-alist
  '((deployments . ("Deployments" "deployments" "deployments.apps"))
    (replicasets . ("ReplicaSets" "replicasets" "replicasets.apps"))
    (daemonsets . ("DaemonSets" "daemonsets" "daemonsets.apps"))
    (pods . ("Pods" "pods"))
    (jobs . ("Jobs" "jobs" "jobs.batch"))
    (cronjobs . ("CronJobs" "cronjobs" "cronjobs.batch"))
    (statefulsets . ("StatefulSets" "statefulsets" "statefulsets.apps")))
  "Maps a resource type to a list of possible API resource type names.")

;; TODO fill this in
(defvar kubel--resource-type-singular->plural-ht
  (ht ("Deployment" "Deployments")
      ("deployment" "deployments")
      ("ReplicaSet" "ReplicaSets")
      ("replicaset" "replicasets")
      ("DaemonSet" "DaemonSets")
      ("daemonset" "daemonsets")
      ("CronJob" "CronJobs")
      ("cronjob" "cronjobs")
      ("Job" "Jobs")
      ("job" "jobs")
      ("StatefulSet" "StatefulSets")
      ("statefulset" "statefulsets"))
  "Maps a singular resource type to plural.")

(defvar kubel--resource-type->aliases-ht
  (let ((result (ht)))
    (dolist (aliases kubel--internal-type-resource-type-alias-alist result)
      (dolist (alias (cdr aliases))
        (dolist (resource-type (cdr aliases))
          (setf (ht-get result resource-type)
                (cons alias (ht-get result resource-type))))))))

(defvar kubel--resource-type->internal-type-ht
  (let ((result (ht)))
    (dolist (aliases kubel--internal-type-resource-type-alias-alist result)
      (dolist (alias (cdr aliases))
        (ht-set result alias (car aliases))))))

;; TODO: find a way to make it universal?

(defvar-local kubel--last-parent nil)

(defun kubel--log-command (process-name cmd)
  "Log the kubectl command to the process buffer.

PROCESS-NAME is the name of the process.
CMD is the kubectl command as a list."
  (let ((str-cmd (if (equal 'string (type-of cmd)) cmd (mapconcat #'identity cmd " "))))
    (setq kubel--last-command str-cmd)
    (kubel--append-to-process-buffer
     (format "[%s]\ncommand: %s" process-name str-cmd))))

(defvar kubel--output-buffer-name "*kubel-output*")

(defun kubel--exec-to-string (cmd)
  "Replace \"shell-command-to-string\" to log to process buffer.

CMD is the command string to run."
  (kubel--log-command "kubectl-command" cmd)
  (with-output-to-string
    (with-current-buffer standard-output
      (shell-command cmd t kubel--output-buffer-name))))

(defvar-local kubel-namespace "default"
  "Current namespace.")

(defvar-local kubel-resource-type "pods"
  "Current resource type.")

(defvar-local kubel-context
  (replace-regexp-in-string
   "\n" "" (kubel--exec-to-string "kubectl config current-context"))
  "Current context.  Tries to smart default.")

(defvar kubel--last-context nil
  "Last used context.")

(defvar kubel--last-namespace nil
  "Last used namespace.")

(defvar-local kubel-resource-filter ""
  "Regex filter for resource view.")

(defvar-local kubel-selectors nil
  "Label selectors for resources.")

(defvar-local kubel-field-selectors ""
  "Field selectors for resources.")

(defvar kubel-namespace-history '()
  "List of previously used namespaces.")

(defvar kubel-selector-history '()
  "List of previously used selectors.")

(defvar-local kubel--can-get-namespace-cached nil)

(defvar kubel--namespace-list-cached nil)

(defvar-local kubel--label-values-cached nil)

(defvar-local kubel--selected-items-set (ht)
  "Hashet containing all the currently selected items.")

(defvar-local kubel--kubernetes-api-resources-list-cached nil)

(defvar-local kubel--all-namespaces-view nil
  "Non-nil if current view is for all namespaces AND has NAMESPACE column.")

(defvar kubel--all-namespaces-entry "*ALL*"
  "Special entry for all namespaces in the namespace list. Must be illegal
from k8s point of view to avoid clashes.")

(defvar-local kubel--ns-name->columns-alist (ht)
  "Hashtable of (ns . name) to columns alist of all items in the view.")

(defvar-local kubel--ns-name->visible (ht)
  "Hashtable of (ns . name) to visible flag all items in the view.")

(defvar kubel--complex-views (ht ("pods" `((table-columns . ("NAME" "READY" "STATUS" "RESTARTS" "CPU(r)" "CPU(l)" "MEM(r)" "MEM(l)" "NODE" "AGE"))
                                           (calls . (((type . get-wide))
                                                     ((type . jsonpath-repeated-columns)
                                                      (spec . "'{range .items[*]}{.metadata.namespace} {.metadata.name}{range .spec.containers[*]} {.resources.requests.cpu} {.resources.requests.memory} {.resources.limits.cpu} {.resources.limits.memory}{end}{\"\\n\"}{end}'")
                                                      (static-columns . ("NAMESPACE" "NAME"))
                                                      (repeated-columns . ("CPUREQ" "MEMREQ" "CPULIM" "MEMLIM"))
                                                      (pre-process . (("CPUREQ" . ,(lambda (acc arg)
                                                                                    (let ((number (kubel--convert-cpu-units-millis arg)))
                                                                                      (+ acc number))))
                                                                      ("MEMREQ" . ,(lambda (acc arg)
                                                                                     (let ((number (kubel--convert-size-units-bytes arg)))
                                                                                       (+ acc number))))
                                                                      ("CPULIM" . ,(lambda (acc arg)
                                                                                    (let ((number (kubel--convert-cpu-units-millis arg)))
                                                                                      (+ acc number))))
                                                                      ("MEMLIM" . ,(lambda (acc arg)
                                                                                     (let ((number (kubel--convert-size-units-bytes arg)))
                                                                                       (+ acc number))))))
                                                      (post-process . (("CPUREQ" . ,(lambda (arg)
                                                                                      (kubel--convert-cpu-units-str arg)))
                                                                       ("MEMREQ" . ,(lambda (arg)
                                                                                      (kubel--convert-size-units-str arg)))
                                                                       ("CPULIM" . ,(lambda (arg)
                                                                                      (kubel--convert-cpu-units-str arg)))
                                                                       ("MEMLIM" . ,(lambda (arg)
                                                                                      (kubel--convert-size-units-str arg))))))


                                                                                                                      ;; FIXME: this won't work with recursive descent
                                                     ;; ((type . jsonpath)
                                                     ;;  (spec . "'{range .items[*]}{.metadata.namespace} {.metadata.name} {..resources.requests.cpu} {..resources.requests.memory}{\"\\n\"}{end}'")
                                                     ;;  (columns . ("NAMESPACE" "NAME" "CPUREQ" "MEMREQ")))
                                                     ((type . top))))
                                           (post-process . (,(lambda (item)
                                                               (let ((cpu-usage-str (ht-get item "CPU(cores)" "-"))
                                                                     (cpu-req-str (ht-get item "CPUREQ" "-")))
                                                                 (ht-set item "CPU(r)" (concat
                                                                                        (kubel--ratio
                                                                                         (kubel--convert-cpu-units-millis cpu-usage-str)
                                                                                         (kubel--convert-cpu-units-millis cpu-req-str))
                                                                                        " ("
                                                                                        cpu-usage-str
                                                                                        "/"
                                                                                        cpu-req-str
                                                                                        ")")))
                                                               (let ((mem-usage-str (ht-get item "MEMORY(bytes)" "-"))
                                                                     (mem-req-str (ht-get item "MEMREQ" "-")))
                                                                 (ht-set item "MEM(r)" (concat
                                                                                        (kubel--ratio
                                                                                         (kubel--convert-size-units-bytes mem-usage-str)
                                                                                         (kubel--convert-size-units-bytes mem-req-str))
                                                                                        " ("
                                                                                        mem-usage-str
                                                                                        "/"
                                                                                        mem-req-str
                                                                                        ")")))
                                                               (let ((cpu-usage-str (ht-get item "CPU(cores)" "-"))
                                                                     (cpu-lim-str (ht-get item "CPULIM" "-")))
                                                                 (ht-set item "CPU(l)" (concat
                                                                                        (kubel--ratio
                                                                                         (kubel--convert-cpu-units-millis cpu-usage-str)
                                                                                         (kubel--convert-cpu-units-millis cpu-lim-str))
                                                                                        " ("
                                                                                        cpu-usage-str
                                                                                        "/"
                                                                                        cpu-lim-str
                                                                                        ")")))
                                                               (let ((mem-usage-str (ht-get item "MEMORY(bytes)" "-"))
                                                                     (mem-lim-str (ht-get item "MEMREQ" "-")))
                                                                 (ht-set item "MEM(l)" (concat
                                                                                        (kubel--ratio
                                                                                         (kubel--convert-size-units-bytes mem-usage-str)
                                                                                         (kubel--convert-size-units-bytes mem-lim-str))
                                                                                        " ("
                                                                                        mem-usage-str
                                                                                        "/"
                                                                                        mem-lim-str
                                                                                        ")"))))))))
                                 ("nodes" `((table-columns . ("NAME" "STATUS" "ROLES" "CPU" "MEM" "INTERNAL-IP" "EXTERNAL-IP" "AGE"))
                                            (calls . (((type . get-wide))
                                                      ((type . custom)
                                                       (spec . "NAME:.metadata.name,CPUALLOC:.status.allocatable.cpu,MEMALLOC:.status.allocatable.memory"))
                                                      ((type . top))))
                                            (post-process . (,(lambda (item)
                                                                (let ((cpu-usage-str (ht-get item "CPU(cores)" ""))
                                                                      (cpu-alloc-str (ht-get item "CPUALLOC" "")))
                                                                  (ht-set item "CPU" (concat
                                                                                      (kubel--convert-cpu-units-str
                                                                                       (kubel--convert-cpu-units-millis
                                                                                        cpu-usage-str))
                                                                                      "/"
                                                                                      (kubel--convert-cpu-units-str
                                                                                       (kubel--convert-cpu-units-millis
                                                                                        cpu-alloc-str))
                                                                                      " ("
                                                                                      (kubel--ratio
                                                                                       (kubel--convert-cpu-units-millis cpu-usage-str)
                                                                                       (kubel--convert-cpu-units-millis cpu-alloc-str))
                                                                                      ")")))
                                                                (let ((mem-usage-str (ht-get item "MEMORY(bytes)" ""))
                                                                      (mem-alloc-str (ht-get item "MEMALLOC" "")))
                                                                  (ht-set item "MEM" (concat
                                                                                      (kubel--convert-size-units-str
                                                                                       (kubel--convert-size-units-bytes
                                                                                        mem-usage-str))
                                                                                      "/"
                                                                                      (kubel--convert-size-units-str
                                                                                       (kubel--convert-size-units-bytes
                                                                                        mem-alloc-str))
                                                                                      " ("
                                                                                      (kubel--ratio
                                                                                       (kubel--convert-size-units-bytes mem-usage-str)
                                                                                       (kubel--convert-size-units-bytes mem-alloc-str))
                                                                                      ")"))))))))
                                 ("events" `((table-columns . ("NAME" "LAST SEEN" "TYPE" "REASON" "OBJECT" "SUBOBJECT" "MESSAGE"))
                                             (calls . (((type . get-wide))
                                                       ((type . custom)
                                                        (spec . "NAMESPACE:.metadata.namespace,NAME:.metadata.name")))))))

  "The structure to define complex resource type views (i.e. consisting
more than one kubectl get call).

The shape of the structure is as follows:

top-level hashtable key is the resource type,
entry points at view alist, which MUST have:

 - table-columns entry, with value of list of displayed columns,
 - calls, with list of calls kubel must make.

It MAY have:

 - post-process entry, with alist of functions shaping the table as the
final step before displaying.

calls is a list of alists. Internal alists must have a type key, which
may be one of the following:

 - get, to perform a naked get
 - get-wide, to perform a get with -o wide
 - custom, to perform a custom-columns call
 - jsonpath, to perform a jsonpath call
 - jsonpath-repeated-columns, to perform a more complex ranged jsonpath
call.

get or get-wide are basic calls and must appear first in the alist.

custom call has one additional key, spec which is the definition of
custom columns as they will appear on the kubectl call. NAMESPACE and
NAME should appear as the first columns, where appropriate. This is
because (NAMESPACE . NAME) cons cell will be used to map different call
results.

jsonpath call has spec and columns keys. spec is the jsonpath for
kubectl call, and columns are names for the values from the call. All
values in jsonpath must be divided by a single whitespace, with
NAMESPACE (if applicable) and NAME appearing first.

jsonpath-repeated-columns has spec, static-columns, repeated-columns,
pre-process and post-process fields. spec is as above, static-columns
are the ones not participating in {range} queries, and repeated-columns
are the ones that do. Try out the pods example to get a better
understanding.

pre-process and post-process are alists of their own, with column names
as keys, and functions of two arguments as values for pre-process, and
of one for post-process. For pre-process, functions will be called with
first argument as an accumulator (integer), and second as a literal
value of a given column (string), for each repeated column. For
post-process, each function will be called once to form the final value
of the column after the call. Post-process function must return a
string.

Global post-process entry (per resource-type) defines any final
transformations that apply to entries before displaying the table. It
contains a single function as a value, that will get a hashtable of each
entry as an argument. You can use this to define new columns, or alter
existing ones.

Any columns starting with \"CPU\" or \"MEM\" will have percentage
propertizing applied.

See also `kubel--make-view-calls'.
")

(defcustom kubel-enable-complex-views t
  "If set, enables complex views for various resource types."
  :type 'boolean
  :group 'kubel)

(defun toggle-kubel-complex-views ()
  (interactive)
  (setq kubel-enable-complex-views (not kubel-enable-complex-views))
  (message "Kubel complex views %s" (if kubel-enable-complex-views "enabled" "disabled")))

(defun kubel--resource-type-global? (resource-type)
  "Utility function to determine if the current resource type is global."
  (ht-get (kubel--get-global-resources-set) resource-type nil))

;; TODO fill this in
(defvar kubel--op->buffer-action
  '((delete . accumulate)
    (apply . accumulate)
    (patch . accumulate)
    (scale . accumulate)
    (logs-follow . pop-comint))
  "Assoc list of operations to what to do with the operation results.
Default is pop. See `kubel--exec'.")

(defun kubel--kubernetes-api-resources-list ()
  "Get list of resources from cache or from fetching the api resource."
  (if (null kubel--kubernetes-api-resources-list-cached)
      (setq kubel--kubernetes-api-resources-list-cached
            (kubel--fetch-api-resource-list))
    kubel--kubernetes-api-resources-list-cached))

(defun kubel--invalidate-context-caches ()
  "Invalidate the context caches."
  (setq kubel--kubernetes-api-resources-list-cached nil)
  (setq kubel--can-get-namespace-cached nil)
  (setq kubel--namespace-list-cached nil)
  (setq kubel--label-values-cached nil)
  (setq kubel--global-resources-set-cached (ht)))

(defvar-local kubel--entrylist-cache nil)

(defvar-local kubel--last-column-sorted nil
  "If not nil, sort by this column after refresh.")

(defvar-local kubel--last-column-sorted-direction nil
  "If t, sorted descending. If nil, ascending.")

(defun kubel-sort-by-column-at-point ()
  (interactive)
  (let* ((colname (get-text-property (point) 'tabulated-list-column-name))
         (colnum (tabulated-list--column-number colname)))
    (if (and (numberp kubel--last-column-sorted) (= colnum kubel--last-column-sorted))
        (setq kubel--last-column-sorted-direction (not kubel--last-column-sorted-direction))
      (setq kubel--last-column-sorted-direction nil))
    (setq kubel--last-column-sorted colnum)
    (tabulated-list-sort colnum)))

(defun kubel-sort-revert ()
  (interactive)
  (setq kubel--last-column-sorted nil)
  (kubel-refresh t))

(defun kubel--parsed-body-to-ns-name-ht (body)
  (let* ((header (car body))
         (entries (cdr body))
         (ns nil)
         (name nil)
         (res (ht))
         (single-entry-ht (ht)))
    (mapc
     (lambda (entry)
       (cl-mapc
        (lambda (key value)
          (cond ((s-equals? "NAMESPACE" key)
                 (setq ns value)
                 (ht-set single-entry-ht key value))
                ((s-equals? "NAME" key)
                 (setq name value)
                 (ht-set single-entry-ht key value))
                ;; FIXME: hack to work around kubel--parse-body behaviour with "top"
                ((s-blank? key))
                (t
                 (ht-set single-entry-ht key value))))

        header
        entry)
       ;; TODO: optimize to not copy ht
       (ht-set res (cons (if (and (not kubel--all-namespaces-view)
                                  (null ns))
                             kubel-namespace ns) name)
               (ht-copy single-entry-ht))
       (ht-clear single-entry-ht))
     entries)
    res))

(defun kubel--merge-hts (main other)
  "Utility function to merge two hashtables without creating a third one.

MAIN is the hashtable to be mutated.
OTHER is the one merged in."
  (dolist (item (ht-items other))
    (let ((key (car item))
          (value (cadr item)))
      (ht-set main key value))))

(defun kubel--merge-second-order-hts (main other)
  "Utility function to merge two second-order hashtables without creating a third one.

MAIN is the hashtable to be mutated.
OTHER is the one merged in."
  (dolist (item (ht-items other))
    (let ((key (car item))
          (value (cadr item)))
      (when (ht-contains? main key)
        (kubel--merge-hts (ht-get main key) value)))))

(comment
 (let ((ht1 (ht (1 (ht ('a 'b)))))
       (ht2 (ht (1 (ht ('c 'd)))
                (2 (ht ('e 'f))))))
   (kubel--merge-second-order-hts ht2 ht1)
   ht2))


(defun kubel--make-view-calls ()
  "A function to make all the calls needed to form the view. Returns a list
properly formatted for future display in tabulated-list-mode.

This function executes kubectl for each call defined in the complex
view, and saves or merges the result into a nested hashtable of (ns .
name)->column->value. It all calls all the pre- and post-process
functions per kubectl call.

At the end, it calls the resource-type post-process functions, and
restructures the list with respect to columns ordering, returning a list
of lists, with the first one being a header, and rest being rows.

The function is very heavy, as it does multiple hashtable operations per
each element of the view, including invisible ones (so keep the
invisible ones to the minimum)."
  (if (or (not kubel-enable-complex-views)
          (not (ht-contains? kubel--complex-views kubel-resource-type)))
      (kubel--parse-body
        (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                       " get " kubel-resource-type (kubel--kubectl-suffix))))
    (let* ((call-spec (ht-get kubel--complex-views kubel-resource-type))
           (table-columns (append (if (and (kubel--all-namespaces?)
                                           (not (kubel--resource-type-global? kubel-resource-type))) '("NAMESPACE"))
                                  (asoc-get call-spec 'table-columns)))
           (post-process-fns (asoc-get call-spec 'post-process))
           (calls (asoc-get call-spec 'calls))
           (res (ht)))
      (dolist (call calls)
        ;; (message "current ht: %s" res)
        (let ((type (asoc-get call 'type)))
          (cond ((eq type 'get)
                 ;; TODO: make kubel--exec more flexible to avoid rebind
                 (let* ((kubel-list-wide nil)
                        (body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                             " get " kubel-resource-type (kubel--kubectl-suffix))))
                        (parsed (kubel--parse-body body))
                        (hashtable (kubel--parsed-body-to-ns-name-ht parsed)))
                   (setq res hashtable)))
                ((eq type 'get-wide)
                 (let* ((kubel-list-wide t)
                        (body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                             " get " kubel-resource-type (kubel--kubectl-suffix))))
                        (parsed (kubel--parse-body body))
                        (hashtable (kubel--parsed-body-to-ns-name-ht parsed)))
                   (setq res hashtable)))
                ;; TODO: instead of top, maybe call to metrics.k8s.io resources?
                ((eq type 'top)
                 (let* ((kubel-list-wide nil)
                        (body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                             " top " kubel-resource-type (kubel--kubectl-suffix))))
                        (parsed (kubel--parse-body body))
                        (hashtable (kubel--parsed-body-to-ns-name-ht parsed)))
                   (dolist (ns-name (ht-keys hashtable))
                     (when (ht-contains? res ns-name)
                       (ht-set res ns-name (ht-merge (ht-get res ns-name) (ht-get hashtable ns-name)))))))
                ((eq type 'custom)
                 (let* ((kubel-list-wide nil)
                        (spec (asoc-get call 'spec))
                        (body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                             " get " kubel-resource-type
                                                             " -o custom-columns=" spec
                                                             (kubel--kubectl-suffix))))
                        (parsed (kubel--parse-body body))
                        (hashtable (kubel--parsed-body-to-ns-name-ht parsed)))
                   (kubel--merge-second-order-hts res hashtable)))
                ((eq type 'jsonpath)
                 (let* ((kubel-list-wide nil)
                        (spec (asoc-get call 'spec))
                        (columns (asoc-get call 'columns))
                        (body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                             " get " kubel-resource-type
                                                             " -o jsonpath=" spec
                                                             (kubel--kubectl-suffix))))
                        (parsed (kubel--parse-jsonpath-body body columns))
                        (hashtable (kubel--parsed-body-to-ns-name-ht parsed)))
                   (kubel--merge-second-order-hts res hashtable)))
                ((eq type 'jsonpath-repeated-columns)
                 (let* ((kubel-list-wide nil)
                        (spec (asoc-get call 'spec))
                        (static-columns (asoc-get call 'static-columns))
                        (repeated-columns (asoc-get call 'repeated-columns))
                        (body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                             " get " kubel-resource-type
                                                             " -o jsonpath=" spec
                                                             (kubel--kubectl-suffix))))
                        (pre-process-alist (asoc-get call 'pre-process))
                        (post-process-alist (asoc-get call 'post-process))
                        (parsed (kubel--parse-jsonpath-repeated-columns-body
                                 body static-columns repeated-columns pre-process-alist post-process-alist))
                        (hashtable (kubel--parsed-body-to-ns-name-ht parsed)))
                   (kubel--merge-second-order-hts res hashtable))))))
      (message "%s" table-columns)
      (append
       (list table-columns)
       (mapcar
        (lambda (entry-ht)
          (dolist (fn post-process-fns)
           (funcall fn entry-ht))
          (mapcar
           (lambda (column) (ht-get entry-ht column))
           table-columns))
        (reverse (ht-values res)))))))

(comment
 (let ((kubel-resource-type "pods")
       (kubel-context "minikube")
       (kubel-namespace "default"))
   (kubel--make-view-calls))

 (let ((kubel-resource-type "pods")
       (kubel-context "minikube")
       (kubel-namespace "*ALL*"))
   (kubel--parse-body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                     " top " kubel-resource-type (kubel--kubectl-suffix)))))
 (let ((kubel-resource-type "pods")
       (kubel-context "minikube")
       (kubel-namespace "default"))
   (kubel--parse-jsonpath-body (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                                              " get " kubel-resource-type
                                                              " -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {..resources.requests.cpu}{\"\\n\"}{end}'"
                                                              (kubel--kubectl-suffix)))
                               '("NAMESPACE" "NAME" "CPUREQ")))
 (let ((kubel-resource-type "pods")
       (kubel-context "minikube")
       (kubel-namespace "default"))
   (kubel--parse-jsonpath-repeated-columns-body
    (kubel--exec-to-string (concat (kubel--kubectl-prefix kubel-namespace)
                                   " get " kubel-resource-type
                                   " -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{range .spec.containers[*]} {.resources.requests.cpu} {.resources.requests.memory} {.resources.limits.cpu} {.resources.limits.memory}{end}{\"\\n\"}{end}'"
                                   (kubel--kubectl-suffix)))
    '("NAMESPACE" "NAME")
    '("CPUREQ" "MEMREQ" "CPULIM" "MEMLIM")
    `(("CPUREQ" . ,(lambda (acc arg)
                           (let ((number (kubel--convert-cpu-units-millis arg)))
                             (+ acc number))))
      ("MEMREQ" . ,(lambda (acc arg)
                     (let ((number (kubel--convert-size-units-bytes arg)))
                       (+ acc number))))
      ("CPULIM" . ,(lambda (acc arg)
                    (let ((number (kubel--convert-cpu-units-millis arg)))
                      (+ acc number))))
      ("MEMLIM" . ,(lambda (acc arg)
                     (let ((number (kubel--convert-size-units-bytes arg)))
                       (+ acc number)))))
    `(("CPUREQ" . ,(lambda (arg)
                           (kubel--convert-cpu-units-str arg)))
      ("MEMREQ" . ,(lambda (arg)
                     (kubel--convert-size-units-str arg)))
      ("CPULIM" . ,(lambda (arg)
                     (kubel--convert-cpu-units-str arg)))
      ("MEMLIM" . ,(lambda (arg)
                     (kubel--convert-size-units-str arg)))))))


(defvar kubel--size-units-alist '(("Ki" . Ki)
                                  ("Mi" . Mi)
                                  ("Gi" . Gi)
                                  ("Ti" . Ti)
                                  ("" . B)))

(defvar kubel--size-unit-multipliers-alist `((Ti . ,(* 1024 1024 1024 1024))
                                             (Gi . ,(* 1024 1024 1024))
                                             (Mi . ,(* 1024 1024))
                                             (Ki . 1024)
                                             (B . 1)))

(defun kubel--appropriate-mult (bytes mults)
  "A function returning an appropriate size multiplier cons cell for given
amount of bytes.

BYTES is the number of bytes
MULTS is an alist of multipliers"

  (if (= bytes 0) (cons 'B 1)
    (let* ((current (car mults))
           (name (car current))
           (mult (cdr current))
           (rest (cdr mults)))
      (if (> bytes mult)
          (cons name mult)
        (kubel--appropriate-mult bytes rest)))))

(defun kubel--convert-size-units-bytes (s)
  "Convert a string representing size to bytes integer.

S is the string."
  (if (or (s-equals? "-" s) (s-blank? s))
      0
    (when (string-match (rx bol (group (one-or-more digit)) (group (? (or "Ki" "Mi" "Gi" "Ti")) eol))
                        s)
      (let* ((num (string-to-number (match-string 1 s)))
             (units (asoc-get kubel--size-units-alist (match-string 2 s)))
             (multiplier (asoc-get kubel--size-unit-multipliers-alist units))
             (bytes (* num multiplier)))
        bytes))))

(defun kubel--convert-size-units-str (bytes)
  "Convert bytes into a string with an appropriate multiplier."
  (if (null bytes)
      ""
    (let* ((appropriate-name-mult (kubel--appropriate-mult bytes kubel--size-unit-multipliers-alist))
           (appropriate-name (car appropriate-name-mult))
           (appropriate-mult (cdr appropriate-name-mult))
           (scaled (/ bytes appropriate-mult)))
      (substring-no-properties (format "%.0f%s" scaled appropriate-name)))))

(defun kubel--convert-cpu-units-millis (s)
  "Convert a string representing CPU usage into millicores.

S is the string."
  (if (or (s-equals? "-" s) (s-blank? s))
      0
    (if (s-suffix? "m" s)
        (string-to-number (s-chop-suffix "m" s))
      (* 1000 (string-to-number s)))))

(defun kubel--convert-cpu-units-str (millis)
  "Convert millis into a CPU usage string.

MILLIS is the amount of millicores."
  (if (null millis)
      ""
    (if (> millis 1000)
        (format "%.1f" (/ millis 1000))
      (concat (number-to-string millis) "m"))))

(defun kubel--ratio (x y)
  "Calculate a usage ratio X/Y in percents, return as a string.

If either is null, or y == 0, return \"N/A\""
  (if (or (null y) (zerop y) (null x))
      "N/A"
    (substring-no-properties (format "%.0f%%" (/ x y 0.01)))))

(defun kubel--populate-list (&optional no-refresh)
  "Return a list with a tabulated list format and \"tabulated-list-entries\".

NO-REFRESH inhibits running kubectl."
  (let*  ((parsed-body (unless no-refresh
                         (kubel--make-view-calls)))
          (entrylist (if no-refresh
                         kubel--entrylist-cache
                       parsed-body)))
    (setq kubel--entrylist-cache entrylist)
    (kubel--populate-view-entries entrylist)
    ;; (when (string-prefix-p "No resources found" body)
    ;;   (message "No resources found"))  ;; TODO exception here
    (let ((list-format (kubel--get-list-format entrylist))
          (list-entries (kubel--get-list-entries)))
      (list list-format list-entries))))

(defun kubel--age-to-secs (age)
  "Convert AGE in format 1d2h3m4s to seconds."
  (let ((rex (rx bol
                 (opt (group (one-or-more digit)) "d")
                 (opt (group (one-or-more digit)) "h")
                 (opt (group (one-or-more digit)) "m")
                 (opt (group (one-or-more digit)) "s")
                 eol)))
    (if (string-match rex age)
        (-sum (--map-indexed
               (* (--if-let (match-string (1+ it-index) age)
                      (string-to-number it)
                    0)
                  it)
               '(86400 3600 60 1)))
      0)))

(defun kubel--make-age-comparator (colnum)
  "Return a function that compares two ages at given column COLNUM."
  (lambda (row1 row2)
    (let ((age1 (elt (cadr row1) colnum))
          (age2 (elt (cadr row2) colnum)))
      (< (kubel--age-to-secs age1)
         (kubel--age-to-secs age2)))))

(defun kubel--make-resource-usage-comparator (colnum)
  "Return a function that compares two resource usages at given column COLNUM."
  (lambda (row1 row2)
    (let* ((usage1 (elt (cadr row1) colnum))
           (usage2 (elt (cadr row2) colnum))
           (parsed1 (kubel--get-percentage usage1))
           (parsed2 (kubel--get-percentage usage2))
           (perc1 (car parsed1))
           (perc2 (car parsed2)))
      (cond ((null perc1)
             t)
            ((null perc2)
             nil)
            (t
             (< perc1
                perc2))))))

;; TODO: add descriptions; make a mechanism to choose between these functions.
(defun kubel--get-count-restarts (s)
  (if (s-equals? "0" s)
      0
    (when (string-match (rx bol (group (one-or-more digit)) (group " (" (* anything) " ago)") eol) s)
      (string-to-number (match-string 1 s)))))

(defun kubel--get-last-restart-age (s)
  ;; if there's age, return that; else return effectively "never" (long in the past)
  (if (string-match (rx bol (group (one-or-more digit)) " (" (group (* anything)) " ago)" eol) s)
      (kubel--age-to-secs (match-string 2 s))
    most-positive-fixnum))

(defun kubel--make-restarts-comparator (colnum)
  "Return a function that compares age of last restarts."
  (lambda (row1 row2)
    (let* ((restarts1 (elt (cadr row1) colnum))
           (restarts2 (elt (cadr row2) colnum))
           (age1 (kubel--get-last-restart-age restarts1))
           (age2 (kubel--get-last-restart-age restarts2)))
      (< age1 age2))))

(defun kubel--column-entry (entrylist)
  "Return a function of colnum to retrieve an entry in a given column for
ENTRYLIST."
  (function
   (lambda (colnum)
     (let* ((name (kubel--column-header entrylist colnum))
            (width (+ 4 (kubel--column-width entrylist colnum)))
            (sort (cond
                   ((or (s-prefix? "CPU" name) (s-prefix? "MEM" name))
                    (kubel--make-resource-usage-comparator colnum))
                   ((member name '("AGE" "DURATION" "LAST SCHEDULE"))
                    (kubel--make-age-comparator colnum))
                   ((member name '("RESTARTS"))
                    (kubel--make-restarts-comparator colnum))
                   (t t))))
       (list name width sort)))))

(defun kubel--get-list-format (entrylist)
  "Get the list format.

ENTRYLIST is the output of the parsed body."
  (defun kubel--get-column-entry (colnum)
    (let ((kubel--get-entry (kubel--column-entry entrylist)))
      (funcall kubel--get-entry colnum)))
  (cl-map 'vector #'kubel--get-column-entry (number-sequence 0 (- (kubel--ncols entrylist) 1))))

;; TODO: is this the correct behaviour? should we instead build intersection between
;; visible and selected items for the operations that work on selections?
(defun kubel--update-selected-items ()
  "Check that all selected items still exist."
  (dolist (ns-name (ht-keys kubel--selected-items-set))
    (unless (and (ht-contains? kubel--ns-name->columns-alist ns-name)
                 (ht-get kubel--ns-name->visible ns-name))
      (ht-remove kubel--selected-items-set ns-name))))

(defun kubel--get-list-entries ()
  "Get the entries.

ENTRYLIST is the output of the parsed body."
  (let ((entries (mapcar (lambda (item)
                          (let ((name (asoc-get item "NAME"))
                                (ns (kubel--ns item)))
                            (list (format "%s/%s" ns name)
                                  (vconcat [] (mapcar #'cdr (kubel--propertize-item (cons ns name) item))))))
                         (reverse (ht-values kubel--ns-name->columns-alist)))))
    (cl-remove-if
     (lambda (entry)
       (kubel--empty? (cadr entry)))
     entries)))

(defun kubel--parse-body (body)
  "Parse the body of kubectl get resource call into a list.

BODY is the raw output of kubectl get resource."
  (let* ((lines (or (nbutlast (split-string body "\n")) '("")))
         (header (car lines))
         ;; Cronjobs have a "LAST SCHEDULE" column, so need to split on 2+ whitespace chars.
         (starts (cl-loop for start = 0 then (match-end 0)
                          while (string-match (rx (>= 2 whitespace)) header start)
                          collect (match-end 0)))
         (position (-zip-with 'cons (cons 0 starts) (append starts '("end"))))
         (parse-line (lambda (line)
                       (mapcar (lambda (pos)
                                 (kubel--extract-value line (car pos) (cdr pos)))
                               position))))
    (mapcar parse-line lines)))

(defun kubel--parse-jsonpath-body (body columns)
  "Parse the body of kubectl get resource call into a list.

BODY is the raw output of kubectl get resource."
  (let* ((lines (or (nbutlast (split-string body "\n")) '(""))))
    (append
     (list columns)
     (mapcar
      (lambda (line)
        (split-string line " "))
      lines))))

(defun kubel--parse-jsonpath-repeated-columns-body (body static-columns repeated-columns pre-process-alist post-process-alist)
  "Parse the body of kubectl get resource call into a list.

BODY is the raw output of kubectl get resource."
  (let* ((lines (or (nbutlast (split-string body "\n")) '("")))
         (longest-line-columns 0)
         (contents (mapcar
                    (lambda (line)
                      (let ((splat (split-string line " ")))
                        (when (< longest-line-columns (length splat))
                            (setq longest-line-columns (length splat)))
                        splat))
                    lines))
         (number-of-repeats (truncate (/ (- longest-line-columns (length static-columns))
                                         (length repeated-columns))))
         (dynamic-columns '())
         (columns static-columns))
    ;; FIXME: this is likely ineffective, refactor
    (dotimes (i number-of-repeats)
      (setq dynamic-columns (append dynamic-columns repeated-columns)))
    (let* ((all-columns (append columns repeated-columns))
           (dynamic-columns-vector (vconcat dynamic-columns))
           (aggregated-contents (mapcar
                                 (lambda (line-list)
                                   (let ((repeated-fields (ht)) ;; aggregate every repeated field in ht
                                         (static-content (take (length static-columns) line-list))
                                         (repeated-content (drop (length static-columns) line-list))
                                         (dynamic-columns-length (length dynamic-columns-vector)))
                                     (dotimes (i (length repeated-content))
                                       (let ((current-repeated-field (aref dynamic-columns-vector (mod i dynamic-columns-length))))
                                         (ht-set repeated-fields current-repeated-field
                                                 (funcall (asoc-get pre-process-alist current-repeated-field)
                                                          (ht-get repeated-fields current-repeated-field 0)
                                                          (nth i repeated-content)))))
                                     ;; read contents back from hashtable
                                     (append static-content (mapcar
                                                             (lambda (column)
                                                               (funcall (asoc-get post-process-alist column)
                                                                        (ht-get repeated-fields column)))
                                                             repeated-columns))))
                                 contents)))
      (append
       (list all-columns)
       aggregated-contents))))

(comment
 (append '(1 2 3) '(4 5)))


(defun kubel--extract-value (line min max)
  "Extract value from LINE between MIN and MAX.
If it's just white space, return -, else trim space.
If MAX is the end of the line, dynamically adjust."
  (let* ((maxx (if (equal max "end") (length line) max))
         (str (substring-no-properties line min maxx)))
    (if (string-match "^ +$" str)
        "-"
      (string-trim str))))

(defun kubel--ncols (entrylist)
  "Return the number of columns in ENTRYLIST."
  (length (car entrylist)))

(defun kubel--nrows (entrylist)
  "Return the nubmer of rows in ENTRYLIST."
  (length entrylist))

(defun kubel--column-header (entrylist colnum)
  "Return the header for a specific COLNUM in ENTRYLIST."
  (nth colnum (car entrylist)))

(defun kubel--column-width (entrylist colnum)
  "Return the width of a specific COLNUM in ENTRYLIST."
  (seq-max (mapcar (lambda (x) (length (nth colnum x) )) entrylist)))

(defun kubel--buffer-name-from-parameters (context namespace resource)
  "Return a preconfigured kubel buffer name."
  (concat (format "*kubel:%s:%s:%s*" context namespace resource)))

(defun kubel--buffer-name ()
  "Return kubel buffer name."
  (concat
   (kubel--buffer-name-from-parameters kubel-context kubel-namespace kubel-resource-type)
   ;; TODO: maybe extract this into a function
   (unless (and (kubel--empty? kubel-selectors) (s-blank? kubel-field-selectors))
     (concat
      " ("
      (mapconcat #'identity (append kubel-selectors
                                    (unless (s-blank? kubel-field-selectors)
                                      (list kubel-field-selectors)))
                 " ")
      ")"))))


;; (defun kubel--get-percentage (s)
;;   (when (string-match (rx bol (group (* anything) "(")  (group (one-or-more digit)) (group "%)") eol) s)
;;     (list
;;      (match-string 1 s)
;;      (string-to-number (match-string 2 s))
;;      (match-string 3 s))))

(defun kubel--get-percentage (s)
  (when (string-match (rx bol (group (one-or-more digit)) (group "% (" (* anything) ")") eol) s)
    (list
     (string-to-number (match-string 1 s))
     (match-string 2 s))))

(comment
 (kubel--get-percentage "0% (-/2.0)"))

(defun kubel--items-selected? ()
  "Return non-nil if there are items selected."
  (not (ht-empty? kubel--selected-items-set)))

(defun kubel--propertize-item (ns-name item)
  "Return the propertized item fields.

ITEM is the item hash-table."
  (let ((item-propertized (asoc-make))
        (name (cdr ns-name))
        (matched? nil)
        ;; always search case-insensitively
        (case-fold-search t))
    (asoc-map
     (lambda (key value)
       (let ((match (or (equal kubel-resource-filter "") (string-match-p kubel-resource-filter value))))
         (if match (setq matched? t))
         (cond
          ((string-equal key "STATUS")
           (if (and (not match) (not kubel-filter-hides))
               (asoc-put! item-propertized key (propertize value 'face 'shadow))
             (let ((status-face (cdr (assoc value kubel-status-faces))))
              (asoc-put! item-propertized key (propertize value 'face status-face)))))
          ((string-equal key "NAME")
           (if (ht-contains? kubel--selected-items-set ns-name)
               ;; if selected
               (asoc-put! item-propertized key (propertize (concat "*" name) 'face 'dired-marked))
             (if (and (not match) (not kubel-filter-hides))
                 (asoc-put! item-propertized key (propertize value 'face 'shadow))
               (asoc-put! item-propertized key value))))
          ((or (s-prefix? "CPU" key) (s-prefix? "MEM" key))
           (if (and (not match) (not kubel-filter-hides))
               (asoc-put! item-propertized key (propertize value 'face 'shadow))
             (let* ((parsed (kubel--get-percentage value))
                    (percentage (car parsed))
                    (rest (cadr parsed)))
               (cond ((null percentage) ; no match
                      (asoc-put! item-propertized key value))
                     ((>= percentage kubel-percentage-critical-threshold)
                      (asoc-put! item-propertized key
                                 (concat
                                  (propertize (number-to-string percentage) 'face 'kubel-percentage-critical-face)
                                  rest)))
                     ((>= percentage kubel-percentage-warning-threshold)
                      (asoc-put! item-propertized key
                                 (concat
                                  (propertize (number-to-string percentage) 'face 'kubel-percentage-warning-face)
                                  rest)))
                     (t (asoc-put! item-propertized key value))))))
          ((and (not match) (not kubel-filter-hides))
           (asoc-put! item-propertized key (propertize value 'face 'shadow)))
          (t (asoc-put! item-propertized key value)))))
     item)
    (if (and kubel-filter-hides (not matched?))
        (progn
          (ht-set kubel--ns-name->visible ns-name nil)
          nil)
      (ht-set kubel--ns-name->visible ns-name t)
      (reverse item-propertized))))

(defun kubel--pop-to-buffer (name)
  "Utility function to pop to buffer or create it.

NAME is the buffer name."
  (unless (get-buffer name)
    (get-buffer-create name))
  (pop-to-buffer-same-window name))

;; TODO: left it as a function call for now but maybe get rid of it later
(defun kubel--process-error-buffer ()
  "Return the error buffer name for the PROCESS-NAME."
  kubel--output-buffer-name)

(defun kubel--sentinel (callback)
  "Sentinel function used by KUBEL--EXEC.

CALLBACK is called when process completes successfully.
"
  (lambda (process event)
    (let ((process-name (process-name process))
          (exit-status (process-exit-status process)))
      (kubel--append-to-process-buffer (format "[%s]\nexit-code: %s" process-name exit-status))
      (if (eq 0 exit-status)
          (when callback (funcall callback))
        (let ((err (with-current-buffer (kubel--process-error-buffer)
                     (buffer-string))))
          (kubel--append-to-process-buffer (format "error: %s" err))
          (error (format "Kubel process %s error: %s" process-name err)))))))

(defun kubel--exec (process-name ns op-type args &optional readonly callback)
  "Utility function to run commands in the proper context and namespace.

PROCESS-NAME is an identifier for the process.  Default to \"kubel-command\".
NS is namespace in which the operation should be performed. nil means no namespace.
OP-TYPE is a type of operation being performed.
ARGS is a list of arguments.
CALLBACK is a function that will be executed when the command completes.
READONLY If true buffer will be in readonly mode(view-mode)."
  (when (equal process-name "")
    (setq process-name "kubel-command"))

  (let* ((buffer-action (if (asoc-contains-key? kubel--op->buffer-action op-type)
                            (asoc-get kubel--op->buffer-action op-type)
                          'pop))
         (buffer-name (cond ((eq buffer-action 'accumulate)
                             kubel--output-buffer-name)
                            (t
                             (format "*kubel-resource:%s:%s:%s*" kubel-context ns (string-join args "_")))))
         (error-buffer (kubel--process-error-buffer))
         (cmd (append (list kubel-kubectl) (kubel--get-context-kubectl-arg) (kubel--get-ns-kubectl-arg ns) args)))
    (when (and (get-buffer buffer-name)
               (not (eq buffer-action 'accumulate)))
      (kill-buffer buffer-name))

    (kubel--log-command process-name cmd)
    (make-process :name process-name
                  :buffer buffer-name
                  :sentinel (kubel--sentinel callback)
                  :file-handler t
                  ;; :stderr (get-buffer-create error-buffer)
                  :stderr nil
                  :command cmd)
    (cond ((eq buffer-action 'pop)
           (pop-to-buffer buffer-name))
          ((eq buffer-action 'pop-comint)
           (pop-to-buffer buffer-name)
           (with-current-buffer buffer-name
             (comint-mode)))
          ((eq buffer-action 'accumulate)
           ;; TODO: this is incorrect, but we'll figure it out
           (display-buffer buffer-name
                           '((display-buffer-reuse-window)
                             (inhibit-same-window . t))
                           t))
          (t (pop-to-buffer buffer-name)))
    (if readonly
        (with-current-buffer buffer-name
          (view-mode)))))

(defun kubel--get-ns-under-cursor ()
  "Utility function to get the namespace of the resource under the cursor."
  (cond
   ((kubel--resource-type-global? kubel-resource-type) nil)
   (kubel--all-namespaces-view (aref (tabulated-list-get-entry) 0))
   (t kubel-namespace)))

(defun kubel--empty? (seq)
  (zerop (length seq)))

(defun kubel--get-name-under-cursor ()
  "Utility function to get the name of the resource under the cursor.
Strip the `*` prefix if the resource is selected"
  (if (kubel--empty? (tabulated-list-get-entry))
      (error "No item selected")
    (string-remove-suffix " (default)" ;; see https://github.com/abrochard/kubel/issues/106
                          (replace-regexp-in-string
                           "^\*" "" (aref (tabulated-list-get-entry)
                                          (if kubel--all-namespaces-view 1 0))))))

(defun kubel--get-ns-name-under-cursor ()
  "Utility function to get the resource under the cursor."
  (let ((name (kubel--get-name-under-cursor))
        (ns (kubel--get-ns-under-cursor)))
    (cons ns name)))

(defun kubel--all-namespaces? ()
  "Utility function to return if currently in special all-namespaces namespace."
  (equal kubel-namespace kubel--all-namespaces-entry))

(defun kubel--get-context-kubectl-arg ()
  "Utility function to return the proper context argument."
  (append
   (unless (equal kubel-context "")
     (list "--context" kubel-context))))

(defun kubel--get-ns-kubectl-arg (ns)
  "Utility function to return the proper namespace arguments."
  (append
   (unless (or (equal ns kubel--all-namespaces-entry)
               ;; ns is nil for global (i.e. non-namespaced) objects
               (null ns)
               ;; FIXME: is ns ever ""?
               (equal ns ""))
     (list "-n" ns))))

(defun kubel--get-selectors ()
  "Utility function to return current label selector."
  (unless (kubel--empty? kubel-selectors)
    (let ((result '()))
      (reverse
       (dolist (selector kubel-selectors result)
         (push "--selector" result)
         (push selector result))))))

(defun kubel--kubectl-prefix (ns)
  "Utility function to prefix the kubectl command with proper context and
namespace."
  (mapconcat 'identity (append (list kubel-kubectl) (kubel--get-context-kubectl-arg) (kubel--get-ns-kubectl-arg ns) (kubel--get-selectors)) " "))

;; TODO merge these?
(defun kubel--kubectl-suffix ()
  "Utility function to suffix the kubectl get command with flags."
  (mapconcat 'identity (append '(" ")
                               (if (kubel--all-namespaces?) (list "--all-namespaces"))
                               (if kubel-list-wide (list "-o wide"))
                               (if (not (s-blank? kubel-field-selectors)) (list "--field-selector" kubel-field-selectors)))
             " "))

(comment
 (let ((kubel-field-selectors "foo==bar"))
   (kubel--kubectl-suffix)))

(defun kubel--kubectl-suffix-all-namespaces ()
  "Utility function to suffix the kubectl get command with all namespaces flag."
  (if (kubel--all-namespaces?)
      " --all-namespaces"
    " "))

(defun kubel--kubectl-suffix-all-namespaces-suffix-by-ns (ns)
  (if (equal ns kubel--all-namespaces-entry)
      " --all-namespaces"
    ""))

(defun kubel--get-containers (ns pod-name &optional type)
  "List the containers in a pod.

POD-NAME is the name of the pod.
TYPE is containers or initContainers."
  (unless type (setq type "containers"))
  (split-string
   (kubel--exec-to-string
    (format "%s get pod %s -o jsonpath='{.spec.%s[*].name}'" (kubel--kubectl-prefix ns) pod-name type)) " "))

(defun kubel--get-pod-labels (ns)
  "List labels of pods in a current namespace."
  (let* ((raw-labels
          (split-string
           (replace-regexp-in-string
            (regexp-quote ":") "="
            (replace-regexp-in-string
             "map\\[\\(.+?\\)\\]" "\\1"
             (kubel--exec-to-string
              (format "%s get pod -o jsonpath='{.items[*].metadata.labels}' %s"
                      (kubel--kubectl-prefix ns)
                      (kubel--kubectl-suffix-all-namespaces-suffix-by-ns ns)))))))
         (splitted (mapcan (lambda (s) (split-string s ","))
                           raw-labels))
         (cleaned (mapcar (lambda (s) (replace-regexp-in-string "[{|\"|}]" "" s)) splitted))
         (unique (-distinct cleaned)))
    unique))

(defun kubel--select-resource (name)
  "Prompt user to select an instance out of a list of resources.

NAME is the string name of the resource."
  (let ((cmd
         (if (kubel--all-namespaces?)
             (format "%s get %s -o=jsonpath='{range .items[*]}{.metadata.namespace}{\"/\"}{.metadata.name}{\" \"}{end}' %s"
                     (kubel--kubectl-prefix nil) name (kubel--kubectl-suffix-all-namespaces))
           (format "%s get %s -o=jsonpath='{.items[*].metadata.name}'"
                   (kubel--kubectl-prefix kubel-namespace) name))))
    (kubel--ns/name-to-ns-name
     (completing-read (concat (s-upper-camel-case name) ": ")
                      (split-string (kubel--exec-to-string cmd) " ")))))

(defun kubel--ns/name-to-ns-name (ns/name)
  "Utility function to parse selected ns/name into (ns . name) cons cell.

NS/NAME is the string representing the object name, of the format
NAMESPACE/NAME."
  (if (kubel--all-namespaces?)
      (let ((parts (split-string ns/name "/")))
        (cons (car parts) (cadr parts)))
    (cons kubel-namespace ns/name)))

(defun kubel--describe-object (resource-type &optional describe)
  "Describe a specific resource.

RESOURCE-TYPE is the string name of the resource type to decribe.
DESCRIBE is boolean to describe instead of get resource details"
  (let* ((ns-name (kubel--select-resource resource-type))
         (ns (car ns-name))
         (name (cdr ns-name))
         (process-name (format "kubel - %s - %s/%s" resource-type ns name))
         (callback (lambda ()
                     (set-buffer-modified-p nil)
                     (goto-char (point-min)))))
    (if describe
        (kubel--exec process-name ns 'describe (list "describe" resource-type name) nil callback)
      (kubel--exec process-name ns 'get (list "get" resource-type "-o" kubel-output name) nil callback))
    (when (string-equal kubel-output "yaml")
      (kubel-yaml-editing-mode))))

(defun kubel--show-rollout-revision (type ns name)
  "Show a specific revision of a certain resource.

TYPE is the resource type.
NAME is the resource name."
  (message "resource: %s/%s" ns name)
  (let* ((typename (format "%s/%s" type name))
         (revision (car (split-string (kubel--select-rollout typename ns))))
         (process-name (format "kubel - rollout - %s - %s" typename revision))
         (callback (lambda () (goto-char (point-min)))))
    (kubel--exec process-name ns 'rollout-history
                 (list "rollout" "history" typename (format "--revision=%s" revision)) nil callback)))

;; TODO: fix this
(defun kubel--list-rollout (typename ns)
  "Return a list of revisions with format '%number   %cause'.

TYPENAME is the resource type/name."

  (let ((cmd (format "%s rollout history %s" (kubel--kubectl-prefix ns) typename)))
    (nthcdr 2 (split-string (kubel--exec-to-string cmd) "\n" t))))

(defun kubel--select-rollout (typename ns)
  "Select a rollout version.

TYPENAME is the resource type/name."
  (let ((prompt (format "Select a rollout of %s: " typename))
        (rollouts (kubel--list-rollout typename ns)))
    (completing-read prompt rollouts)))

(defun kubel--pod-view? ()
  "Return non-nil if this is the pod view."
  (equal (capitalize kubel-resource-type) "Pods"))

(defun kubel--node-view? ()
  "Return non-nil if this is the pod view."
  (equal (capitalize kubel-resource-type) "Nodes"))

(defun kubel--deployment-view? ()
  "Return non-nil if this is a deployment view."
  (-contains? '("Deployments" "deployments" "deployments.apps") kubel-resource-type))

;; TODO: generalize this somehow?
(defun kubel--is-scalable ()
  "Return non-nil if the resource can be scaled."
  (or
   (kubel--deployment-view?)
   (-contains? '("ReplicaSets" "replicasets" "replicasets.apps") kubel-resource-type)
   (-contains? '("StatefulSets" "statefulsets" "statefulsets.apps") kubel-resource-type)))

(defun kubel-kill-buffer ()
  "Kill the current buffer."
  (interactive)
  (when (or (not (buffer-modified-p))
            (not kubel-kill-buffer-query)
            (yes-or-no-p "Resource modified; kill anyway? "))
    (kill-buffer (current-buffer))))

(defvar kubel-yaml-editing-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'kubel-apply)
    (define-key map (kbd "C-c C-k") #'kubel-kill-buffer)
    map)
  "Keymap used in `kubel-yaml-editing-mode' buffers.")

(defvar kubel-json-editing-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'kubel-apply)
    (define-key map (kbd "C-c C-k") #'kubel-kill-buffer)
    map)
  "Keymap used in `kubel-json-editing-mode' buffers.")

;; interactive
;;;###autoload
(define-derived-mode kubel-yaml-editing-mode yaml-mode "kubel/e"
  "Kubel Yaml editing mode.

Allows simple apply of the changes made.

\\{kubel-yaml-editing-mode-map}")

(define-derived-mode kubel-json-editing-mode json-mode "kubel/e"
  "Kubel JSON editing mode.

Allows simple apply of the changes made.

\\{kubel-json-editing-mode-map}")

(defun kubel--act-on-file (operation &optional no-prompt)
  "Utility function to abstract kubectl operations on files.

OPERATION is a string, a kubectl verb (apply, delete, etc)"
  (setq dir-prefix (or
                    (when (tramp-tramp-file-p default-directory)
                      (with-parsed-tramp-file-name default-directory nil
                        (format "/%s%s:%s:" (or hop "") method (if user (concat user "@" host) host))))
                    ""))

  (let* ((filename-without-tramp-prefix (format "/tmp/kubel/%s-%s.%s"
                                                (replace-regexp-in-string "/" "_"
                                                                          (replace-regexp-in-string "\*\\| " "" (buffer-name)))
                                                (floor (float-time))
                                                (cond ((eq major-mode 'kubel-yaml-editing-mode) "yaml")
                                                      ((eq major-mode 'kubel-json-editing-mode) "json"))))
         (filename (format "%s%s" dir-prefix filename-without-tramp-prefix)))
    (when (or no-prompt (y-or-n-p (concat operation "? ")))
      (unless  (file-exists-p (format "%s/tmp/kubel" dir-prefix))
        (make-directory (format "%s/tmp/kubel" dir-prefix) t))
      (write-region (point-min) (point-max) filename)
      (kubel--exec (format "kubectl - %s - %s" operation filename)
                   (if (kubel--all-namespaces?) nil kubel-namespace)
                   'apply (list operation "-f" filename-without-tramp-prefix)
                   nil (lambda () (message "Executed %s on %s" operation filename))))))


(defun kubel-apply (&optional no-prompt)
  "Save the current buffer to a temp file and try to kubectl apply it."
  (interactive "P")
  (kubel--act-on-file "apply" no-prompt))

(defun kubel--delete ()
  "Save the current buffer to a temp file and try to kubectl delete it."
  (kubel--act-on-file "delete" t))

(defun kubel-get-object-details (&optional describe)
  "Get the details of the object under the cursor.

 DESCRIBE is the optional param to describe instead of get."
  (interactive "P")
  (let* ((cell (kubel--get-ns-name-under-cursor))
         (ns (car cell))
         (name (cdr cell))
         (ctx kubel-context)
         (res kubel-resource-type)
         (process-name (format "kubel - %s - %s" kubel-resource-type name))
         (callback (lambda ()
                     (set-buffer-modified-p nil)
                     (goto-char (point-min)))))
    (if describe
        (kubel--exec process-name ns 'describe (list "describe" kubel-resource-type name) nil callback)
      (kubel--exec process-name ns 'get (list "get" kubel-resource-type name "-o" kubel-output) nil callback))
    (when (or (string-equal kubel-output "yaml")
              (string-equal kubel-output "json")
              (transient-args 'kubel-describe-popup))
      (unless describe
        (cond ((string-equal kubel-output "yaml")
               (kubel-yaml-editing-mode))
              ((string-equal kubel-output "json")
               (kubel-json-editing-mode))))
      (setq kubel-context ctx)
      (setq kubel-namespace ns)
      (setq kubel-resource-type res))))

(defun kubel--default-tail-arg (args)
  "Ugly function to make sure that there is at least the default tail.

ARGS is the arg list from transient."
  (if (car (remove nil (mapcar (lambda (x)
                                 (string-prefix-p "--tail=" x)) args)))
      args
    (append args (list (concat "--tail=" (format "%s" kubel-log-tail-n))))))

(defun kubel--max-requests-arg (args)
  "Function to emit --max-log-requests argument if following logs.

ARGS is the arguments list from transient."
  ;; FIXME: magic argument
  (when (kubel--follow-logs-mode? args)
    (list (format "--max-log-requests=%s" kubel-log-max-log-requests))))

(defun kubel--follow-logs-mode? (args)
  (member "-f" args))

;; TODO: rename from get-pod-logs to get-logs
;; if in pod view, get pod under cursor / selected items
;; if in deployment/rs/whatever else view, use kubectl logs deployments/blah form
;;   if something is selected, refuse to work
(defun kubel-get-pod-logs (&optional args type)
  "Get the last N logs of the pod under the cursor.

ARGS is the arguments list from transient.
TYPE is containers or initContainers."
  (interactive
   (list (transient-args 'kubel-log-popup)))
  (dolist (pod (if (kubel--pod-view?)
                   (if (kubel--items-selected?)
                       (ht-keys kubel--selected-items-set)
                     (list (kubel--get-ns-name-under-cursor)))
                 (list (kubel--select-resource "Pods"))))
    (let* ((ns (car pod))
           (name (cdr pod))
           (type (or type "containers"))
           (containers (kubel--get-containers ns name type))
           (container (if (equal (length containers) 1)
                          (car containers)
                        (completing-read "Select container: " containers)))
           (process-name (format "kubel - logs - %s/%s - %s" ns name container)))
      (kubel--exec process-name ns (if (kubel--follow-logs-mode? args) 'logs-follow 'logs)
                   (append '("logs") (kubel--default-tail-arg args) (list name container)) t nil))))

(defun kubel-get-pod-logs--initContainer (&optional args)
  "Get the last N logs of the pod under the cursor.

ARGS is the arguments list from transient."
  (interactive
   (list (transient-args 'kubel-log-popup)))
  (kubel-get-pod-logs args "initContainers"))

;; this command doesn't make sense in the all-namespaces context
(defun kubel-get-logs-by-labels (&optional args)
  "Get the last N logs of the pods by labels.
ARGS is the arguments list from transient."
  (interactive
   (list (transient-args 'kubel-log-popup)))
  (kubel--max-requests-arg args)
  (let* ((ns-name (kubel--get-ns-name-under-cursor))
         (ns (car ns-name))
         (labels (kubel--get-pod-labels ns))
         (label (completing-read "Select label: " labels))
         (process-name (format "kubel - logs - %s" label)))
    (kubel--exec process-name ns (if (kubel--follow-logs-mode? args) 'logs-follow 'logs)
                 (append '("logs") (kubel--default-tail-arg args) (kubel--max-requests-arg args) '("-l") (list label)) t nil)))

(defun kubel-copy-resource-name ()
  "Copy the name of the pod under the cursor."
  (interactive)
  (kill-new (kubel--get-name-under-cursor))
  (message "Resource name copied to kill-ring"))

(defun kubel-copy-log-command ()
  "Copy the streaming log command of the pod under the cursor."
  (interactive)
  (kill-new
   (let* ((cell (if (kubel--pod-view?)
                    (kubel--get-ns-name-under-cursor)
                  (kubel--select-resource "Pods")))
          (ns (car cell))
          (name (cdr cell)))
     (format "%s logs -f --tail=%s %s"
             (kubel--kubectl-prefix ns)
             kubel-log-tail-n
             name)))
  (message "Log command copied to kill-ring"))

(defun kubel-copy-command-prefix ()
  "Copy the kubectl command prefix."
  (interactive)
  (kill-new (kubel--kubectl-prefix kubel-namespace))
  (message "Command prefix copied to kill-ring"))

(defun kubel-copy-last-command ()
  "Copy the last kubectl command ran."
  (interactive)
  (kill-new kubel--last-command)
  (message (concat "Last command copied: " kubel--last-command)))

(defun kubel-set-kubectl-config-file (configfile)
  "Set the path to the kubectl CONFIGFILE."
  (interactive "f")
  (let ((configfile (or configfile "~/.kube/config")))
    (if (file-exists-p (expand-file-name configfile))
        (setenv "KUBECONFIG" (expand-file-name configfile))
      (error "Kubectl config file '%s' does not exist!" configfile))))

(defun kubel--can-get-namespace ()
  "Determine if permissions allow for `kubectl get namespace` in current context."
  (cond ((eq kubel-use-namespace-list 'on) t)
        ((eq kubel-use-namespace-list 'auto)
         (progn
           (unless kubel--can-get-namespace-cached
             (setq kubel--can-get-namespace-cached
                   (string-match-p "yes\n"
                                   (kubel--exec-to-string
                                    (format "%s --context %s auth can-i list namespaces" kubel-kubectl kubel-context))))))
         kubel--can-get-namespace-cached)))

(defun kubel--get-namespace ()
  "Get namespaces for current context, try to recover from cache first."
  (unless kubel--namespace-list-cached
    (setq kubel--namespace-list-cached
          (append
           (list kubel--all-namespaces-entry)
           (split-string (kubel--exec-to-string
                          (format "%s --context %s get namespace -o jsonpath='{.items[*].metadata.name}'" kubel-kubectl kubel-context)) " "))))
  kubel--namespace-list-cached)

(defun kubel--list-namespace ()
  "List namespace, either from history, or dynamically if possible."
  (if (kubel--can-get-namespace)
      (kubel--get-namespace)
    kubel-namespace-history))

(defun kubel--add-namespace-to-history (namespace)
  "Add NAMESPACE to history if it isn't there already."
  (unless (member namespace kubel-namespace-history)
    (push namespace kubel-namespace-history)))

(defun kubel-set-namespace (&optional refresh)
  "Set the namespace.
If called with a prefix argument REFRESH, refreshes
the context caches, including the cached resource list."
  (interactive "P")
  (when refresh (kubel--invalidate-context-caches))
  (let* ((namespace (completing-read "Namespace: "
                                     (kubel--list-namespace)
                                     nil nil nil nil "default"))
         (kubel--buffer (get-buffer (kubel--buffer-name)))
         (last-default-directory (when kubel--buffer
                                   (with-current-buffer kubel--buffer default-directory))))
    (with-current-buffer (clone-buffer)
      (setq kubel-namespace namespace)
      (kubel--add-namespace-to-history namespace)
      (switch-to-buffer (current-buffer))
      (kubel-refresh nil last-default-directory))))

(defun kubel-set-context ()
  "Set the context."
  (interactive)
  (let* ((kubel--buffer (get-buffer (kubel--buffer-name)))
         (last-default-directory (when kubel--buffer (with-current-buffer kubel--buffer default-directory))))
    (with-current-buffer (clone-buffer)
      (setq kubel-context
            (completing-read
             "Select context: "
             (split-string (kubel--exec-to-string (format "%s config view -o jsonpath='{.contexts[*].name}'" kubel-kubectl)) " ")))
      (kubel--invalidate-context-caches)
      (setq kubel-namespace "default")
      (switch-to-buffer (current-buffer))
      (kubel-refresh nil last-default-directory))))

(defun kubel--add-selector-to-history (selectors)
  "Add SELECTOR to history if it isn't there already."
  (dolist (selector selectors kubel-selector-history)
    (unless (member selector kubel-selector-history)
      (push selector kubel-selector-history))))

(defun kubel--get-all-selectors ()
  "Get all selectors."
  (unless kubel--label-values-cached
    (let ((labels (kubel--get-pod-labels kubel-namespace)))
      (setq kubel--label-values-cached labels)))
  kubel--label-values-cached)

(defvar kubel--selector-finish-choice "*FINISH*")

(defun kubel--list-selectors ()
  "List selector expressions from history."
  (delete-dups
   (append (list kubel--selector-finish-choice)
           (kubel--get-all-selectors)
           kubel-selector-history)))

(defun kubel-set-label-selector ()
  "Set the selector."
  (interactive)
  (with-current-buffer (clone-buffer)
    (setq kubel-selectors '())
    (let ((selector nil))
      (while (not (string-equal selector kubel--selector-finish-choice))
        (setq selector (completing-read
                        (format "Selector (current: %s): "
                                (if (kubel--empty? kubel-selectors)
                                    "none"
                                  (mapconcat #'identity kubel-selectors " ")))
                        (kubel--list-selectors)))
        (unless (or (equal selector kubel--selector-finish-choice)
                    (member selector kubel-selectors))
          (push selector kubel-selectors))))
    ;; TODO: fix history
    (kubel--add-selector-to-history kubel-selectors)
    ;; Update pod list according to the label selector
    (switch-to-buffer (current-buffer))
    (setq kubel--no-reset-sort-column t)
    (kubel-refresh)))

(defun kubel-set-field-selector ()
  "Set the field selector."
  (interactive)
  (with-current-buffer (clone-buffer)
    (setq kubel-field-selectors (read-string "Field selector(s): " kubel-field-selectors))
    (switch-to-buffer (current-buffer))
    (kubel-refresh)))

(defun kubel--fetch-api-resource-list ()
  "Fetch the API resource list."
  (split-string (kubel--exec-to-string
                 (format "%s --context %s api-resources -o name --no-headers=true" kubel-kubectl kubel-context)) "\n" t))

(defun kubel-set-resource (&optional refresh)
  "Set the resource.
If called with a prefix argument REFRESH, refreshes
the context caches, including the cached resource list."
  (interactive "P")
  (when refresh (kubel--invalidate-context-caches))
  (let* ((current-buffer-name (kubel--buffer-name))
         (resource-list (kubel--kubernetes-api-resources-list))
         (kubel--buffer (get-buffer current-buffer-name))
         (last-default-directory (when kubel--buffer (with-current-buffer kubel--buffer default-directory))))
    (with-current-buffer (clone-buffer)
      (setq kubel-resource-type
            (completing-read "Select resource: " resource-list))
      (switch-to-buffer (current-buffer))
      (kubel-refresh nil last-default-directory))))

(defun kubel-set-output-format ()
  "Set output format of kubectl."
  (interactive)
  (setq kubel-output
        (completing-read
         "Set output format: "
         '("yaml" "json" "wide" "custom-columns="))))

(defun kubel-port-forward-pod (p)
  "Port forward a pod to your local machine.

P can be a single number or a localhost:container port pair."
  (interactive "sPort: ")
  (let* ((port (if (string-match-p ":" p) p (format "%s:%s" p p)))
         (cell (if (kubel--pod-view?)
                   (kubel--get-ns-name-under-cursor)
                 (kubel--select-resource "Pods")))
         (ns (car cell))
         (name (cdr cell))
         (process-name (format "kubel - port-forward - %s:%s" name port)))
    (kubel--exec process-name ns 'port-forward (list "port-forward" name port))))

(defun kubel-setup-tramp (ns)
  "Setup a kubectl TRAMP."
  (setq tramp-methods (delete (assoc "kubectl" tramp-methods) tramp-methods)) ;; cleanup previous tramp method
  ;; TODO error message if resource is not pod
  (add-to-list 'tramp-methods
               `("kubectl"
                 (tramp-login-program      ,kubel-kubectl)
                 (tramp-login-args         (,(kubel--get-context-kubectl-arg) ,(kubel--get-ns-kubectl-arg ns) ("exec" "-it") ("-c" "%u") ("%h") ("--" "sh")))
                 (tramp-remote-shell       "sh")
                 (tramp-remote-shell-args  ("-i" "-c"))))) ;; add the current context/namespace to tramp methods

;; TODO: maybe redefine it to (ns . (pod . container)), simplify
(defun kubel--get-container-under-cursor ()
  "Get `(container . pod)' name under cursor."
  (let* ((cell (if (kubel--pod-view?)
                   (kubel--get-ns-name-under-cursor)
                 (kubel--select-resource "Pods")))
         (ns (car cell))
         (name (cdr cell))
         (containers (kubel--get-containers ns name))
         (container (if (equal (length containers) 1)
                        (car containers)
                      (completing-read "Select container: " containers))))
    (cons container name)))

(defun kubel--dir-prefix ()
  "Return the current directory prefix for a TRAMP connection."
  (or
   (when (tramp-tramp-file-p default-directory)
     (with-parsed-tramp-file-name default-directory nil
       (format "%s%s:%s|" (or hop "") method (if user (concat user "@" host) host))))
   ""))

(defun kubel-exec-pod ()
  "Exec into the pod under the cursor -> `find-file."
  (interactive)
  (kubel-setup-tramp (kubel--get-ns-under-cursor))
  (let* ((dir-prefix (kubel--dir-prefix))
         (con-pod (kubel--get-container-under-cursor)))
    (find-file (format "/%skubectl:%s@%s:/" dir-prefix (car con-pod) (cdr con-pod)))))

(defun kubel--shell-buffer-name (shell-type container pod)
  "Generate the name for a pod's shell buffer.

This uses `kubel-shell-buffer-name-format' as the buffer name
format. See the documentation for it for more information on how
to set this format.

The values for the current namespace and context are pulled from
the variables `kubel-namespace' and `kubel-context', respectively."
  (format-spec kubel-shell-buffer-name-format
               `((?t . ,shell-type)
                 (?c . ,container)
                 (?p . ,pod)
                 (?n . ,kubel-namespace)
                 (?C . ,kubel-context))))

(defun kubel-exec-shell-pod ()
  "Exec into the pod under the cursor -> shell."
  (interactive)
  (kubel-setup-tramp (kubel--get-ns-under-cursor))
  (let* ((dir-prefix (kubel--dir-prefix))
         (con-pod (kubel--get-container-under-cursor))
         (container (car con-pod))
         (pod (cdr con-pod))
         (default-directory (format "/%skubectl:%s@%s:/" dir-prefix container pod)))
    (shell (kubel--shell-buffer-name "shell" container pod))))

(defun kubel-exec-eshell-pod ()
  "Exec into the pod under the cursor -> eshell."
  (interactive)
  (kubel-setup-tramp (kubel--get-ns-under-cursor))
  (let* ((dir-prefix (kubel--dir-prefix))
         (con-pod (kubel--get-container-under-cursor))
         (container (car con-pod))
         (pod (cdr con-pod))
         (default-directory (format "/%skubectl:%s@%s:/" dir-prefix container pod))
         (eshell-buffer-name
          (kubel--shell-buffer-name "eshell" container pod)))
    (eshell)))

(defun kubel-exec-vterm-pod ()
  "Exec into the pod under the cursor -> vterm."
  (interactive)
  (kubel-setup-tramp (kubel--get-ns-under-cursor))
  (let* ((dir-prefix (kubel--dir-prefix))
         (con-pod (kubel--get-container-under-cursor))
         (container (car con-pod))
         (pod (cdr con-pod))
         (default-directory (format "/%skubectl:%s@%s:/" dir-prefix container pod))
         (vterm-buffer-name
          (kubel--shell-buffer-name "vterm" container pod))
         (vterm-shell "/bin/sh"))
    (vterm nil)))

;;;###autoload
(defun kubel-vterm-setup ()
  "Adds a vterm enty to the KUBEL-EXEC-POP."
  (require 'vterm)
  (transient-append-suffix 'kubel-exec-popup "e"
    '("v" "Vterm" kubel-exec-vterm-pod)))

(defun kubel-exec-ansi-term-pod ()
  "Exec into the pod under the cursor -> `ansi-term'."
  (interactive)
  (let* ((ns (kubel--get-ns-under-cursor))
         (con-pod (kubel--get-container-under-cursor))
         (container (car con-pod))
         (name (cdr con-pod))
         (command (format "%s exec %s -c %s -i -t -- /usr/bin/env sh" (kubel--kubectl-prefix ns) name container)))
    (with-current-buffer (ansi-term "bash" (kubel--shell-buffer-name "ansi-term" container name))
      (process-send-string (current-buffer) (format "%s\n" command)))))

(defun kubel-exec-eat-pod ()
  "Exec into the pod under the cursor -> eat."
  (interactive)
  (unless (fboundp 'eat-other-window)
    (user-error "This command requires the `eat' package."))
  (kubel-setup-tramp (kubel--get-ns-under-cursor))
  (let* ((dir-prefix (kubel--dir-prefix))
         (con-pod (kubel--get-container-under-cursor))
         (container (car con-pod))
         (pod (cdr con-pod))
         (default-directory (format "/%skubectl:%s@%s:/" dir-prefix container pod))
         (eat-buffer-name (format "*eat:%s" default-directory)))
    (eat-other-window)))

(defun kubel-exec-pod-by-shell-command ()
  "Prompt shell with kubectl exec command at pod under cursor."
  (interactive)
  (let* ((con-pod (kubel--get-container-under-cursor))
         (command (read-string "Shell command: "
                              (format "%s exec %s -c %s -- " (kubel--kubectl-prefix kubel-namespace) (cdr con-pod) (car con-pod)))))
    (kubel-setup-tramp (kubel--get-ns-under-cursor))
    (shell-command command)))


(defun kubel-delete-resource ()
  "Kubectl delete resource under cursor."
  (interactive)
  (dolist (resource (if (kubel--items-selected?)
                        (ht-keys kubel--selected-items-set)
                      (list (kubel--get-ns-name-under-cursor))))
    (let* ((ns (car resource))
           (name (cdr resource))
           (process-name (format "kubel - delete %s - %s" kubel-resource-type name))
           (args (list "delete" kubel-resource-type name)))
     (when (transient-args 'kubel-delete-popup)
       (setq args (append args (list "--force" "--grace-period=0"))))
     (kubel--exec process-name ns 'delete args)
     (kubel-refresh))))

(defun kubel-jab-deployment ()
  "Make a trivial patch to force a new deployment.

See https://github.com/kubernetes/kubernetes/issues/27081"
  (interactive)
  (dolist (deployment (if (kubel--deployment-view?)
                          (if (kubel--items-selected?)
                              (ht-keys kubel--selected-items-set)
                            (list (kubel--get-ns-name-under-cursor)))
                        (list (kubel--select-resource "Deployments"))))
    (let* ((ns (car deployment))
           (name (cdr deployment))
           (process-name (format "kubel - bouncing - %s" name)))
      (kubel--exec process-name ns 'patch
                   (list "patch" "deployment" name "-p"
                         (format "{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"date\":\"%s\"}}}}}"
                                 (round (time-to-seconds))))))))

(defun kubel-scale-replicas (replicas)
  "Scale resource replicas.

REPLICAS is the number of desired replicas."
  (interactive (list (read-number "Replicas: ")))
  (if (kubel--is-scalable)
      (let* ((cell (kubel--get-ns-name-under-cursor))
             (ns (car cell))
             (name (cdr cell))
             (process-name (format "kubel:scale:%s/%s" kubel-resource-type name)))
        (kubel--exec process-name ns 'scale (list "scale" kubel-resource-type name "--replicas" (number-to-string replicas))))
    (message
     "[%s] cannot be scaled.\nOnly these resources can be scaled: [deployment, replica set and stateful set]."
     kubel-resource-type)))

(defun kubel-set-filter ()
  "Set the view filter."
  (interactive)
  (setq kubel-resource-filter (read-string "Filter: " kubel-resource-filter))
  (setq kubel--no-reset-sort-column t)
  (kubel-refresh t))

(defun kubel--jump-to-highlight (init search reset)
  "Base function to jump to highlight.

INIT is to be called before searching.
SEARCH is to apply the search and can be repeated safely.
RESET is to be called if the search is nil after the first attempt."
  (unless (equal kubel-resource-filter "")
    (funcall init)
    (unless (funcall search)
      (funcall reset)
      (funcall search))
    (beginning-of-line)))

(defun kubel-jump-to-next-highlight ()
  "Jump to the next hightlighted resrouce."
  (interactive)
  (kubel--jump-to-highlight
   #'end-of-line
   (lambda () (re-search-forward kubel-resource-filter (point-max) t))
   #'beginning-of-buffer))

(defun kubel-jump-to-previous-highlight ()
  "Jump to the previou highlighted resrouce."
  (interactive)
  (kubel--jump-to-highlight
   #'beginning-of-line
   (lambda () (re-search-backward kubel-resource-filter (point-min) t))
   #'end-of-buffer))

(defun kubel-rollout-history ()
  "See rollout history for resource under cursor."
  (interactive)
  ;; TODO: implement view type constraints for resource types it makes sense for
  (let* ((cell (kubel--get-ns-name-under-cursor))
         (ns (car cell))
         (name (cdr cell)))
    (kubel--show-rollout-revision kubel-resource-type ns name)))

(defun kubel-changelog ()
  "Opens up the changelog."
  (interactive)
  (browse-url "https://github.com/abrochard/kubel/blob/master/CHANGELOG.md"))

(defun kubel-quick-edit ()
  "Quickly edit any resource."
  (interactive)
  (kubel--describe-object
   (completing-read "Select resource: " (kubel--kubernetes-api-resources-list))))

(defun kubel-show-process-buffer ()
  "Show the kubel-process-buffer."
  (interactive)
  (pop-to-buffer kubel--process-buffer)
  (special-mode))

(defun kubel-mark-item ()
  "Mark the item under cursor."
  (interactive)
  (let ((item (kubel--get-ns-name-under-cursor)))
    (unless (ht-contains? kubel--selected-items-set item)
      (ht-set kubel--selected-items-set item t)
      (kubel-refresh t))
    (forward-line 1)))

(defun kubel-unmark-item (&optional backward)
  "Unmark the item under cursor.

BACKWARD moves back one line if set."
  (interactive)
  (let ((item (kubel--get-ns-name-under-cursor)))
    (when (ht-contains? kubel--selected-items-set item)
      (ht-remove kubel--selected-items-set item)
      (kubel-refresh t))
    (if backward
        (forward-line -1)
      (forward-line 1))))

(defun kubel-unmark-item-backward ()
  "Unmark the item under cursor and move it backwards."
  (interactive)
  (kubel-unmark-item t))

(defun kubel-mark-all ()
 "Mark all items."
 (interactive)
 (ht-clear kubel--selected-items-set)
 (save-excursion
   (goto-char (point-min))
   (while (not (eobp))
     (ht-set kubel--selected-items-set (kubel--get-ns-name-under-cursor) t)
     (forward-line 1)))
 (kubel-refresh t))

(defun kubel-unmark-all ()
  "Unmark all items."
  (interactive)
  (ht-clear kubel--selected-items-set)
  (kubel-refresh t))

(defun kubel--read-buffer ()
  "Return the list of all buffers of kubel pattern."
  (let* ((other-buffer (other-buffer (current-buffer)))
         (other-name (buffer-name other-buffer))
         (buffers))
    (dolist (buf (buffer-list))
      (when (string-prefix-p "*kubel:" (buffer-name buf))
        (push buf buffers)))
    (let ((predicate
           (lambda (buffer)
             ;; BUFFER is an entry (BUF-NAME . BUF-OBJ) of Vbuffer_alist.
             (memq (cdr buffer) buffers))))
      (read-buffer
       "Switch to buffer: "
       (when (funcall predicate (cons other-name other-buffer)) other-name)
       nil
       predicate))))

(defun kubel-switch-to-buffer (buffer-or-name)
  "Display buffer BUFFER-OR-NAME in the selected window.
When called interactively, prompts for a buffer belonging to kubel."
  (interactive (list (kubel--read-buffer)))
  (switch-to-buffer buffer-or-name))

(defun kubel--find-resource-type-alias (resource-type)
  "Function to find an alias to a given resource-type that exists in the
cluster.

RESOURCE-TYPE is a resource-type."
  (let ((alias nil))
    (dolist (possible-alias (ht-get kubel--resource-type->aliases-ht resource-type) alias)
      (if (member possible-alias (kubel--kubernetes-api-resources-list))
          (setq alias possible-alias)))))

(defun kubel--select-only (ns name)
  "Utility function to set selected items to a single item.

NS is object's namespace.
NAME is object's name."
  (ht-clear kubel--selected-items-set)
  (ht-set kubel--selected-items-set (cons ns name) t))

(defun kubel-jump-to-owner ()
  (interactive)
  (let* ((ns-name (kubel--get-ns-name-under-cursor))
         (ns (car ns-name))
         (name (cdr ns-name))
         (json-object (json-parse-string (kubel--exec-to-string (format "%s --context %s --namespace %s get %s %s -o json"
                                                                        kubel-kubectl kubel-context ns kubel-resource-type name))))
         (json-owner-references (ht-get* json-object "metadata" "ownerReferences")))
    (if (null json-owner-references)
        (message "Object has no owner.")
      (let* ((owner-reference (aref (ht-get* json-object "metadata" "ownerReferences") 0))
             (owner-kind (ht-get owner-reference "kind"))
             (owner-name (ht-get owner-reference "name"))
             (owner-kind-plural (ht-get kubel--resource-type-singular->plural-ht owner-kind))
             (owner-kind-actual (kubel--find-resource-type-alias owner-kind-plural)))
        (message "owner: %s" owner-kind-actual)
        (with-current-buffer (clone-buffer)
          (setq kubel-resource-type owner-kind-actual)
          (kubel--select-only ns owner-name)
          (setq kubel-selectors '())
          (setq kubel-field-selectors "")
          (switch-to-buffer (current-buffer))
          (kubel-refresh)
          ;; set the cursor to the marked line
          (search-forward "*"))))))

(defun kubel-jump-to-children ()
  (interactive)
  (cond ((s-equals? "nodes" kubel-resource-type)
         (let* ((ns-name (kubel--get-ns-name-under-cursor))
                (name (cdr ns-name)))
           (with-current-buffer (clone-buffer)
             (setq kubel-resource-type "pods")
             (setq kubel-field-selectors (format "spec.nodeName=%s" name))
             (switch-to-buffer (current-buffer))
             (kubel-refresh))))
        (t
         (let* ((ns-name (kubel--get-ns-name-under-cursor))
                (ns (car ns-name))
                (name (cdr ns-name))
                (json-object (json-parse-string (kubel--exec-to-string (format "%s --context %s --namespace %s get %s %s -o json"
                                                                               kubel-kubectl kubel-context ns kubel-resource-type name))))
                (owner-selector (ht-get* json-object "spec" "selector")))
           (if (null owner-selector)
               (error "Object has no children.")
             (let* ((owner-match-labels (ht-get* json-object "spec" "selector" "matchLabels"))
                    (owner-kind-plural kubel-resource-type)
                    (owner-kind-internal (ht-get kubel--resource-type->internal-type-ht owner-kind-plural))
                    (child-kind-internal (asoc-get kubel--internal-type-ownership-alist owner-kind-internal))
                    (child-kind-alias (car (asoc-get kubel--internal-type-resource-type-alias-alist child-kind-internal)))
                    (child-kind-actual (kubel--find-resource-type-alias child-kind-alias)))
               (with-current-buffer (clone-buffer)
                 (setq kubel-resource-type child-kind-actual)
                 (setq kubel-selectors (mapcar (lambda (label-value) (format "%s=%s" (car label-value) (cadr label-value)))
                                               (ht-items owner-match-labels)))
                 (setq kubel-field-selectors "")
                 (switch-to-buffer (current-buffer))
                 (kubel-refresh))))))))

(defun kubel-jump-to-node ()
  (interactive)
  (if (not (kubel--pod-view?))
      (error "Not in the pod view.")
    (let* ((ns-name (kubel--get-ns-name-under-cursor))
           (ns (car ns-name))
           (name (cdr ns-name))
           (json-object (json-parse-string (kubel--exec-to-string (format "%s --context %s --namespace %s get %s %s -o json"
                                                                          kubel-kubectl kubel-context ns kubel-resource-type name))))
           (node-name (ht-get* json-object "spec" "nodeName"))
           (nodes-resource-type "nodes"))
      (with-current-buffer (clone-buffer)
        (setq kubel-resource-type nodes-resource-type)
        (setq kubel-field-selectors (concat "metadata.name=" node-name))
        (switch-to-buffer (current-buffer))
        (kubel-refresh)))))

;; shell magic has to happen here
(defun kubel-node-shell ()
  (interactive)
  (if (not (kubel--node-view?))
      (error "Not in a node view.")
    (error "Not implemented.")))

;; popups

(transient-define-prefix kubel-exec-popup ()
  "Kubel Exec Menu"
  ["Actions"
   ("!" "Shell command" kubel-exec-pod-by-shell-command)
   ("d" "Dired" kubel-exec-pod)
   ("e" "Eshell" kubel-exec-eshell-pod)
   ("a" "Ansi-term" kubel-exec-ansi-term-pod)
   ("t" "eat" kubel-exec-eat-pod)
   ("s" "Shell" kubel-exec-shell-pod)])

(transient-define-prefix kubel-configure-popup ()
  "Kubel Configure Menu"
  ["Actions"
   ("c" "Context" kubel-set-context)
   ("n" "Namespace" kubel-set-namespace)
   ("r" "Resource Type" kubel-set-resource)
   ("f" "Config file" kubel-set-kubectl-config-file)])

(transient-define-prefix kubel-filtering-popup ()
  "Kubel Format/Filtering Menu"
  ["Actions"
   ("c" "Toggle complex views" toggle-kubel-complex-views)
   ("h" "Toggle regex filter hides" toggle-kubel-filter-hides)
   ("r" "Regex filter" kubel-set-filter)
   ("o" "Output format" kubel-set-output-format)
   ("f" "Field selector" kubel-set-field-selector)
   ("l" "Label selector" kubel-set-label-selector)])

(transient-define-prefix kubel-resource-popup ()
  "Kubel Resource Menu"
  ["Actions"
   ("e" "Exec" kubel-exec-popup)
   ("j" "Jab deployment" kubel-jab-deployment)
   ("r" "Rollout history" kubel-rollout-history)
   ("s" "Scale" kubel-scale-replicas)
   ("p" "Port forward" kubel-port-forward-pod)
   ("l" "Logs" kubel-log-popup)
   ("k" "Delete" kubel-delete-popup)
   ("n" "Node-shell" kubel-node-shell)])

(transient-define-prefix kubel-jump-popup ()
  "Kubel Jump Menu"
  ["Actions"
   ("o" "Owner" kubel-jump-to-owner)
   ("c" "Children" kubel-jump-to-children)
   ("n" "Node" kubel-jump-to-node)])

(transient-define-prefix kubel-log-popup ()
  "Kubel Log Menu"
  ["Arguments"
   ("-f" "Follow" "-f")
   ("-t" "Timestamps" "--timestamps")
   ("-p" "Previous" "-p")
   ("-n" "Tail" "--tail=")]
  ["Actions"
   ("l" "Tail pod logs" kubel-get-pod-logs)
   ("i" "Tail initContainer logs" kubel-get-pod-logs--initContainer)
   ("L" "Tail by labels" kubel-get-logs-by-labels)])

(transient-define-prefix kubel-copy-popup ()
  "Kubel Copy Menu"
  ["Actions"
   ("w" "Copy resource name" kubel-copy-resource-name)
   ("l" "Copy pod log command" kubel-copy-log-command)
   ("p" "Copy command prefix" kubel-copy-command-prefix)
   ("c" "Copy last command" kubel-copy-last-command)])

(transient-define-prefix kubel-delete-popup ()
  "Kubel Delete menu"
  ["Arguments"
   ("-f" "Force" "--force --grace-period=0")]
  ["Actions"
   ("k" "Delete resource(s)" kubel-delete-resource)])

(transient-define-prefix kubel-describe-popup ()
  "Kubel Describe Menu"
  ["Arguments"
   ("-y" "Yaml" "-o yaml")]
  ["Actions"
   ("RET" "Describe" kubel-get-object-details)])

(transient-define-prefix kubel-help-popup ()
  "Kubel Menu"
  [["Actions"
    ;; global
    ("RET" "Resource details" kubel-describe-popup)
    ("e" "Quick edit" kubel-quick-edit)
    ("g" "Refresh" kubel-refresh)
    ("b" "Buffers" kubel-switch-to-buffer)]
   [""
    ("c" "Configure..." kubel-configure-popup)
    ("r" "Act on resource..." kubel-resource-popup)
    ("j" "Jump to resource..." kubel-jump-popup)]
   ["Filtering"
    ("f" "Output and filtering..." kubel-filtering-popup)
    ("s" "Sort" kubel-sort-by-column-at-point)
    ("S" "Revert sorting" kubel-sort-revert)
    ("M-n" "Next highlight" kubel-jump-to-next-highlight)
    ("M-p" "Previous highlight" kubel-jump-to-previous-highlight)]
   ["Marking"
    ("m" "Mark item" kubel-mark-item)
    ("u" "Unmark item" kubel-unmark-item)
    ("DEL" "Unmark item and move back" kubel-unmark-item-backward)
    ("M" "Mark all items" kubel-mark-all)
    ("U" "Unmark all items" kubel-unmark-all)]
   ["Utilities"
    ("w" "Copy to clipboad..." kubel-copy-popup)
    ("$" "Show Process buffer" kubel-show-process-buffer)]])

;; mode map
(defvar kubel-mode-map
  (let ((map (make-sparse-keymap)))
    ;; global
    (define-key map (kbd "RET") 'kubel-get-object-details)
    (define-key map (kbd "e") 'kubel-quick-edit)
    (define-key map (kbd "g") 'kubel-refresh)
    (define-key map (kbd "b") 'kubel-switch-to-buffer)
    (define-key map (kbd "$") 'kubel-show-process-buffer)
    (define-key map (kbd "c") 'kubel-configure-popup)
    (define-key map (kbd "h") 'kubel-help-popup)
    (define-key map (kbd "?") 'kubel-help-popup)
    (define-key map (kbd "f") 'kubel-filtering-popup)
    (define-key map (kbd "r") 'kubel-resource-popup)
    (define-key map (kbd "j") 'kubel-jump-popup)
    (define-key map (kbd "w") 'kubel-copy-popup)
    (define-key map (kbd "s") 'kubel-sort-by-column-at-point)
    (define-key map (kbd "S") 'kubel-sort-revert)
    (define-key map (kbd "M-n") 'kubel-jump-to-next-highlight)
    (define-key map (kbd "M-p") 'kubel-jump-to-previous-highlight)

    ;; based on view
    (define-key map (kbd "w") 'kubel-copy-popup)

    ;; (define-key map (kbd "m") 'kubel-mark-item)
    (define-key map (kbd "m") 'kubel-mark-item)
    (define-key map (kbd "u") 'kubel-unmark-item)
    (define-key map (kbd "DEL") 'kubel-unmark-item-backward)
    (define-key map (kbd "M") 'kubel-mark-all)
    (define-key map (kbd "U") 'kubel-unmark-all)

    map)
  "Keymap for `kubel-mode'.")

(defun kubel--current-state ()
  "Show the current context, namespace, and resource in the Echo Area.
Append filter to the modeline."
  (setq mode-line-misc-info
        (mapconcat 'identity (append
                              (unless (s-blank? kubel-resource-filter)
                                (list (format "/%s" kubel-resource-filter))))
                             " "))
  (message (concat
            (format "[Context: %s] [Namespace: %s] [Resource: %s]" kubel-context kubel-namespace kubel-resource-type)
            (unless (and (kubel--empty? kubel-selectors) (s-blank? kubel-field-selectors))
              (concat " (" (mapconcat #'identity
                                      (append kubel-selectors
                                              (unless (s-blank? kubel-field-selectors)
                                                (list kubel-field-selectors)))
                                      " ")
                      ")"))
            (unless (equal kubel-resource-filter "")
              (format " /%s" kubel-resource-filter)))))

(defun kubel--ns (item-alist)
  "Utility function to get namespace of list item's alist"
  (cond
   ((kubel--resource-type-global? kubel-resource-type) nil)
   (kubel--all-namespaces-view (asoc-get item-alist "NAMESPACE"))
   (t kubel-namespace)))

(defun kubel--populate-view-entries (entries)
  "Function to populate kubel--ns-name->columns-alist variable."
  (ht-clear kubel--ns-name->columns-alist)
  (let ((column-names (car entries)))
    (dolist (values (cdr entries))
      (let ((item-alist (asoc-make)))
        ;; used for side effects
        (cl-mapcar (lambda (column-name value)
                     (asoc-put! item-alist column-name value))
                   column-names values)
        (let ((ns (kubel--ns item-alist))
              (name (asoc-get item-alist "NAME")))
          (ht-set kubel--ns-name->columns-alist (cons ns name) (reverse item-alist)))))))


(defun kubel--get-global-resources-set ()
  (if (ht-empty? kubel--global-resources-set-cached)
      (let ((global-resources (split-string (kubel--exec-to-string
                                             (format "%s --context %s api-resources --namespaced=false -o name"
                                                     kubel-kubectl kubel-context)))))
        (dolist (entry global-resources)
          (ht-set kubel--global-resources-set-cached entry t))))
  kubel--global-resources-set-cached)

(defvar-local kubel--no-reset-sort-column nil)

;;;###autoload
(defun kubel-refresh (&optional no-refresh directory)
  "Refresh the current kubel buffer, calling kubectl using the configured
context, namespace, and resource.

DIRECTORY is optional for TRAMP support."
  (interactive)
  (when directory (setq default-directory directory))
  (let ((name (kubel--buffer-name)))
    ;; Remove old buffer if exist but not is current buffer
    (if (get-buffer name)
        (unless (equal (buffer-name (current-buffer)) name)
          (kill-buffer (get-buffer name))))
    (rename-buffer name)
    (unless no-refresh
      (message (format "Running kubectl for: %s..." name))))
  (if (and (kubel--all-namespaces?)
           (not (kubel--resource-type-global? kubel-resource-type)))
      (setq kubel--all-namespaces-view t)
    (setq kubel--all-namespaces-view nil))
  (let ((entries (kubel--populate-list no-refresh)))
    (setq tabulated-list-format (car entries))
    (setq tabulated-list-entries (cadr entries)))   ; TODO handle "No resource found"
  (kubel--update-selected-items)
  (setq tabulated-list-sort-key kubel--list-sort-key)
  (setq tabulated-list-sort-key nil)
  (tabulated-list-init-header)
  (let ((line-num (line-number-at-pos (point)))
        (current-id (tabulated-list-get-id)))
    (tabulated-list-print t)
    (unless (string-equal current-id (tabulated-list-get-id))
      ;; tabulated-list could not follow the current entry, then fallback on
      ;; keeping the same line.
      (goto-char (point-min))
      (forward-line (1- line-num))))
  (when (or (and kubel--no-reset-sort-column kubel--last-column-sorted)
            (called-interactively-p 'interactive))
    (tabulated-list-sort kubel--last-column-sorted)
    (if kubel--last-column-sorted-direction
        (tabulated-list-sort kubel--last-column-sorted)))
  ;; TODO: stuff resets the colnum
  (when (and (not kubel--no-reset-sort-column)
             (not (called-interactively-p 'interactive)))
    (setq kubel--last-column-sorted nil)
    (setq kubel--last-column-sorted-direction nil))
  (setq kubel--no-reset-sort-column nil)
  (setq kubel--last-context kubel-context)
  (setq kubel--last-namespace kubel-namespace)
  (unless no-refresh
    (kubel--current-state)))

(defun toggle-kubel-filter-hides ()
  (interactive)
  (setq kubel-filter-hides (not kubel-filter-hides))
  (message "Kubel regex filter hides %s" (if kubel-filter-hides "enabled" "disabled"))
  (kubel-refresh))

;;;###autoload
(defun kubel-open (context namespace resource &optional directory)
  "Create a new kubel buffer using passed parameters CONTEXT NAMESPACE RESOURCE.
DIRECTORY is optional for TRAMP support."
  (let ((tmpname "*kubel-tmp*")
        (name (kubel--buffer-name-from-parameters context namespace resource)))
    (if (get-buffer name)
        (pop-to-buffer-same-window name)
      (with-current-buffer (get-buffer-create tmpname)
        (kubel-mode)
        (setq kubel-context context)
        (setq kubel-namespace namespace)
        (setq kubel-resource-type resource)
        (pop-to-buffer-same-window tmpname)
        (kubel-refresh nil directory)))))

;;;###autoload
(defun kubel (&optional directory)
  "Invoke the kubel buffer.
DIRECTORY is optional for TRAMP support."
  (interactive)
  (let* ((name (kubel--buffer-name))
         (buf (or (get-buffer name)
                  (get-buffer-create name))))
    (with-current-buffer buf
      (switch-to-buffer (current-buffer))
      (unless (eq major-mode 'kubel-mode)
        (kubel-mode))
      (kubel-refresh nil directory))))

;;;###autoload
(defun kubel-apply-arbitrary (&optional no-prompt)
  "Apply an arbitrary resource to last used context and namespace."
  (interactive "P")
  (if (or (null kubel--last-context)
          (null kubel--last-namespace))
      (error "You have to refresh at least one kubel buffer first.")
    (let ((kubel-context kubel--last-context)
          (kubel-namespace kubel--last-namespace))
      (when (or no-prompt (y-or-n-p (format "Apply to ctx %s, ns %s? " kubel-context kubel-namespace)))
        (let ((current-prefix-arg t))
          (call-interactively #'kubel-apply t))))))

;;;###autoload
(defun kubel-delete-arbitrary (&optional no-prompt)
  "Delete an arbitrary resource from the last used context and namespace."
  (interactive "P")
  (if (or (null kubel--last-context)
          (null kubel--last-namespace))
      (error "You have to refresh at least one kubel buffer first.")
    (let ((kubel-context kubel--last-context)
          (kubel-namespace kubel--last-namespace))
      (when (or no-prompt (y-or-n-p (format "Delete from ctx %s, ns %s? " kubel-context kubel-namespace)))
        (let ((current-prefix-arg t))
          (kubel--delete))))))

(define-derived-mode kubel-mode tabulated-list-mode "Kubel"
  "Special mode for kubel buffers."
  (buffer-disable-undo)
  (kill-all-local-variables)
  (setq truncate-lines t)
  (setq mode-name "Kubel")
  (setq major-mode 'kubel-mode)
  (use-local-map kubel-mode-map)
  (hl-line-mode 1)
  (run-mode-hooks 'kubel-mode-hook))

(provide 'kubel)
;;; kubel.el ends here
