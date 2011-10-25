;;; 1 buffer length gate

#+(not allegro)
(defstruct (gate (:constructor %make-gate))
  in-semaphore
  out-semaphore)

(defun dfl-make-gate ()
  #+allegro (mp:make-gate t)
  #+sbcl (let ((gate (%make-gate)))
           (setf (gate-in-semaphore gate)
                 (sb-thread:make-semaphore :name "Gate In Semaphore" :count 1))
           (setf (gate-out-semaphore gate)
                 (sb-thread:make-semaphore :name "Gate Out Semaphore" :count 0))
           gate))

(defun dfl-gate-open-p (gate)
  #+allegro (mp:gate-open-p gate)
  #+sbcl (and (= (sb-thread:semaphore-count (gate-in-semaphore gate)) 1)
              (= (sb-thread:semaphore-count (gate-out-semaphore gate)) 0)))

(defun dfl-open-gate (gate)
  #+allegro (mp:open-gate gate)
  #+sbcl (unless (dfl-gate-open-p gate)
           (sb-thread:wait-on-semaphore (gate-out-semaphore gate))
           (sb-thread:signal-semaphore (gate-in-semaphore gate))))

(defun dfl-close-gate (gate)
  #+allegro (mp:close-gate gate)
  #+sbcl (when (dfl-gate-open-p gate)
           (sb-thread:wait-on-semaphore (gate-in-semaphore gate))
           (sb-thread:signal-semaphore (gate-out-semaphore gate))))


(defun dfl-wait-gate-open (gate)
  #+allegro (mp:process-wait "" #'mp:gate-open-p gate)
  #+sbcl (sb-thread:wait-on-semaphore ))

