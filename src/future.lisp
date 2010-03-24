(in-package :future)

(defvar *future-max-threads* 4)

(defvar *finished-futures* (make-queue))
(defvar *thread-pool* (make-thread-pool))

(defvar *after-finish-hooks* nil)
(defvar *before-start-hooks* nil)

(defclass future ()
  ((lambda :accessor lambda-of
     :initarg :lambda
     :initform (error "Must provide lambda for future"))
   (current-thread :accessor current-thread-of :initform nil)
   (result :accessor result-of :initform 'unbound)))

(defmethod print-object ((f future) stream)
  (with-accessors ((result result-of) (current-thread current-thread-of)) f
    (print-unreadable-object (f stream :type t :identity t)
      (format stream "RESULT: ~A, CURRENT-THREAD: ~A" result current-thread))))

(defun future-finished-p (future)
  (not (eq (result-of future) 'unbound)))

;;; 
(defun initialize-environment (&key kill-current-futures-p)
  (when kill-current-futures-p
    (kill-all-futures))
  (setf *thread-pool* (make-thread-pool)))

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
    (when (not (future-finished-p future))
      (with-mutex ((queue-mutex queue))
        (loop
          (tagbody
           :continue
             (multiple-value-bind (finished-future available-p) (dequeue queue)
               (if available-p
                   (when (eq finished-future future)
                     (return future))
                   (wait-condition-variable (queue-cond-var queue) (queue-mutex queue))))))))))

(defun wait-for-any-future ()
  (let ((queue *finished-futures*))
    (with-mutex ((queue-mutex queue))
      (wait-condition-variable (queue-cond-var queue) (queue-mutex queue))
      (dequeue queue))))

;; wait-for-all-futures

(defun kill-future (future)
  (unless (future-finished-p future)
    (with-mutex ((thread-pool-mutex *thread-pool*))
      (let ((future-thread (current-thread-of future)))
        (when future-thread
          (kill-thread future-thread))
        (queue-delete-item (lambda-of future) (thread-pool-task-queue *thread-pool*))
        (queue-delete-item future *finished-futures*)
        nil)))) 

(defun kill-all-futures ()
  ;; NOTE: this is special
  (reset-thread-pool *thread-pool*)
  (queue-empty! *finished-futures*))

(defun eval-future (fn)
  (let ((future (make-instance 'future :lambda nil)))
    (labels ((future-body ()
               (setf (current-thread-of future) (current-thread))
               (let ((result (funcall fn)))
                 (setf (result-of future) result)
                 (enqueue future *finished-futures*)
                 (setf (current-thread-of future) nil)
                 (queue-notify *finished-futures*))))
      (setf (lambda-of future) #'future-body)
      (assign-task (lambda-of future) *thread-pool*)
      future)))

(defmacro future (&body body)
  `(eval-future #'(lambda () ,@body)))

(defun touch (future)
  "walk the list structure 'future', replacing any futures with their
evaluated values. Blocks if a future is still running."
  (with-slots (result) future
    (wait-for-future future) 
    (result-of future)))

