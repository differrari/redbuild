(load "../v3/redbuild.lisp")

(redbuild:quick-build (redbuild:make-instance `redbuild:redmod
        :name "play"
        :type :lib
        :target (redbuild:native)
        :srcs (list "test.c" "a.c")
) :add-dependencies t :run t :success (lambda () (print "Done") (print (redbuild:emit-compile-commands))))
