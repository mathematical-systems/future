(in-package :future)

(defstruct pipe
  capacity
  semaphore
  source-process
  target-process
  )

