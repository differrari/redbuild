(load "../v3/redbuild.lisp")

(quick_redb (make-instance `redmod
        :name "play"
        :type :lib
        :target :linux
        :srcs (list "test.c" "a.c")
) :add-dependencies t :run t :success (lambda () (print "Done") (emit_compile_commands)))