(defstruct (lock (:constructor %make-lock))
  (flag (make-array 32 :element-type 'sb-ext:word :initial-element 0) :type (simple-array sb-ext:word (*)))
  (tail 0 :type sb-ext:word))

(defun make-lock ()
  (let ((lock (%make-lock)))
    (setf (aref (lock-flag lock) 0) 1)
    lock))

(defvar *slot-index*)

(declaim (inline lock unlock))
(locally (declare (optimize speed (safety 0)))
  (defun lock (lock)
    (declare (type lock lock))
    (let ((index (mod (atomic-incf (lock-tail lock)) 32)))
      (setf *slot-index* index)
      (loop while (zerop (aref (lock-flag lock) index)))))
  (defun unlock (lock)
    (declare (type lock lock))
    (let ((index *slot-index*))
      (setf (aref (lock-flag lock) index) 0)
      (setf (aref (lock-flag lock) (mod (1+ index) 32)) 1)
      (setf *slot-index* nil)))
  (defmacro with-spinlock ((lock) &body body)
    `(let ((lock ,lock))
       (unwind-protect
            (progn
              (lock lock)
              (locally ,@body))
         (unlock lock))))) 


