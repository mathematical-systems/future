(cl:defpackage :future
    (:use :cl)
  (:export #:future
           #:touch
           #:wait-for-future
           #:wait-for-any-future
           #:wait-for-all-futures
           #:kill-future
           #:kill-all-futures
           #:*before-fork-hooks*
           #:*after-fork-hooks* 
           #:*future-max-threads*
           #:initialize-environment
           #:with-new-environment))

