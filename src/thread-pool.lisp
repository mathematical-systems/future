(in-package :future)

(defvar *thread-keep-alive-seconds* 30)

(deftype task () 'function)

(defun run-task (task)
  (funcall task))

(defstruct thread-pool
  (mutex (make-mutex :name "Thread pool mutex"))
  (limit 16)
  (thread-count 0)
  (idle-thread-count 0)
  threads
  (task-queue (make-queue)))

(defmacro deftpfun (name args &body body)
  `(defun ,name ,args
     (with-slots (mutex limit thread-count idle-thread-count threads task-queue) thread-pool
       (with-mutex (mutex)
         ,@body))))

(deftpfun thread-pool-full-p (thread-pool)
  (>= thread-count limit))

(deftpfun thread-pool-empty-p (thread-pool)
  (= thread-count 0))


(deftpfun make-active-thread (new-task thread-pool)
  (labels ((self-regulation ()
             (tagbody
              :run-next
                (multiple-value-bind (task availabie-p) (dequeue task-queue)
                  (when availabie-p
                    (run-task task)
                    (go :run-next)))
              :wait
                (with-mutex ((queue-mutex task-queue))
                  (incf idle-thread-count)
                  (when (eq :timeout
                            (prog1
                                (wait-for-new-items task-queue :timeout *thread-keep-alive-seconds*)
                              (decf idle-thread-count)))
                    (go :quit)) 
                  (go :run-next))
              :quit
                ;; NOTE: be sure to check there's no task before quit
                (with-mutex ((queue-mutex task-queue))
                  (when (not (queue-empty-p (thread-pool-task-queue thread-pool)))
                    (go :run-next))
                  (setf threads (delete (current-thread) threads))
                  (decf thread-count)))))
    (assert (not (thread-pool-full-p thread-pool)))
    (let ((thread (spawn-thread (lambda ()
                                  (run-task new-task)
                                  (self-regulation))
                                :name (format nil "Thread #~a" thread-count))))
      (push thread threads)
      (incf thread-count)
      thread)))

(deftpfun assign-task (task thread-pool)
  (if (not (thread-pool-full-p thread-pool))
      (make-active-thread task thread-pool)
      (progn
        (enqueue task task-queue)
        (queue-notify task-queue)))
  thread-pool)


(deftpfun reset-thread-pool (thread-pool)
  (queue-empty! task-queue)
  (mapc #'kill-thread threads)
  (setf threads '())
  (setf thread-count 0)
  (setf idle-thread-count 0) 
  thread-pool)
