(in-package :future)

(defvar *future-max-threads* 4)
(defvar *finished-futures* (make-queue))
(defvar *thread-pool* (make-thread-pool :limit *future-max-threads*))

(defun future-max-threads ()
  *future-max-threads*)

(defun (setf future-max-threads) (newval)
  (setf (thread-pool-limit *thread-pool*) newval)
  (setf *future-max-threads* newval))

(defvar *after-finish-hooks* nil)
(defvar *before-start-hooks* nil)

(defstruct future 
  (lambda (error "Must provide lambda for future") :type function)
  current-thread
  (result 'unbound))

(defmethod print-object ((f future) stream)
  (with-slots (result current-thread) f
    (print-unreadable-object (f stream :type t :identity t)
      (format stream "RESULT: ~A, CURRENT-THREAD: ~A" result current-thread))))

(defun future-finished-p (future)
  (not (eq (future-result future) 'unbound)))

;;; 
(defun initialize-environment (&key kill-current-futures-p)
  (when kill-current-futures-p
    (kill-all-futures))
  (setf *thread-pool* (make-thread-pool :limit *future-max-threads*)))

(defmacro with-new-environment (() &body body)
  `(let (*thread-pool*
         (*future-max-threads* *future-max-threads*)
         *after-finish-hooks*
         *before-start-hooks*)
     (initialize-environment)
     (locally
         ,@body)))

;;;
(defun wait-for-future (future)
  (let ((queue *finished-futures*))
    (loop until (future-finished-p future)
          do
       (with-mutex ((queue-mutex queue))
         (multiple-value-bind (finished-future available-p) (dequeue queue)
           (if available-p
               (when (eq finished-future future)
                 (return future))
               (wait-condition-variable (queue-cond-var queue) (queue-mutex queue))))))
    future))

(defun wait-for-any-future ()
  (let ((queue *finished-futures*))
    (with-mutex ((queue-mutex queue))
      (wait-condition-variable (queue-cond-var queue) (queue-mutex queue))
      (dequeue queue))))

(defun wait-for-all-futures (futures)
  (mapc #'wait-for-future futures))

(defun kill-future (future)
  (let ((thread-pool *thread-pool*))
    (unless (future-finished-p future)
      (with-mutex ((thread-pool-mutex thread-pool))
        (let ((future-thread (future-current-thread future)))
          (when (and future-thread (not (future-finished-p future)))
            (kill-thread future-thread)
            (decf (thread-pool-thread-count thread-pool)))
          (queue-delete-item (future-lambda future) (thread-pool-task-queue thread-pool))
          (queue-delete-item future *finished-futures*)
          nil))))) 

(defun kill-all-futures ()
  ;; NOTE: this is special
  (reset-thread-pool *thread-pool*)
  (queue-empty! *finished-futures*))

(defun eval-future (fn)
  (let ((future (make-instance 'future :lambda nil)))
    (labels ((future-body ()
               (setf (future-current-thread future) (current-thread))
               (let ((result (funcall fn)))
                 (setf (future-result future) result)
                 (enqueue future *finished-futures*)
                 (setf (future-current-thread future) nil)
                 (queue-notify *finished-futures*))))
      (setf (future-lambda future) #'future-body)
      (assign-task (future-lambda future) *thread-pool*)
      future)))

(defmacro future (&body body)
  `(eval-future #'(lambda () ,@body)))

(defun touch (future)
  "walk the list structure 'future', replacing any futures with their
evaluated values. Blocks if a future is still running."
  (with-slots (result) future
    (wait-for-future future) 
    (future-result future)))

