(in-package :future-test)

(in-suite root-suite)

(defsuite* unit-test)

;;; queue
(defvar *empty-queue*)
(defvar *sample-queue*)

(defixture queue
  (setf *empty-queue* (future::make-queue))
  (setf *sample-queue* (future::make-queue :initial-content #(1 2 3))))

(defun push-pull (queue pause-time)
  (future::enqueue 1 queue)
  (future::enqueue 2 queue)
  (future::enqueue 3 queue)
  (when pause-time
    (sleep (random pause-time)))
  (future::dequeue queue)
  (future::dequeue queue)
  (future::dequeue queue))

(deftest simple-queue-tests ()
  (with-fixture queue
    (is (= 0 (future::queue-length *empty-queue*)))
    (is (= 3 (future::queue-length *sample-queue*)))
    (is (future::queue-empty-p *empty-queue*))
    (is (not (future::queue-empty-p *sample-queue*)))
    ;;
    (future::enqueue 1 *empty-queue*)
    (is (= 1 (future::queue-length *empty-queue*)))
    (is (not (future::queue-empty-p *empty-queue*)))
    ;;
    (future::queue-empty! *empty-queue*)
    (is (= 0 (future::queue-length *empty-queue*)))
    (is (future::queue-empty-p *empty-queue*))
    ;;
    (push-pull *empty-queue* 0.01)
    (is (= 0 (future::queue-length *empty-queue*)))
    (is (future::queue-empty-p *empty-queue*))
    ;;
    (future::queue-delete-item 2 *sample-queue*)
    (is (= 2 (future::queue-length *sample-queue*)))
    (is (= 1 (future::dequeue *sample-queue*)))
    (is (= 3 (future::dequeue *sample-queue*)))
    (is (= 0 (future::queue-length *sample-queue*)))
    (is (future::queue-empty-p *sample-queue*))
    ;;
    (future::with-mutex ((future::queue-mutex *empty-queue*))
      (future::wait-for-new-items *empty-queue* :timeout 0.1)
      (is (eq nil (future::dequeue *empty-queue*))))
    ;;
    (future::join-threads
     (list
      (future::spawn-thread
       (lambda ()
         (future::with-mutex ((future::queue-mutex *empty-queue*))
           (future::wait-for-new-items *empty-queue* :timeout 1)
           (is (= 1 (future::dequeue *empty-queue*))))))
      (future::spawn-thread
       (lambda ()
         (future::with-mutex ((future::queue-mutex *empty-queue*))
           (future::enqueue 1 *empty-queue*)
           (future::queue-notify *empty-queue*))))))
    (is (= 0 (future::queue-length *empty-queue*)))
    (is (future::queue-empty-p *empty-queue*))
    ))


;;;
(defvar *thread-pool*)

(defixture thread-pool
  (setf *thread-pool* (future::make-thread-pool :limit 3 :keep-alive-seconds 1)))

(deftest thread-pool-test ()
  (with-fixture thread-pool
    (is (future::thread-pool-empty-p *thread-pool*))
    (is (= 0 (future::thread-pool-idle-thread-count *thread-pool*)))
    (is (= 0 (length (future::thread-pool-threads *thread-pool*))))
    (is (future::queue-empty-p (future::thread-pool-task-queue *thread-pool*)))
    (is (not (future::thread-pool-full-p *thread-pool*)))
    ;;
    (future::assign-task (lambda () (sleep 1)) *thread-pool*)
    (is (not (future::thread-pool-empty-p *thread-pool*)))
    (is (= 0 (future::thread-pool-idle-thread-count *thread-pool*)))
    (is (= 1 (length (future::thread-pool-threads *thread-pool*))))
    (is (future::queue-empty-p (future::thread-pool-task-queue *thread-pool*)))
    (is (not (future::thread-pool-full-p *thread-pool*)))
    (future::assign-task (lambda () (sleep 1)) *thread-pool*)
    (future::assign-task (lambda () (sleep 1)) *thread-pool*)
    (is (future::thread-pool-full-p *thread-pool*))
    (is (= 0 (future::thread-pool-idle-thread-count *thread-pool*)))
    (is (= 3 (length (future::thread-pool-threads *thread-pool*))))
    (is (future::queue-empty-p (future::thread-pool-task-queue *thread-pool*)))
    (future::assign-task (lambda () (sleep 1)) *thread-pool*)
    (is (future::thread-pool-full-p *thread-pool*))
    (is (= 0 (future::thread-pool-idle-thread-count *thread-pool*)))
    (is (= 3 (length (future::thread-pool-threads *thread-pool*))))
    (is (not (future::queue-empty-p (future::thread-pool-task-queue *thread-pool*))))
    ;;
    (future::join-threads (future::thread-pool-threads *thread-pool*))
    (is (future::thread-pool-empty-p *thread-pool*))
    (is (= 0 (future::thread-pool-idle-thread-count *thread-pool*)))
    (is (= 0 (length (future::thread-pool-threads *thread-pool*))))
    (is (future::queue-empty-p (future::thread-pool-task-queue *thread-pool*)))
    (is (not (future::thread-pool-full-p *thread-pool*)))
    ;;
    (future::assign-task (lambda () (sleep 1)) *thread-pool*)
    (sleep 0.5)
    (future::reset-thread-pool *thread-pool*)
    (is (future::thread-pool-empty-p *thread-pool*))
    (is (= 0 (future::thread-pool-idle-thread-count *thread-pool*)))
    (is (= 0 (length (future::thread-pool-threads *thread-pool*))))
    (is (future::queue-empty-p (future::thread-pool-task-queue *thread-pool*)))
    (is (not (future::thread-pool-full-p *thread-pool*)))
    ;;
    ))


;;; future
(deftest 1+1-is-2 ()
  (assert-no-futures)
  (is (= 2 (touch (future (+ 1 1)))))
  (is (= 2 (touch (future (print 'hello) (+ 1 1)))))
  (assert-no-futures))

#+nil
(deftest error-test ()
  (assert-no-futures)
  (signals error (touch (future (error "error test"))))
  (assert-no-futures))

(deftest future-test ()
  (kill-all-futures)
  (assert-no-futures)
  (let ((f1 (future (sleep 0.1) (+ 1 1)))
        (f2 (future (sleep 0.2) (+ 1 1))))
    (is (= 2 (futures-count)))
    (is (= 4 (+ (touch f1) (touch f2)))))
  (assert-no-futures))

(deftest wait-for-future-test ()
  (kill-all-futures)
  (assert-no-futures)
  (let ((f (future (sleep 0.1) (+ 1 1))))
    (is (= 1 (running-futures-count)))
    (is (= 0 (pending-futures-count)))
    (wait-for-future f)
    (assert-no-futures)
    (is (not (eq (future::result-of f) 'future::unbound)))
    (is (= 2 (touch f)))))

#+nil
(deftest wait-for-all-futures-test ()
  (assert-no-futures) 
  (let ((f1 (future (sleep 0.1) (+ 1 1)))
        (f2 (future (sleep 0.2) (+ 1 1)))
        (f3 (future (+ 1 1))))
    (is (= 3 (futures-count)))
    (wait-for-all-futures)
    (assert-no-futures)
    (is (every (lambda (f) (not (eq (future::result-of f) 'future::unbound)))
               (list f1 f2 f3)))
    (is (= 6 (+ (touch f1) (touch f2) (touch f3))))))

(deftest kill-future-test ()
  (kill-all-futures)
  (assert-no-futures)
  (let* ((f (future (sleep 0.1) (+ 1 1))))
    (is (= 1 (running-futures-count)))
    (is (= 0 (pending-futures-count)))
    (sleep 0.5)
    (kill-future f)
    (assert-no-futures)))

#+nil
(deftest kill-future-force-test ()
  (assert-no-futures)
  (let* ((f (future (+ 1 1)))
         (pid (fork-future::pid-of f)))
    (is (= 1 (running-futures-count)))
    (is (= 0 (pending-futures-count)))
    (sleep 0.5)
    (kill-future f t)
    (assert-no-futures)
    (is (not (probe-file (format nil fork-future::*future-result-file-template* pid))))
    (is (> 0 (fork-future::wait)))
    (is (> 0 (fork-future::waitpid 0)))))

(deftest kill-all-futures-test ()
  (kill-all-futures)
  (assert-no-futures)
  (let* ((f1 (future (sleep 0.1) (+ 1 1)))
         (f2 (future (sleep 0.5) (+ 1 1)))
         (f3 (future (sleep 1) (+ 1 1))))
    (is (= 3 (futures-count)))
    (sleep 0.5)
    (kill-all-futures)
    (assert-no-futures)))

#+nil
(deftest kill-all-futures-force-test ()
  (assert-no-futures)
  (let* ((f1 (future (+ 1 1)))
         (f2 (future (sleep 0.5) (+ 1 1)))
         (f3 (future (sleep 1) (+ 1 1))))
    (is (= 3 (futures-count)))
    (sleep 0.5)
    (kill-all-futures t)
    (assert-no-futures) 
    (is (every (lambda (f) (not (probe-file (format nil fork-future::*future-result-file-template*
                                                    (fork-future::pid-of f)))))
               (list f1 f2 f3)))
    (is (> 0 (fork-future::wait)))
    (is (> 0 (fork-future::waitpid 0)))))


#+nil
(deftest recursive-future-test ()
  (assert-no-futures)
  (let ((f1
         (future
           (+
            (let ((f1 (future (+ 1 1)))
                  (f2 (future (+ 2 2))))
              (is (= 2 (futures-count))) 
              (is (= 6 (+ (touch f1) (touch f2))))
              (+ (touch f1) (touch f2)))
            (let ((f1 (future (+ 1 1)))
                  (f2 (future (+ 2 2))))
              (is (= 2 (futures-count))) 
              (is (= 6 (+ (touch f1) (touch f2))))
              (+ (touch f1) (touch f2)))))))
    (is (= 1 (futures-count)))
    (is (= 12 (touch f1)))))
