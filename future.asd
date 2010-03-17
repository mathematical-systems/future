(cl:in-package :cl-user)

(defvar *fork-future-library-path* *load-truename*)

(asdf:defsystem fork-future
  :description "Fork-future is a thread based future parallel library"
  :author "Jianshi Huang @ Mathematical Systems Inc. (huang@msi.co.jp)"
  :version "0.1.20100317"
  :depends-on ()
  :components 
  ((:module src
            :components
            ((:file "package")
             (:file "thread-api" :depends-on ("package"))
             (:file "thread-pool" :depends-on ("thread-api"))
             (:file "future" :depends-on ("thread-pool"))))))

