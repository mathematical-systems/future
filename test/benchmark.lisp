(in-package :future-test)

(defun fib (x)
  (if (<= x 1)
      1
      (+ (fib (- x 1))
         (fib (- x 2)))))

(defun benchmark-parallel (x times)
  (kill-all-futures)
  (let (futures)
    (loop repeat times
          for f = (future (fib x))
          ;; collect f into fs
          ;; finally (setf futures fs)
          do (push f futures))
    (loop for f in futures
          for r = (touch f)
          collect r)))

(defun benchmark-sequential (x times)
  (loop repeat times
        for r = (fib x)
        collect r))
