(in-package :future-test)

(in-suite root-suite)

(defsuite* stress-test)

(deftest 100p-100times ()
  (loop repeat 100
        do
     (progn
       (kill-all-futures)
       (assert-no-futures) 
       (let ((futures (loop repeat 100
                            collect
                         (future (sleep 0.01) (+ 1 1)))))
         (is (= 100 (futures-count)))
         (is (= 200 (reduce '+ futures :key 'touch))))
       (assert-no-futures))))
