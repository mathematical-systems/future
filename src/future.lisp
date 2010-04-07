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
  (lambda (error "Must provide lambda for future"))
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
  (setf *thread-pool* (make-thread-pool :limit *future-max-threads*))
  (setf *finished-futures* (make-queue)))

(defmacro with-new-environment (() &body body)
  `(let (*thread-pool*
         (*future-max-threads* *future-max-threads*)
         *after-finish-hooks*
         *before-start-hooks*
         *finished-futures*)
     (initialize-environment)
     (locally
         ,@body)))

;;;
(defun pop-all-finished-futures ()
  (let ((queue *finished-futures*))
    (loop while (nth-value 1 (dequeue queue)))))

(defun wait-for-future (future)
  (let ((queue *finished-futures*))
    (loop until (future-finished-p future)
          do
       (with-mutex ((queue-mutex queue))
         (multiple-value-bind (finished-future available-p) (dequeue queue)
           (if available-p
               (when (eq finished-future future)
                 (return))
               (wait-condition-variable (queue-cond-var queue) (queue-mutex queue))))))
    (pop-all-finished-futures)
    future))

(defun wait-for-any-future ()
  (let ((queue *finished-futures*))
    (with-mutex ((queue-mutex queue))
      (multiple-value-bind (finished-future available-p) (dequeue queue)
        (if available-p
            finished-future
            (progn
              (wait-condition-variable (queue-cond-var queue) (queue-mutex queue))
              (dequeue queue)))))))

(defun wait-for-all-futures (futures)
  (mapc #'wait-for-future futures))

(defun kill-future (future)
  (let ((thread-pool *thread-pool*))
    (unless (future-finished-p future)
      (with-mutex ((thread-pool-mutex thread-pool))
        (let ((future-thread (future-current-thread future)))
          (when (and future-thread (not (future-finished-p future)))
            (kill-thread future-thread)
            (setf (future-current-thread future) nil)
            (if (queue-empty-p (thread-pool-task-queue thread-pool))
                (decf (thread-pool-thread-count thread-pool))
                (let ((task (dequeue (thread-pool-task-queue thread-pool))))
                  (when task
                    (assign-task task thread-pool)))))
          (queue-delete-item (future-lambda future) (thread-pool-task-queue thread-pool)))))
    ;; remove it when finished
    ;; (queue-delete-item future *finished-futures*)
    ;; use pop-all-finished-futures is better
    (pop-all-finished-futures)
    nil)) 

(defun kill-all-futures ()
  ;; NOTE: this is special
  (reset-thread-pool *thread-pool*)
  (queue-empty! *finished-futures*))

(defun eval-future (fn)
  (let ((future (make-future :lambda nil)))
    (labels ((future-body ()
               (setf (future-current-thread future) (current-thread))
               (let ((result (funcall fn)))
                 (setf (future-result future) result)
                 (setf (future-current-thread future) nil)
                 (enqueue future *finished-futures*)
                 (queue-notify *finished-futures*))))
      (setf (future-lambda future) #'future-body)
      (assign-task (future-lambda future) *thread-pool*)
      future)))

(defmacro future (&body body)
  `(eval-future #'(lambda () ,@body)))

(defun touch (future)
  (wait-for-future future) 
  (future-result future))

