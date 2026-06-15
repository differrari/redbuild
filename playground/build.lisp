(load "../v3/redbuild.lisp")

(quick_redb (make-instance `redmod
        :name "play"
        :type :bin
        :target :linux
        :srcs (list "test.c")
) :add-dependencies t :run t :success (lambda () (print "Done")))